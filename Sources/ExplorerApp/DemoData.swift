import AppKit
import ExplorerCore

/// Only the separate bundle produced by scripts/demo.sh enables this mode.
/// Sample drives are fictional; file browsing still uses ordinary temporary files.
@MainActor
enum DemoData {
    static var active: Bool { Bundle.main.object(forInfoDictionaryKey: "ExplorerDemo") as? Bool == true }
    static var root: URL {
        URL(fileURLWithPath: Bundle.main.object(forInfoDictionaryKey: "ExplorerDemoRoot") as? String ?? "/tmp/MacExplorer Demo", isDirectory: true)
    }
    static var favorites: Favorites {
        let folders = [("Projects", L("text.projects.04e2a972")), ("Documents", L("text.documents.b4e929d8")),
                       ("Pictures", L("text.pictures.1e624500")), ("Downloads", L("text.downloads.d5fdc1af"))]
        return Favorites([Favorite(url: root, name: L("text.home.3a786953"))] + folders.map {
            Favorite(url: root.appendingPathComponent($0.0), name: $0.1)
        })
    }
    static var session: WorkspaceSession {
        WorkspaceSession(left: PaneSession(paths: [BrowserLocation.stored(BrowserLocation.thisMac), root.appendingPathComponent("Projects").path,
                                                   root.appendingPathComponent("Pictures").path]))
    }
    static var locations: [StorageLocation] {
        let gb: Int64 = 1_000_000_000
        func drive(_ path: String, _ title: String, _ kind: StorageLocation.Kind, total: Int64, free: Int64) -> StorageLocation {
            StorageLocation(url: root.appendingPathComponent("Devices/" + path), title: title,
                            detail: kind == .internalDrive ? L("text.local.disk.8c755697") : kind == .network ? L("text.network.drive.e5c4e330") : L("text.external.volume.a4deb99e"),
                            kind: kind, capacity: StorageCapacity(total: total * gb, available: free * gb))
        }
        let google = root.appendingPathComponent("Cloud/Google Drive")
        let googleTitle = L("text.google.drive.915ef4ba"), googleDetail = googleTitle + " · demo@example.test"
        return [drive("Macintosh HD", L("text.macintosh.hd.a9fdbf3a"), .internalDrive, total: 1000, free: 428),
                drive("Studio SSD", L("text.studio.ssd.dccd7888"), .externalDrive, total: 2000, free: 1240),
                drive("Archive", L("text.archive.66f4804e"), .externalDrive, total: 500, free: 34),
                drive("Shared Projects", L("text.shared.projects.0b47e3bf"), .network, total: 4000, free: 2160),
                StorageLocation(url: google, title: googleTitle, detail: googleDetail, kind: .googleDrive, children: [
                    StorageLocation(url: google.appendingPathComponent("My Drive"), title: L("text.my.drive.428d9cf8"), detail: googleDetail, kind: .googleDrive),
                    StorageLocation(url: google.appendingPathComponent("Shared drives"), title: L("text.shared.drives.bae61950"), detail: googleDetail, kind: .googleDrive)
                ]),
                StorageLocation(url: root.appendingPathComponent("Cloud/OneDrive"), title: L("text.onedrive.8a7a54d3"), detail: L("text.sample.workspace.01822ab0"), kind: .cloud)]
    }
    static func configure() {
        guard active else { return }
        UserDefaults.standard.setVolatileDomain([
            "explorer.shortcut.enabled": false, "explorer.appearance": "light", "explorer.showHidden": false,
            "explorer.searchScope": "subfolders", "explorer.viewMode": "details", "explorer.startup": "restore"
        ], forName: UserDefaults.argumentDomain)
    }
    static func exportScreenshot(of controller: ExplorerWindowController) throws {
        guard active, let window = controller.window, let frame = window.contentView?.superview,
              let output = Bundle.main.object(forInfoDictionaryKey: "ExplorerScreenshotDirectory") as? String else { return }
        frame.layoutSubtreeIfNeeded()
        guard let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) else { return }
        frame.cacheDisplay(in: frame.bounds, to: bitmap)
        let name = controller.workspace.dualPane ? "dual-pane" : controller.browser.tab.hasSearchQuery ? "search" : controller.browser.tab.isThisMac ? "this-mac" : "files"
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
    }
}
