import AppKit
import Carbon
import ExplorerCore

/// Finder owns the native Get Info UI. Paths are Apple-event parameters, never
/// interpolated AppleScript source, and no keyboard/UI scripting is involved.
actor FinderInformation {
    static let shared = FinderInformation()
    static func arguments(for urls: [URL]) -> NSAppleEventDescriptor {
        let list = NSAppleEventDescriptor.list()
        for (index, url) in urls.enumerated() { list.insert(NSAppleEventDescriptor(string: url.path), at: index + 1) }
        return list
    }
    func show(_ urls: [URL]) -> String? {
        let source = """
        on run itemPaths
            tell application "Finder"
                repeat with itemPath in itemPaths
                    set targetItem to (POSIX file (contents of itemPath)) as alias
                    open information window of targetItem
                end repeat
                activate
            end tell
        end run
        """
        guard let script = NSAppleScript(source: source) else { return L("text.could.not.prepare.finder.s.get.info.command.7aea821d") }
        let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEOpenApplication),
                                          targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
        event.setParam(Self.arguments(for: urls), forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        script.executeAppleEvent(event, error: &error)
        guard let error else { return nil }
        if (error[NSAppleScript.errorNumber] as? NSNumber)?.intValue == -1743 {
            return L("text.allow.explorer.to.control.finder.in.system.settings.privacy.security.17bb9a75")
        }
        return error[NSAppleScript.errorMessage] as? String ?? L("text.finder.could.not.open.get.info.for.this.selection.7e66e2e2")
    }
}

@MainActor
enum FileProperties {
    static func show(_ urls: [URL], window: NSWindow?) {
        guard !urls.isEmpty, urls.allSatisfy(\.isFileURL) else { return }
        Task {
            if let error = await FinderInformation.shared.show(urls) {
                let alert = NSAlert(); alert.messageText = L("text.couldn.t.open.properties.a5384b35"); alert.informativeText = error
                if let window, window.attachedSheet == nil { await alert.beginSheetModal(for: window) }
                else { alert.runModal() }
            }
        }
    }
    static func item(urls: [URL], window: NSWindow?) -> NSMenuItem {
        ContextMenu.item(L("text.properties.ae43692b"), symbol: "info.circle") { [weak window] in show(urls, window: window) }
    }
}
