import AppKit

/// Watches for option +. and, when pressed, runs macOS's own interactive screenshot
/// tool so you can drag out a custom area, then appends the result to the destination file.
final class ScreenshotManager {

    private var monitor: Any?

    
    // Virtual keycode 44 is the physical position of the "/" key on a standard layout.
    private let slashKeyCode: UInt16 = 44

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self, event.keyCode == self.slashKeyCode,
                  event.modifierFlags.contains(.option) else { return }
            self.captureArea()
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func captureArea() {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount

        // screencapture -i blocks until the user finishes dragging a selection
        // -c sends the result straight to the clipboard
        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = ["-i", "-c"]
            try? task.run()
            task.waitUntilExit()

            DispatchQueue.main.async {
                guard pasteboard.changeCount != previousChangeCount,
                      let imageData = self.pngData(from: pasteboard) else {
                    // User pressed Esc to cancel — nothing landed on the clipboard.
                    return
                }
                DestinationFileManager.shared.appendImage(imageData)
            }
        }
    }

    // screencapture typically places a TIFF representation on the clipboard rather than
    // PNG, so we convert it ourselves before saving.
    private func pngData(from pasteboard: NSPasteboard) -> Data? {
        if let png = pasteboard.data(forType: .png) {
            return png
        }
        if let tiff = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: tiff) {
            return rep.representation(using: .png, properties: [:])
        }
        return nil
    }
}
