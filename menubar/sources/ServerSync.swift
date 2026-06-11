import AppKit
import Foundation

/// HTTP client that mirrors the local SQLite rollups + settings to a
/// self-hosted server (`context-bar-server` Rust crate). Designed to be
/// called opportunistically — never blocking the menubar UI tick.
///
/// ## Push
///   POST {server}/v1/ingest   {machine, schema, agents[...]}     — atomic upsert
///   GET  {server}/v1/rollups  → [machine, agent, …]              — combine view
///
/// ## Pull
///   GET  {server}/v1/rollups  → mirror other machines into LocalStore
///
/// The server URL is the only setting the user has to know. Auth is a
/// per-install API token generated on first launch; the server stores it
/// and returns it in the install response so the client can save it in
/// the Keychain. (See `context-bar-server` for the protocol docs.)

final class ServerSync {
    static let shared = ServerSync()

    /// Default cadence: never push faster than once every `minInterval` so a
    /// runaway timer can't DoS the user's server. 60s matches the engine
    /// tick + a small jitter.
    private let minInterval: TimeInterval = 60

    private var lastPushedAt: Date?
    private let queue = DispatchQueue(label: "com.htahaozlu.contextbar.serversync", qos: .utility)

    private init() {}

    var serverURL: String? {
        get {
            UserDefaults.standard.string(forKey: "serverSync.url")
        }
        set {
            if let v = newValue, !v.isEmpty {
                UserDefaults.standard.set(v, forKey: "serverSync.url")
            } else {
                UserDefaults.standard.removeObject(forKey: "serverSync.url")
            }
            LocalStore.shared.updateSyncStatus(serverURL: newValue)
        }
    }

    var apiToken: String? {
        get { UserDefaults.standard.string(forKey: "serverSync.token") }
        set { UserDefaults.standard.set(newValue, forKey: "serverSync.token") }
    }

    /// Last sync status for the Status view in Settings → Across your Macs.
    var status: LocalStore.SyncStatus { LocalStore.shared.getSyncStatus() }

    /// Convenience for the settings Status pill. `idle` = enabled but quiet,
    /// `disabled` = no server URL set, `syncing` = a push/pull is in flight,
    /// `error` = last attempt failed.
    enum State { case disabled, idle, syncing, error(String) }
    var state: State {
        if serverURL?.isEmpty != false { return .disabled }
        if syncInFlight { return .syncing }
        let s = status
        if s.lastStatus == "error" {
            return .error(s.lastMessage ?? "unknown")
        }
        return .idle
    }

    /// Set when a push/pull is mid-flight. The Settings view observes this
    /// via `observeState` to spin the status pill without polling.
    private(set) var syncInFlight: Bool = false
    private var observers: [UUID: (State) -> Void] = [:]
    private let obsLock = NSLock()

    func observeState(_ cb: @escaping (State) -> Void) -> UUID {
        obsLock.lock(); defer { obsLock.unlock() }
        let id = UUID()
        observers[id] = cb
        return id
    }
    func unobserve(_ id: UUID) {
        obsLock.lock(); defer { obsLock.unlock() }
        observers.removeValue(forKey: id)
    }
    private func notify() {
        obsLock.lock()
        let snapshot = Array(observers.values)
        obsLock.unlock()
        let s = self.state
        DispatchQueue.main.async { for cb in snapshot { cb(s) } }
    }

