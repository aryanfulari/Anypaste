import SwiftUI

// The @main entry point. Anypaste has no windows — it's a pure menu bar app — so the
// Scene here is just a placeholder. All real work happens in AppDelegate, which we hook
// in via @NSApplicationDelegateAdaptor.
@main
struct AnypasteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
