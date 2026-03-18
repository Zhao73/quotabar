import Cocoa

let application = NSApplication.shared
let delegate = MainActor.assumeIsolated { CodexTokenAppDelegate() }
application.delegate = delegate
application.setActivationPolicy(.accessory)

withExtendedLifetime(delegate) {
    application.run()
}
