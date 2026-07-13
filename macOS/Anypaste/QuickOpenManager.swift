import AppKit

/// Watches for Cmd+Option+O and opens the current destination file in its default app
/// (whatever you have set as the default handler for .md files).
final class QuickOpenManager {

    private var monitor: Any?

    // Virtual keycode 31 is the physical position of the "O" key on a standard layout.
    private let oKeyCode: UInt16 = 31

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.keyCode == self.oKeyCode,
                  event.modifierFlags.contains([.command, .option]) else { return }
            self.openCurrentFile()
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func openCurrentFile() {
        guard let url = DestinationFileManager.shared.currentFileURL else { return }
        NSWorkspace.shared.open(url)
    }
}
