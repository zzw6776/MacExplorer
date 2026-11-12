import AppKit
import ExplorerCore

@MainActor
final class FavoriteStore {
    static let shared = FavoriteStore()
    static let changed = Notification.Name("ExplorerFavoritesChanged")
    private(set) var favorites: Favorites
    private init() {
        if DemoData.active { favorites = DemoData.favorites; return }
        if let data = UserDefaults.standard.data(forKey: "explorer.favorites.v1"),
           let stored = try? JSONDecoder().decode(Favorites.self, from: data) {
            favorites = Favorites(stored.items)
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let folders = [("Desktop", L("text.desktop.9bd88f24")), ("Downloads", L("text.downloads.d5fdc1af")), ("Documents", L("text.documents.b4e929d8")), ("Pictures", L("text.pictures.1e624500"))]
            favorites = Favorites([Favorite(url: home, name: L("text.home.3a786953"))] + folders.map { Favorite(url: home.appendingPathComponent($0.0), name: $0.1) })
        }
    }
    func toggle(_ url: URL) {
        guard url.isFileURL else { return }
        if favorites.contains(url) { favorites.unpin(url) } else { favorites.pin(url) }
        save()
    }
    func move(_ id: UUID, by offset: Int) { favorites.move(id, by: offset); save() }
    private func save() {
        if let data = try? JSONEncoder().encode(favorites) { UserDefaults.standard.set(data, forKey: "explorer.favorites.v1") }
        NotificationCenter.default.post(name: Self.changed, object: nil)
    }
}
