import AppKit
import ExplorerCore

enum FileAction: String, CaseIterable {
    case cut, copy, paste, move, rename, newFolder, trash, compress, extract, properties, undo, cancel
    var title: String {
        switch self {
        case .cut: L("text.cut.1f45f025")
        case .copy: L("text.copy.e21f935f")
        case .paste: L("text.paste.f3380f7b")
        case .move: L("text.move.to.folder.99742d10")
        case .rename: L("text.rename.6fa62b3d")
        case .newFolder: L("text.new.folder.633810e9")
        case .trash: L("text.move.to.trash.9adcdf33")
        case .compress: L("text.compress.to.zip.83cbfce7")
        case .extract: L("text.extract.all.0311fbf1")
        case .properties: L("text.properties.ae43692b")
        case .undo: L("text.undo.a8283ade")
        case .cancel: L("text.cancel.operation.8c5701a8")
        }
    }
}

@MainActor
final class FileOperationController {
    static let shared = FileOperationController()
    static let changed = Notification.Name("ExplorerFileOperationsChanged")
    static let finished = Notification.Name("ExplorerFileOperationsFinished")
    private let engine = FileOperationEngine()
    private var task: Task<Void, Never>?
    private var cutChangeCount: Int?
    private var cutURLs: [URL] = []
    private var clipboardTimer: Timer?
    private(set) var busy = false
    private(set) var statusText = ""
    private(set) var undoTitle: String?
    var canPaste: Bool { !busy && !clipboardURLs.isEmpty }
    var cutPaths: Set<String> {
        guard cutChangeCount == NSPasteboard.general.changeCount else { return [] }
        return Set(cutURLs.map(\.path))
    }
    static func itemPath(_ url: URL) -> String {
        let item = url.standardizedFileURL
        return item.deletingLastPathComponent().resolvingSymlinksInPath().appendingPathComponent(item.lastPathComponent).path
    }
    private var clipboardURLs: [URL] {
        (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []).filter(\.isFileURL)
    }
    private init() {
        // NSPasteboard has no change notification. Poll only while a cut is pending.
    }
    private func notify() { NotificationCenter.default.post(name: Self.changed, object: nil) }
    func copy(_ urls: [URL], cut: Bool) {
        guard !busy, !urls.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents(); pasteboard.writeObjects(urls as [NSURL])
        cutURLs = cut ? urls : []; cutChangeCount = cut ? pasteboard.changeCount : nil
        clipboardTimer?.invalidate(); clipboardTimer = nil
        if cut {
            clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    if self.cutChangeCount != NSPasteboard.general.changeCount { self.clearCut() }
                }
            }
        }
        statusText = cut ? L("text.argument.cut.paste.to.move.80397d14", urls.count) : L("text.argument.copied.efdb487e", urls.count)
        notify()
    }
    func clearCut() {
        cutURLs = []; cutChangeCount = nil; clipboardTimer?.invalidate(); clipboardTimer = nil; statusText = ""; notify()
    }
    func paste(into folder: URL, window: NSWindow) {
        let urls = clipboardURLs
        guard !busy, !urls.isEmpty else { return }
        let cut = cutChangeCount == NSPasteboard.general.changeCount
        let clipboardVersion = NSPasteboard.general.changeCount
        run(cut ? .move(urls, to: folder) : .copy(urls, to: folder), window: window) { [weak self] report in
            guard let self, cut, self.cutChangeCount == clipboardVersion,
                  NSPasteboard.general.changeCount == clipboardVersion else { return }
            let consumed = Set(report.consumedSources.map(Self.itemPath))
            let remaining = urls.filter { !consumed.contains(Self.itemPath($0)) }
            if remaining.isEmpty {
                NSPasteboard.general.clearContents(); self.clearCut()
            } else if remaining.count != urls.count { self.copy(remaining, cut: true) }
        }
    }
    func cancel() {
        guard busy else { clearCut(); return }
        task?.cancel(); statusText = L("text.cancelling.after.the.current.item.94343bba"); notify()
    }
    func run(_ operation: FileOperation, window: NSWindow, completion: ((OperationReport) -> Void)? = nil) {
        // Sheet completion handlers run just before AppKit detaches the sheet.
        // The queued Task starts after that handler returns.
        guard !busy else { return }
        busy = true; statusText = L("text.preparing.argument.e24788c1", operation.title.lowercased()); notify()
        task = Task {
            let report = await engine.perform(operation, resolve: { [weak self, weak window] conflict in
                guard let self, let window else { return ConflictResolution(.cancel) }
                return await self.resolve(conflict, window: window)
            }, progress: { [weak self] progress in await self?.showProgress(progress) })
            undoTitle = await engine.undoTitle
            busy = false; task = nil; completion?(report)
            finish(report, title: operation.title, window: window)
        }
    }
    func undo(window: NSWindow) {
        guard !busy, undoTitle != nil, window.attachedSheet == nil else { return }
        busy = true; statusText = L("text.checking.items.for.undo.210e62e1"); notify()
        task = Task {
            let report = await engine.undo(progress: { [weak self] progress in await self?.showProgress(progress) })
            undoTitle = await engine.undoTitle; busy = false; task = nil
            finish(report, title: L("text.undo.a8283ade"), window: window)
        }
    }
    private func showProgress(_ progress: OperationProgress) {
        statusText = L("text.argument.argument.of.argument.argument.bf7338ae", progress.title, progress.index, progress.total, progress.item); notify()
    }
    private func finish(_ report: OperationReport, title: String, window: NSWindow) {
        statusText = report.cancelled ? L("text.cancelled.completed.items.can.be.undone.bb7ef0d3") : L("text.argument.complete.74b43d7c", title)
        if report.skipped > 0 { statusText += L("text.argument.skipped.926f5b7c", report.skipped) }
        notify()
        NotificationCenter.default.post(name: Self.finished, object: nil,
                                        userInfo: ["completed": report.completed, "metadataOnly": report.metadataOnly])
        if let error = report.error {
            let alert = NSAlert(); alert.alertStyle = .warning
            alert.messageText = L("text.argument.couldn.t.finish.adbb179e", title)
            alert.informativeText = error + (report.completed.isEmpty ? "" : L("text.completed.items.are.still.available.in.undo.88c0c40b"))
            alert.addButton(withTitle: L("text.ok.565339bc")); alert.beginSheetModal(for: window)
        }
    }
    private func resolve(_ conflict: FileConflict, window: NSWindow) async -> ConflictResolution {
        guard !Task.isCancelled else { return ConflictResolution(.cancel) }
        let alert = NSAlert(); alert.alertStyle = .warning
        alert.messageText = L("text.argument.already.exists.ceed4197", conflict.destination.lastPathComponent)
        alert.informativeText = L("text.from.argument.to.argument.308d8413", conflict.source.path, conflict.destination.path) +
            (conflict.destinationIsDirectory ? L("text.replace.sends.the.entire.existing.folder.to.trash.folders.are.f9d63708") : L("text.replace.sends.the.existing.item.to.trash.so.it.can.e32a5736"))
        // Keep Both is the safe default. Escape cancels the remaining batch.
        [L("text.keep.both.38b99fe6"), L("text.replace.95e15439"), L("text.skip.28d03596"), L("text.cancel.19766ed6")].forEach { alert.addButton(withTitle: $0) }
        alert.buttons[3].keyEquivalent = "\u{1b}"
        alert.showsSuppressionButton = true; alert.suppressionButton?.title = L("text.apply.to.all.remaining.conflicts.a3aa3cf9")
        let response = await alert.beginSheetModal(for: window)
        let choice: ConflictChoice
        switch response {
        case .alertFirstButtonReturn: choice = .keepBoth
        case .alertSecondButtonReturn: choice = .replace
        case .alertThirdButtonReturn: choice = .skip
        default: choice = .cancel
        }
        return ConflictResolution(choice, applyToAll: alert.suppressionButton?.state == .on)
    }

    func askName(title: String, initial: String, selectStem: Bool, window: NSWindow,
                 submit: @escaping (String) -> Void) {
        guard !busy, window.attachedSheet == nil else { return }
        let alert = NSAlert(); alert.messageText = title
        alert.addButton(withTitle: title == L("text.new.folder.c75ba807") ? L("text.create.4759498a") : L("text.rename.3064d79a")); alert.addButton(withTitle: L("text.cancel.19766ed6"))
        let field = NSTextField(string: initial); field.frame = NSRect(x: 0, y: 0, width: 340, height: 26)
        field.setAccessibilityLabel(L("text.name.dcd1d522")); alert.accessoryView = field; alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            do { try FileOperationEngine.validateName(field.stringValue); submit(field.stringValue) }
            catch {
                let errorAlert = NSAlert(); errorAlert.messageText = L("text.that.name.can.t.be.used.337c8d3b")
                errorAlert.informativeText = error.localizedDescription; errorAlert.beginSheetModal(for: window)
            }
        }
        field.selectText(nil)
        if selectStem, let editor = field.currentEditor() {
            let ext = (initial as NSString).pathExtension
            let length = (initial as NSString).length - (ext.isEmpty ? 0 : (ext as NSString).length + 1)
            editor.selectedRange = NSRange(location: 0, length: length)
        }
    }
}
