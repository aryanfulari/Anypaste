import AppKit

/// Watches for the "Option + drag-select" gesture anywhere on screen.
///
/// How it works: once "Three Finger Drag" is turned on in Trackpad > Accessibility settings,
/// macOS itself translates a three-finger drag into an ordinary left-mouse-drag before any
/// app ever sees it — so there's nothing trackpad-specific to detect here. This class just
/// watches for a left-mouse-drag that happens while the Option key is held down. When the
/// drag ends, it simulates Cmd+C to copy whatever text ended up selected in the frontmost
/// app, reads that text off the clipboard, and appends it to the destination file.
final class TextCaptureManager {

    private var monitor: Any?
    private var isOptionHeld = false
    private var dragStartedWithOption = false

    func start() {
        // A *global* monitor observes events happening in OTHER applications (a local
        // monitor would only see events inside Anypaste itself). This requires
        // Accessibility permission, which AppDelegate confirms before calling start().
        monitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.flagsChanged, .leftMouseDragged, .leftMouseUp]
        ) { [weak self] event in
            self?.handle(event)
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .flagsChanged:
            // Swapped .option for .function (the Fn / Globe key)
            isOptionHeld = event.modifierFlags.contains(.function)

        case .leftMouseDragged:
            if isOptionHeld {
                dragStartedWithOption = true
            }

        case .leftMouseUp:
            if dragStartedWithOption {
                dragStartedWithOption = false
                captureSelection()
            }

        default:
            break
        }
    }

    private func captureSelection() {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousItems = snapshotPasteboard(pasteboard)

        simulateCommandC()

        // Give the frontmost app a moment to respond to the copy command before reading
        // the clipboard back.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            defer { self.restorePasteboard(previousItems) }

            guard pasteboard.changeCount != previousChangeCount,
                  let text = pasteboard.string(forType: .string),
                  !text.isEmpty else {
                return
            }
            DestinationFileManager.shared.appendText(text)
        }
    }

    // We hijack the system clipboard to do the copy, so we snapshot it first and restore
    // it afterwards — this way Anypaste never clobbers whatever you last manually copied.
    private func snapshotPasteboard(_ pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]]? {
        pasteboard.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        }
    }

    private func restorePasteboard(_ items: [[NSPasteboard.PasteboardType: Data]]?) {
        guard let items else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let newItems = items.map { dict -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(newItems)
    }

    /// Posts synthetic keyDown/keyUp events for Cmd+C, as if the user pressed it themselves.
    /// Virtual keycode 8 is the physical position of the "C" key — virtual keycodes track
    /// physical key position, not the character printed on the key, so this works regardless
    /// of keyboard layout.
    private func simulateCommandC() {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 8, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
