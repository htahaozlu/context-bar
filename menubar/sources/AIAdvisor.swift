import Foundation
import Security

/// BYO-key AI usage advisor (C-tier flagship). The user connects their OWN
/// Gemini or OpenAI key; we send a COMPACT, aggregates-only usage summary (never
/// raw transcripts, never project names) to their chosen provider and surface
/// actionable recommendations to cut token cost + improve context efficiency.
/// Opt-in. Nothing leaves the machine unless a key is set and the user asks.

enum AIProvider: String, CaseIterable {
    case off, openai, gemini

    var label: String {
        switch self {
        case .off: return L10n.text("Off", "Kapalı")
        case .openai: return "OpenAI"
        case .gemini: return "Gemini"
        }
    }

    /// A capable, cheap default model per provider (user's key, user's bill).
    var model: String {
        switch self {
        case .openai: return "gpt-4o-mini"
        case .gemini: return "gemini-2.0-flash"
        case .off: return ""
        }
    }
}

// MARK: - Provider preference (UserDefaults) + API key (Keychain)

extension DisplayPrefs {
    private static let kAIProvider = "displayPrefs.aiProvider"
    static var aiProvider: AIProvider {
        get { AIProvider(rawValue: UserDefaults.standard.string(forKey: kAIProvider) ?? "") ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: kAIProvider) }
    }
}

/// API keys live in the Keychain, never UserDefaults / never the snapshot.
enum AIKeychain {
    private static let service = "com.htahaozlu.contextbar.ai-key"

    static func save(_ key: String, for provider: AIProvider) {
        delete(for: provider)
        guard !key.isEmpty else { return }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecValueData as String: Data(key.utf8),
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(q as CFDictionary, nil)
    }

    static func load(for provider: AIProvider) -> String? {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data, let s = String(data: data, encoding: .utf8), !s.isEmpty
        else { return nil }
        return s
    }

    static func delete(for provider: AIProvider) {
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: provider.rawValue,
        ]
        SecItemDelete(q as CFDictionary)
    }

    static func hasKey(for provider: AIProvider) -> Bool { load(for: provider) != nil }
}

// MARK: - Compact, privacy-safe usage summary

/// Aggregates only — token buckets, cache ratio, sub-agent share, top models,
/// cost + projection, context-window pressure. NO project names, NO transcripts.
enum AIUsageSummary {
    static func build() -> String {
        let path = ContextSnapshot.resolveSnapshotPath()
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return "{}" }

        func agentSummary(_ a: [String: Any]?) -> [String: Any]? {
            guard let a else { return nil }
            func u(_ k: String) -> UInt64 {
                if let n = a[k] as? UInt64 { return n }
                if let n = a[k] as? Int, n >= 0 { return UInt64(n) }
                if let d = a[k] as? Double, d >= 0 { return UInt64(d) }
                return 0
            }
            func d(_ k: String) -> Double { (a[k] as? Double) ?? Double(u(k)) }
            let totalFresh = u("total_tokens_30d")
            let cacheRead = u("cache_read_tokens_30d")
            let subagent = u("subagent_tokens_30d")
            let models = (a["by_model"] as? [[String: Any]] ?? [])
                .sorted { (($0["tokens"] as? Double) ?? 0) > (($1["tokens"] as? Double) ?? 0) }
                .prefix(4)
                .compactMap { $0["model"] as? String }
            return [
                "fresh_tokens_30d": totalFresh,
                "input_30d": u("total_input_30d"),
                "output_30d": u("total_output_30d"),
                "cache_read_tokens_30d": cacheRead,
                "cache_read_to_fresh_ratio": totalFresh > 0 ? round(Double(cacheRead) / Double(totalFresh) * 10) / 10 : 0,
                "subagent_share_pct": totalFresh > 0 ? Int(Double(subagent) / Double(totalFresh) * 100) : 0,
                "cost_30d_usd": round(d("total_cost_30d") * 100) / 100,
                "cost_today_usd": round(d("cost_today") * 100) / 100,
                "cache_savings_30d_usd": round(d("cache_savings_30d") * 100) / 100,
                "last_context_pct": a["last_context_pct"] as? Double ?? 0,
                "top_models": Array(models),
            ]
        }

