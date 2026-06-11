import AppKit
import CoreText
import Foundation

// MARK: - Bundled fonts
//
// The redesign sets every number in JetBrains Mono (tabular). The faces are
// shipped inside the app bundle (Resources/Fonts) and registered for this
// process at launch so `NSFont(name: "JetBrainsMono-…")` resolves without the
// user installing anything. If registration ever fails, Typography.mono falls
// back to the system monospaced-digit font.

enum Fonts {
    private static var didRegister = false

    private static let faces = [
        "JetBrainsMono-Regular",
        "JetBrainsMono-Medium",
        "JetBrainsMono-SemiBold",
        "JetBrainsMono-Bold",
    ]

    /// Register the bundled JetBrains Mono faces. Idempotent; call as early as
    /// possible (before any view builds) so tabular numbers render correctly.
    static func registerBundled() {
        guard !didRegister else { return }
        didRegister = true
        for face in faces {
            guard let url = fontURL(face) else { continue }
            var error: Unmanaged<CFError>?
            // `.process` scope: visible to this app only, no install prompt.
            // A non-fatal failure (e.g. already registered) is ignored on purpose.
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }

    private static func fontURL(_ face: String) -> URL? {
        if let url = Bundle.main.url(forResource: face, withExtension: "ttf", subdirectory: "Fonts") {
            return url
        }
        if let url = Bundle.main.url(forResource: face, withExtension: "ttf") {
            return url
        }
        // Dev builds run from the repo working tree without a packaged bundle.
        let repo = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("menubar/assets/fonts/\(face).ttf")
        return FileManager.default.fileExists(atPath: repo.path) ? repo : nil
    }
}
