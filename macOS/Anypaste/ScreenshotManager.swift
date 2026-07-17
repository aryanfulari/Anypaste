import AppKit

/// Watches for option +. and, when pressed, runs macOS's own interactive screenshot
/// tool so you can drag out a custom area, then appends the result to the destination file.
final class ScreenshotManager {

    private var monitor: Any?

    
    // Virtual keycode 44 is the physical position of the "/" key on a standard layout.
    private let slashKeyCode: UInt16 = 44

    func start() {
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            // Check if our base keys (Option + /) are pressed
            guard let self, event.keyCode == self.slashKeyCode,
                  event.modifierFlags.contains(.option) else { return }
            
            // If Shift is ALSO held, trigger a full-screen capture
            if event.modifierFlags.contains(.shift) {
                self.captureFullScreen()
            } else {
                self.captureArea()
            }
        }
    }

    private func captureArea() {
        // -i opens the interactive selection tool
        performCapture(arguments: ["-i", "-c"], isFullScreen: false)
    }

    private func captureFullScreen() {
        // Running screencapture without -i instantly captures the whole screen
        performCapture(arguments: ["-c"], isFullScreen: true)
    }

    private func performCapture(arguments: [String], isFullScreen: Bool) {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount

        DispatchQueue.global(qos: .userInitiated).async {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
            task.arguments = arguments
            try? task.run()
            task.waitUntilExit()

            DispatchQueue.main.async {
                guard pasteboard.changeCount != previousChangeCount,
                      let imageData = self.pngData(from: pasteboard) else {
                    return // User cancelled or capture failed
                }
                // Pass the image data and the flag to the updated DestinationFileManager
                DestinationFileManager.shared.appendImage(imageData, isFullScreen: isFullScreen)
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
