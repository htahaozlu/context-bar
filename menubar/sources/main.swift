import AppKit
import Foundation

// Register bundled JetBrains Mono before any view (or the status item) builds.
Fonts.registerBundled()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