        var summary: [String: Any] = ["note": "API-equivalent estimates from local transcripts; subscription users are not billed per token."]
        if let c = agentSummary(root["claude"] as? [String: Any]) { summary["claude"] = c }
        if let x = agentSummary(root["codex"] as? [String: Any]) { summary["codex"] = x }
        let json = (try? JSONSerialization.data(withJSONObject: summary, options: [.sortedKeys, .prettyPrinted]))
            .flatMap { String(data: $0, encoding: .utf8) }
        return json ?? "{}"
    }

    static let systemPrompt = """
    You are a usage-efficiency advisor for AI coding agents (Claude Code, Codex). \
    You receive a 30-day usage summary (API-equivalent cost ESTIMATES from local \
    transcripts — the user is on a subscription, not billed per token). Give 3–5 \
    specific, actionable recommendations to cut token cost and improve context \
    efficiency. Ground every point in the numbers provided. Focus where the data \
    points: cache-read dominance (replayed context billed at 0.1x input — huge by \
    volume), sub-agent / multi-agent burn (Anthropic reports multi-agent runs use \
    ~15x the tokens of a chat), context-window growth over long sessions, and model \
    choice (Opus vs Sonnet vs Haiku). Be concrete and plain. No preamble, no \
    disclaimers about being an AI. Output short markdown bullets.
    """
}

// MARK: - LLM call

enum AIAdvisorError: Error { case noKey, badResponse(String) }

enum AIAdvisor {
    /// Build the summary, POST it to the user's provider, return the advice text.
    static func analyze(completion: @escaping (Result<String, Error>) -> Void) {
        let provider = DisplayPrefs.aiProvider
        guard provider != .off, let key = AIKeychain.load(for: provider) else {
            completion(.failure(AIAdvisorError.noKey)); return
        }
        let summary = AIUsageSummary.build()
        let userMsg = "Here is my 30-day AI coding usage summary (JSON):\n\n\(summary)"

        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 45
        let session = URLSession(configuration: cfg)

        let req: URLRequest
        let parse: (Data) -> String?
        switch provider {
        case .openai:
            (req, parse) = openAIRequest(key: key, model: provider.model, user: userMsg)
        case .gemini:
            (req, parse) = geminiRequest(key: key, model: provider.model, user: userMsg)
        case .off:
            completion(.failure(AIAdvisorError.noKey)); return
        }

        session.dataTask(with: req) { data, resp, err in
            let done: (Result<String, Error>) -> Void = { r in DispatchQueue.main.async { completion(r) } }
            if let err { done(.failure(err)); return }
            guard let data else { done(.failure(AIAdvisorError.badResponse("empty"))); return }
            if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let body = String(data: data, encoding: .utf8) ?? ""
                done(.failure(AIAdvisorError.badResponse("HTTP \(http.statusCode): \(body.prefix(300))"))); return
            }
            if let text = parse(data), !text.isEmpty { done(.success(text)) }
            else { done(.failure(AIAdvisorError.badResponse("could not parse provider response"))) }
        }.resume()
    }

    private static func openAIRequest(key: String, model: String, user: String) -> (URLRequest, (Data) -> String?) {
        var req = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": AIUsageSummary.systemPrompt],
                ["role": "user", "content": user],
            ],
            "temperature": 0.3,
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let parse: (Data) -> String? = { data in
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = j["choices"] as? [[String: Any]],
                  let msg = choices.first?["message"] as? [String: Any],
                  let content = msg["content"] as? String else { return nil }
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (req, parse)
    }

    private static func geminiRequest(key: String, model: String, user: String) -> (URLRequest, (Data) -> String?) {
        let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent?key=\(key)")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": AIUsageSummary.systemPrompt]]],
            "contents": [["role": "user", "parts": [["text": user]]]],
            "generationConfig": ["temperature": 0.3],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        let parse: (Data) -> String? = { data in
            guard let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let cands = j["candidates"] as? [[String: Any]],
                  let content = cands.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]] else { return nil }
            let text = parts.compactMap { $0["text"] as? String }.joined()
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (req, parse)
    }
}