    /// Push THIS machine's rollups to the server. No-op when:
    ///   - no server URL set
    ///   - last push was < `minInterval` ago (rate limit)
    ///   - already in flight
    func pushIfDue() {
        guard let url = serverURL, !url.isEmpty else { return }
        if let last = lastPushedAt, Date().timeIntervalSince(last) < minInterval { return }
        if syncInFlight { return }
        syncInFlight = true; notify()
        let payload = buildPayload()
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.syncInFlight = false
                DispatchQueue.main.async { self.notify() }
            }
            self.post(url: url, path: "/v1/ingest", body: payload) { result in
                self.lastPushedAt = Date()
                switch result {
                case .success:
                    LocalStore.shared.updateSyncStatus(
                        pushedAt: Date(), status: "ok", message: nil)
                case .failure(let err):
                    LocalStore.shared.updateSyncStatus(
                        pushedAt: Date(), status: "error", message: err.message)
                }
                DispatchQueue.main.async { self.notify() }
            }
        }
    }

    /// Pull every machine's rollups from the server. Mirrors them into the
    /// local store so the Across-your-Macs view can show the combined total
    /// offline too.
    func pullIfDue(force: Bool = false) {
        guard let url = serverURL, !url.isEmpty else { return }
        if !force, let pulled = status.lastPulledAt,
           Date().timeIntervalSince(pulled) < minInterval { return }
        if syncInFlight { return }
        syncInFlight = true; notify()
        queue.async { [weak self] in
            guard let self else { return }
            defer {
                self.syncInFlight = false
                DispatchQueue.main.async { self.notify() }
            }
            self.get(url: url, path: "/v1/rollups") { result in
                switch result {
                case .success(let data):
                    if let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let items = any["rollups"] as? [[String: Any]] {
                        for r in items {
                            let machine = (r["machine"] as? String) ?? "?"
                            let agent = (r["agent"] as? String) ?? "?"
                            let tokens = UInt64((r["tokens_30d"] as? Double) ?? 0)
                            let cost = (r["cost_30d"] as? Double) ?? 0
                            let sub = UInt64((r["subagent_tokens_30d"] as? Double) ?? 0)
                            LocalStore.shared.upsertRollup(
                                machine: machine, agent: agent,
                                tokens30d: tokens, cost30d: cost, subagent30d: sub)
                        }
                    }
                    LocalStore.shared.updateSyncStatus(
                        pulledAt: Date(), status: "ok", message: nil)
                case .failure(let err):
                    LocalStore.shared.updateSyncStatus(
                        pulledAt: Date(), status: "error", message: err.message)
                }
                DispatchQueue.main.async { self.notify() }
            }
        }
    }

    /// Manual sync: push then pull. Used by the "Sync now" button.
    func syncNow(completion: ((State) -> Void)? = nil) {
        guard let url = serverURL, !url.isEmpty else {
            completion?(.disabled); return
        }
        syncInFlight = true; notify()
        let payload = buildPayload()
        queue.async { [weak self] in
            guard let self else { return }
            self.post(url: url, path: "/v1/ingest", body: payload) { pushResult in
                self.get(url: url, path: "/v1/rollups") { pullResult in
                    if case .failure(let err) = pushResult {
                        LocalStore.shared.updateSyncStatus(
                            pushedAt: Date(), status: "error", message: err.message)
                    } else {
                        LocalStore.shared.updateSyncStatus(
                            pushedAt: Date(), status: "ok", message: nil)
                    }
                    if case .success(let data) = pullResult,
                       let any = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let items = any["rollups"] as? [[String: Any]] {
                        for r in items {
                            LocalStore.shared.upsertRollup(
                                machine: (r["machine"] as? String) ?? "?",
                                agent: (r["agent"] as? String) ?? "?",
                                tokens30d: UInt64((r["tokens_30d"] as? Double) ?? 0),
                                cost30d: (r["cost_30d"] as? Double) ?? 0,
                                subagent30d: UInt64((r["subagent_tokens_30d"] as? Double) ?? 0))
                        }
                        LocalStore.shared.updateSyncStatus(
                            pulledAt: Date(), status: "ok", message: nil)
                    }
                    self.syncInFlight = false
                    let s = self.state
                    DispatchQueue.main.async {
                        self.notify()
                        completion?(s)
                    }
                }
            }
        }
    }

    /// Validate the URL by GETting `/v1/health`. Returns nil on success,
    /// an error message on failure. Used by the Settings Status pill
    /// "Test connection" button.
    func testConnection(completion: @escaping (Result<String, ServerSyncError>) -> Void) {
        guard let url = serverURL, !url.isEmpty else {
            completion(.failure(SyncError(message: "No server URL set"))); return
        }
        get(url: url, path: "/v1/health") { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let data):
                    if let s = String(data: data, encoding: .utf8) {
                        completion(.success(s))
                    } else {
                        completion(.failure(SyncError(message: "Could not decode response")))
                    }
                case .failure(let err):
                    completion(.failure(err))
                }
            }
        }
    }

    // MARK: - private

    struct ServerSyncError: Error { let message: String }
    private typealias SyncError = ServerSyncError

    private func buildPayload() -> [String: Any] {
        let machine = MachineSync.machineName
        var agents: [String: [String: Any]] = [:]
        for r in LocalStore.shared.allRollups() where r.machine == machine {
            agents[r.agent] = [
                "tokens_30d": r.tokens30d,
                "cost_30d": r.cost30d,
                "subagent_tokens_30d": r.subagent30d,
            ]
        }
        return [
            "schema": 2,
            "machine": machine,
            "updated_at": LocalStore.iso8601(Date()),
            "agents": agents,
        ]
    }

    private func post(url base: String, path: String, body: [String: Any],
                      completion: @escaping (Result<Void, SyncError>) -> Void) {
        guard let req = makeRequest(url: base, path: path, method: "POST", body: body) else {
            completion(.failure(SyncError(message: "Bad URL"))); return
        }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(.failure(SyncError(message: err.localizedDescription))); return }
            guard let http = resp as? HTTPURLResponse else {
                completion(.failure(SyncError(message: "No response"))); return
            }
            if !(200..<300).contains(http.statusCode) {
                let body = String(data: data ?? Data(), encoding: .utf8) ?? ""
                completion(.failure(SyncError(message: "HTTP \(http.statusCode) — \(body.prefix(200))")))
                return
            }
            completion(.success(()))
        }.resume()
    }

    private func get(url base: String, path: String,
                     completion: @escaping (Result<Data, SyncError>) -> Void) {
        guard let req = makeRequest(url: base, path: path, method: "GET", body: nil) else {
            completion(.failure(SyncError(message: "Bad URL"))); return
        }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            if let err { completion(.failure(SyncError(message: err.localizedDescription))); return }
            guard let http = resp as? HTTPURLResponse else {
                completion(.failure(SyncError(message: "No response"))); return
            }
            if !(200..<300).contains(http.statusCode) {
                completion(.failure(SyncError(message: "HTTP \(http.statusCode)")))
                return
            }
            completion(.success(data ?? Data()))
        }.resume()
    }

    private func makeRequest(url base: String, path: String, method: String,
                             body: [String: Any]?) -> URLRequest? {
        // Tolerate a missing scheme (e.g. user typed "home.local:7878") by
        // prepending http:// — the server is self-hosted and probably isn't
        // behind TLS in a homelab.
        var u = base
        if !u.lowercased().hasPrefix("http://") && !u.lowercased().hasPrefix("https://") {
            u = "http://" + u
        }
        // Strip a trailing slash so base + path doesn't produce `//v1/...`.
        while u.hasSuffix("/") { u.removeLast() }
        guard let full = URL(string: u + path) else { return nil }
        var req = URLRequest(url: full)
        req.httpMethod = method
        req.timeoutInterval = 8
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("context-bar/0.7.10", forHTTPHeaderField: "User-Agent")
        if let t = apiToken, !t.isEmpty {
            req.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            req.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [.fragmentsAllowed])
        }
        return req
    }
}
