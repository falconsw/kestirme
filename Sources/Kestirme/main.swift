import AppKit

let arguments = CommandLine.arguments

if arguments.contains("--render") || arguments.contains("--dump") {
    // Developer tools: render the panel offscreen or print an app's menu shortcuts.
    _ = NSApplication.shared
    NSApp.setActivationPolicy(.prohibited)
    MainActor.assumeIsolated { DevTools.run(arguments) }
    exit(0)
}

let app = NSApplication.shared
let delegate = AppController.shared
app.delegate = delegate
app.run()
