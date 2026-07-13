import AppKit
import ApplicationServices

/// Handles the one macOS permission Anypaste needs up front: Accessibility.
/// Accessibility access is what lets the app (a) globally observe mouse/keyboard events
/// happening in OTHER apps, and (b) simulate a Cmd+C keypress on your behalf.
enum PermissionsManager {

    /// Returns true if Anypaste already has Accessibility access.
    /// If `prompt` is true and access is missing, macOS shows its own system dialog
    /// asking the user to grant it.
    @discardableResult
    static func ensureAccessibilityAccess(prompt: Bool) -> Bool {
        let options: [String: Any] = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Deep-links straight to the Accessibility pane in System Settings.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
