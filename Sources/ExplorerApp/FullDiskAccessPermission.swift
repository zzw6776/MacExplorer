import AppKit

enum FullDiskAccessPermission {
    private static let protectedDirectories = [
        "Library/Containers/com.apple.stocks",
        "Library/Safari"
    ]

    static func isGranted(fileManager: FileManager = .default) -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser
        return protectedDirectories.contains { relativePath in
            let url = home.appendingPathComponent(relativePath, isDirectory: true)
            return (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) != nil
        }
    }

    /// Keeps guiding development builds to System Settings until Full Disk
    /// Access is granted. Once granted, subsequent rebuilds stay silent.
    static func shouldRequestOnLaunch() -> Bool {
        guard Bundle.main.object(forInfoDictionaryKey: "ExplorerDevelopmentBuild") as? Bool == true else { return false }
        return !isGranted()
    }

    @MainActor
    static func request() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
}
