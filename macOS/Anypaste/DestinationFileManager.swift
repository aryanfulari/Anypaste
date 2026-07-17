import AppKit
import UniformTypeIdentifiers

/// Owns "which file is Anypaste currently appending to" and all the actual disk writes.
final class DestinationFileManager {

    static let shared = DestinationFileManager()

    private let defaultsKey = "AnypasteDestinationPath"
    private let recentsKey = "AnypasteRecentFiles"
    private let maxRecents = 3

    /// The markdown file currently receiving captures. Persisted across launches via UserDefaults.
    private(set) var currentFileURL: URL?

    /// Most-recently-used destination files, newest first, capped at 3. Persisted across launches.
    private(set) var recentFileURLs: [URL] = []

    private init() {
        if let path = UserDefaults.standard.string(forKey: defaultsKey) {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.path) {
                currentFileURL = url
            }
        }
        if let paths = UserDefaults.standard.stringArray(forKey: recentsKey) {
            recentFileURLs = paths
                .map { URL(fileURLWithPath: $0) }
                .filter { FileManager.default.fileExists(atPath: $0.path) }
        }
    }

    var currentFileName: String {
        currentFileURL?.lastPathComponent ?? "No file selected"
    }

    /// Opens a save panel so the user can create a brand-new markdown file anywhere on disk.
    func createNewFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSSavePanel()
        panel.title = "Create New Anypaste File"
        panel.nameFieldStringValue = "Anypaste.md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let header = "# Anypaste Log\n\n"
            try? header.write(to: url, atomically: true, encoding: .utf8)
            self?.setCurrentFile(url)
        }
    }

    /// Opens an open panel so the user can pick an existing file to append to.
    func chooseExistingFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Choose Destination File"
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.setCurrentFile(url)
        }
    }

    private func setCurrentFile(_ url: URL) {
        currentFileURL = url
        UserDefaults.standard.set(url.path, forKey: defaultsKey)
        addToRecents(url)
        NotificationCenter.default.post(name: .anypasteDestinationChanged, object: nil)
    }

    private func addToRecents(_ url: URL) {
        recentFileURLs.removeAll { $0.path == url.path }
        recentFileURLs.insert(url, at: 0)
        if recentFileURLs.count > maxRecents {
            recentFileURLs = Array(recentFileURLs.prefix(maxRecents))
        }
        UserDefaults.standard.set(recentFileURLs.map(\.path), forKey: recentsKey)
    }

    /// Switches straight to one of the recent files — used by the "Recent Files" menu.
    func selectRecentFile(_ url: URL) {
        setCurrentFile(url)
    }

    /// Appends a block of captured text to the destination file as its own markdown paragraph.
    func appendText(_ text: String) {
        appendRaw(text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n")
    }

    /// Saves screenshot data next to the destination file and appends a centered HTML image link.
    func appendImage(_ imageData: Data, isFullScreen: Bool) {
        guard let fileURL = currentFileURL else { return }

        let assetsFolder = fileURL.deletingLastPathComponent().appendingPathComponent("AnypasteAssets")
        try? FileManager.default.createDirectory(at: assetsFolder, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let imageName = "screenshot_\(formatter.string(from: Date())).png"
        let imageURL = assetsFolder.appendingPathComponent(imageName)

        do {
            try imageData.write(to: imageURL)
            
            // Define the HTML image tag based on the capture type
            let imgTag = isFullScreen
                ? "<img src=\"AnypasteAssets/\(imageName)\" width=\"900\">"
                : "<img src=\"AnypasteAssets/\(imageName)\">"
                
            // Wrap the image in a centered paragraph tag
            let formattedOutput = "<p align=\"center\">\n  \(imgTag)\n</p>\n\n"
            
            appendRaw(formattedOutput)
        } catch {
            NSLog("Anypaste: failed to save screenshot – \(error)")
        }
    }

    private func appendRaw(_ string: String) {
        guard let fileURL = currentFileURL, let data = string.data(using: .utf8) else { return }

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? Data().write(to: fileURL)
        }

        if let handle = try? FileHandle(forWritingTo: fileURL) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
            NotificationCenter.default.post(name: .anypasteCaptureSucceeded, object: nil)
        }
    }
}

extension Notification.Name {
    static let anypasteDestinationChanged = Notification.Name("anypasteDestinationChanged")
    static let anypasteCaptureSucceeded = Notification.Name("anypasteCaptureSucceeded")
}
