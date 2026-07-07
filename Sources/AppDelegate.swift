import Cocoa
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var imageView: ImageView!
    private var pendingURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenu()
        setupWindow()

        // Priority: CLI argument > Finder-opened file > last viewed image.
        let args = CommandLine.arguments.dropFirst()
        if let path = args.first {
            imageView.load(url: URL(fileURLWithPath: path))
        } else if let pendingURL {
            imageView.load(url: pendingURL)
        } else if let lastPath = UserDefaults.standard.string(forKey: "lastImagePath"),
                  FileManager.default.fileExists(atPath: lastPath) {
            imageView.load(url: URL(fileURLWithPath: lastPath))
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    // Called when an image is opened via Finder ("Open With" / double-click / drag onto Dock icon).
    // Can arrive before applicationDidFinishLaunching, i.e. before the window exists.
    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if let imageView {
            imageView.load(url: url)
        } else {
            pendingURL = url
        }
        return true
    }

    private func setupWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 960, height: 600)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "LaViewer"
        window.titlebarAppearsTransparent = true
        window.minSize = NSSize(width: 480, height: 320)
        if let screen = NSScreen.main {
            window.setFrame(screen.visibleFrame, display: true)
        } else {
            window.center()
        }

        imageView = ImageView(frame: contentRect)
        window.contentView = imageView
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(imageView)
    }

    private func setupMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit LaViewer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let fileMenuItem = NSMenuItem()
        mainMenu.addItem(fileMenuItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "Open…", action: #selector(openDocument), keyEquivalent: "o")
        let closeItem = NSMenuItem(title: "Close", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "w")
        closeItem.keyEquivalentModifierMask = .control
        fileMenu.addItem(closeItem)
        fileMenuItem.submenu = fileMenu

        NSApplication.shared.mainMenu = mainMenu
    }

    @objc private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            imageView.load(url: url)
        }
    }
}
