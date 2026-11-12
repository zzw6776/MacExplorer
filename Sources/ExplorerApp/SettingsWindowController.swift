import AppKit
import ExplorerCore
import ServiceManagement
import UniformTypeIdentifiers

@MainActor
private final class SettingsWindow: NSWindow {
    weak var recorder: ShortcutRecorder?
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if recorder?.isRecording == true { recorder?.capture(event); return true }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
private final class SettingsPageController: NSViewController {
    var onDisappear: (() -> Void)?
    override func viewWillDisappear() { super.viewWillDisappear(); onDisappear?() }
}

@MainActor
final class ShortcutRecorder: NSButton {
    private(set) var isRecording = false
    var onBegin: (() -> Void)?
    var onFinish: ((LaunchShortcut?) -> Void)?
    var onInvalid: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }
    init() {
        super.init(frame: .zero)
        bezelStyle = .rounded; font = .monospacedSystemFont(ofSize: 15, weight: .medium)
        target = self; action = #selector(begin)
        setAccessibilityLabel(L("text.record.global.shortcut.f10b6307"))
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    @objc private func begin() {
        guard !isRecording else { return }
        onBegin?(); isRecording = true; title = L("text.press.shortcut.95d3d7e8")
        window?.makeFirstResponder(self)
    }
    func cancel() {
        guard isRecording else { return }
        isRecording = false; onFinish?(nil)
    }
    func capture(_ event: NSEvent) {
        guard isRecording else { return }
        if event.keyCode == 53 { cancel(); return }
        let flags = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let shortcut = LaunchShortcut(keyCode: UInt32(event.keyCode), modifiers: flags.rawValue,
                                      character: (event.charactersIgnoringModifiers ?? "").uppercased())
        guard shortcut.isValid else { onInvalid?(); return }
        isRecording = false; onFinish?(shortcut)
    }
    override func keyDown(with event: NSEvent) {
        if isRecording { capture(event) } else { super.keyDown(with: event) }
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let preferences: AppPreferences
    private let shortcutController: GlobalShortcutController
    private let updates: AppUpdateController
    private let automaticChecks = NSButton(checkboxWithTitle: L("text.automatically.check.for.updates.409e6a1a"), target: nil, action: nil)
    private let automaticInstalls = NSButton(checkboxWithTitle: L("text.download.and.install.updates.automatically.c7717897"), target: nil, action: nil)
    private let updateStatus = NSTextField(wrappingLabelWithString: "")
    private let lastUpdateCheck = NSTextField(labelWithString: "")
    private let checkUpdates = NSButton(title: L("text.check.for.updates.c372f825"), target: nil, action: nil)
    private let recorder = ShortcutRecorder()
    private let shortcutEnabled = NSButton(checkboxWithTitle: L("text.enable.global.shortcut.d79e9c90"), target: nil, action: nil)
    private let shortcutStatus = NSTextField(wrappingLabelWithString: "")
    private let launchAtLogin = NSButton(checkboxWithTitle: L("text.open.explorer.at.login.ae999bce"), target: nil, action: nil)
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let loginSettings = NSButton(title: L("text.open.login.items.settings.cab0594e"), target: nil, action: nil)
    private let hidden = NSButton(checkboxWithTitle: L("text.show.hidden.files.and.folders.c73c36d4"), target: nil, action: nil)
    private let startup = NSPopUpButton(), appearance = NSPopUpButton(), viewMode = NSPopUpButton(), scope = NSPopUpButton(), shortcutAction = NSPopUpButton()
    private let terminalApplication = NSPopUpButton(), editorApplication = NSPopUpButton()

    init(preferences: AppPreferences = .shared, shortcutController: GlobalShortcutController, updates: AppUpdateController) {
        self.preferences = preferences; self.shortcutController = shortcutController
        self.updates = updates
        let window = SettingsWindow(contentRect: NSRect(x: 0, y: 0, width: 590, height: 480),
                                    styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init(window: window)
        window.title = L("text.explorer.settings.ff454ece"); window.isReleasedWhenClosed = false
        window.delegate = self; window.recorder = recorder; window.setFrameAutosaveName("Explorer.Settings")
        let tabs = NSTabViewController(); tabs.tabStyle = .toolbar
        let general = NSViewController(); general.view = generalView()
        let keyboard = SettingsPageController(); keyboard.view = keyboardView()
        keyboard.onDisappear = { [weak self] in self?.recorder.cancel() }
        let updatePage = NSViewController(); updatePage.view = updatesView()
        let applications = NSViewController(); applications.view = applicationsView()
        for (controller, title, symbol) in [(general, L("text.general.c910d474"), "gearshape"), (applications, L("text.applications.98e33b0f"), "app.badge"), (keyboard, L("text.shortcut.5753ea37"), "keyboard"), (updatePage, L("text.updates.22e2bada"), "arrow.triangle.2.circlepath")] {
            let item = NSTabViewItem(viewController: controller); item.label = title
            item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); tabs.addTabViewItem(item)
        }
        tabs.preferredContentSize = NSSize(width: 590, height: 480)
        window.contentViewController = tabs; window.center()
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: AppPreferences.changed, object: preferences)
        NotificationCenter.default.addObserver(self, selector: #selector(refresh), name: NSApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(refreshUpdates), name: AppUpdateController.changed, object: updates)
        refresh()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func page(_ title: String, subtitle: String, content: [NSView]) -> NSView {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 590, height: 480))
        let heading = NSTextField(labelWithString: title); heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let caption = note(subtitle)
        let stack = NSStackView(views: [heading, caption] + content)
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 16
        stack.setCustomSpacing(5, after: heading); stack.setCustomSpacing(24, after: caption)
        root.addSubview(stack); stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 28),
                                     stack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -28),
                                     stack.topAnchor.constraint(equalTo: root.topAnchor, constant: 25)])
        for child in stack.arrangedSubviews { child.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        return root
    }
    private func note(_ text: String) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text); label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor; return label
    }
    private func row(_ title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title); label.font = .systemFont(ofSize: 13)
        label.widthAnchor.constraint(equalToConstant: 180).isActive = true
        let stack = NSStackView(views: [label, control]); stack.orientation = .horizontal; stack.spacing = 14
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return stack
    }
    private func popup(_ popup: NSPopUpButton, titles: [String], action: Selector, label: String) {
        popup.addItems(withTitles: titles); popup.target = self; popup.action = action
        popup.setAccessibilityLabel(label)
    }
    private func generalView() -> NSView {
        popup(startup, titles: StartupLocation.allCases.map(\.title), action: #selector(startupChanged), label: L("text.open.new.windows.to.688255ed"))
        popup(appearance, titles: AppAppearance.allCases.map(\.title), action: #selector(appearanceChanged), label: L("text.appearance.3907fa7f"))
        popup(viewMode, titles: FileViewMode.allCases.map(\.title), action: #selector(viewChanged), label: L("text.default.folder.view.1ea848c6"))
        popup(scope, titles: [L("text.current.folder.1a5db523"), L("text.all.subfolders.f25b8ff5")], action: #selector(scopeChanged), label: L("text.default.search.scope.70aaf185"))
        hidden.target = self; hidden.action = #selector(hiddenChanged)
        launchAtLogin.target = self; launchAtLogin.action = #selector(loginChanged)
        launchAtLogin.isEnabled = !DemoData.active
        loginStatus.font = .systemFont(ofSize: 12); loginStatus.textColor = .secondaryLabelColor
        loginSettings.bezelStyle = .rounded; loginSettings.target = self; loginSettings.action = #selector(openLoginSettings)
        return page(L("text.make.explorer.yours.c4b06dc7"), subtitle: L("text.changes.are.saved.automatically.98f075b8"), content: [
            row(L("text.open.new.windows.to.688255ed"), control: startup), row(L("text.appearance.3907fa7f"), control: appearance),
            row(L("text.default.folder.view.1ea848c6"), control: viewMode), row(L("text.default.search.scope.70aaf185"), control: scope),
            hidden, note(L("text.view.and.search.defaults.apply.to.new.tabs.existing.tabs.aba96f55")),
            launchAtLogin, loginStatus, loginSettings
        ])
    }
    private func keyboardView() -> NSView {
        shortcutEnabled.target = self; shortcutEnabled.action = #selector(enabledChanged)
        recorder.widthAnchor.constraint(greaterThanOrEqualToConstant: 155).isActive = true
        recorder.onBegin = { [weak self] in
            try? self?.shortcutController.apply(nil)
            self?.showShortcutStatus(L("text.press.command.control.or.option.plus.a.letter.or.number.86741f00"))
        }
        recorder.onFinish = { [weak self] binding in self?.finishRecording(binding) }
        recorder.onInvalid = { [weak self] in self?.showShortcutStatus(ShortcutError.invalid.localizedDescription, error: true) }
        let reset = NSButton(title: L("text.use.e.5c34b896"), target: self, action: #selector(resetShortcut)); reset.bezelStyle = .rounded
        let controls = NSStackView(views: [recorder, reset]); controls.orientation = .horizontal; controls.spacing = 10
        popup(shortcutAction, titles: [L("text.show.existing.window.cfefa17c"), L("text.open.a.new.window.e0429430")], action: #selector(shortcutActionChanged), label: L("text.shortcut.action.e2a84554"))
        shortcutStatus.font = .systemFont(ofSize: 12); shortcutStatus.textColor = .secondaryLabelColor
        return page(L("text.explorer.one.shortcut.away.6f544a5e"), subtitle: L("text.open.explorer.from.any.app.like.windows.e.2799b548"), content: [
            shortcutEnabled, row(L("text.keyboard.shortcut.cda8fb17"), control: controls), row(L("text.when.pressed.3d1cad83"), control: shortcutAction),
            shortcutStatus,
            note(L("text.click.the.shortcut.to.record.a.new.combination.while.enabled.45245b0c")),
            note(L("text.explorer.must.be.running.closing.all.browser.windows.keeps.the.125bc128"))
        ])
    }
    private func updatesView() -> NSView {
        automaticChecks.target = self; automaticChecks.action = #selector(automaticChecksChanged)
        automaticInstalls.target = self; automaticInstalls.action = #selector(automaticInstallsChanged)
        checkUpdates.bezelStyle = .rounded; checkUpdates.target = updates; checkUpdates.action = #selector(AppUpdateController.checkForUpdates(_:))
        updateStatus.font = .systemFont(ofSize: 12); updateStatus.textColor = .secondaryLabelColor
        lastUpdateCheck.font = .systemFont(ofSize: 12); lastUpdateCheck.textColor = .secondaryLabelColor
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("text.development.21b6a798")
        return page(L("text.keep.explorer.up.to.date.d40df08d"), subtitle: L("text.explorer.argument.b710d6fe", version), content: [
            automaticChecks, automaticInstalls,
            note(L("text.automatic.installation.is.optional.explorer.waits.for.file.operations.to.4f3dfa9b")),
            checkUpdates, lastUpdateCheck, updateStatus
        ])
    }
    private func applicationsView() -> NSView {
        terminalApplication.target = self; terminalApplication.action = #selector(applicationChanged(_:)); terminalApplication.tag = 0
        editorApplication.target = self; editorApplication.action = #selector(applicationChanged(_:)); editorApplication.tag = 1
        terminalApplication.setAccessibilityLabel(L("text.preferred.terminal.application.84449aa7"))
        editorApplication.setAccessibilityLabel(L("text.preferred.text.editor.ebe2faff"))
        return page(L("text.open.with.your.favorite.apps.e3c257cb"), subtitle: L("text.choose.the.apps.used.by.explorer.s.right.click.menu.966c15e5"), content: [
            row(L("text.terminal.e0926fda"), control: terminalApplication),
            note(L("text.open.a.folder.in.terminal.iterm2.or.another.terminal.that.2bd05969")),
            row(L("text.text.editor.95642d5b"), control: editorApplication),
            note(L("text.open.text.code.json.yaml.and.configuration.files.in.your.e43d135d")),
            note(L("text.these.choices.apply.only.to.explorer.s.terminal.and.editor.f9a02b87"))
        ])
    }
    private func refreshApplications() {
        for (role, popup) in [(ExternalApplicationRole.terminal, terminalApplication), (.editor, editorApplication)] {
            popup.removeAllItems()
            popup.addItem(withTitle: L("text.argument.default.d1981f69", role.defaultName))
            let selected = ExternalApplications.choice(for: role, preferences: preferences)
            var choices = role.installedCandidates.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }
            if let selected {
                let url = selected.resolvedURL ?? URL(fileURLWithPath: selected.path)
                if !choices.contains(url) { choices.append(url) }
            }
            var seen = Set<String>()
            for url in choices where seen.insert(url.path).inserted {
                let choice = ApplicationChoice(url: url)
                let isSelected = selected.map { $0.resolvedURL == url || $0.path == url.path } ?? false
                let missing = !ApplicationChoice.isApplication(url)
                popup.addItem(withTitle: ExternalApplications.name(of: url) + (missing ? L("text.not.found.17e70a00") : ""))
                popup.lastItem?.representedObject = isSelected ? (selected ?? choice) : choice
                if isSelected { popup.select(popup.lastItem) }
            }
            popup.menu?.addItem(.separator())
            popup.addItem(withTitle: L("text.choose.application.cc53a4fa")); popup.lastItem?.tag = 999
        }
    }
    @objc private func applicationChanged(_ sender: NSPopUpButton) {
        let role: ExternalApplicationRole = sender.tag == 0 ? .terminal : .editor
        guard sender.selectedItem?.tag == 999 else {
            setApplication(sender.selectedItem?.representedObject as? ApplicationChoice, role: role); return
        }
        refreshApplications()
        guard let window else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = L("text.choose.c7f93783"); panel.message = role == .terminal ? L("text.choose.your.terminal.application.f8a56a4d") : L("text.choose.your.text.editor.c1806bfe")
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            guard ApplicationChoice.isApplication(url), Bundle(url: url)?.bundleIdentifier != Bundle.main.bundleIdentifier else {
                DispatchQueue.main.async { ExternalApplications.showError(L("text.choose.a.terminal.or.text.editor.application.other.than.explorer.3f7f1f50"), window: window) }
                return
            }
            self?.setApplication(ApplicationChoice(url: url), role: role)
        }
    }
    private func setApplication(_ choice: ApplicationChoice?, role: ExternalApplicationRole) {
        if role == .terminal { preferences.terminalApplication = choice }
        else { preferences.editorApplication = choice }
    }
    @objc private func refreshUpdates() {
        automaticChecks.state = updates.automaticallyChecks ? .on : .off
        automaticChecks.isEnabled = updates.isAvailable
        automaticInstalls.state = updates.automaticallyInstalls ? .on : .off
        automaticInstalls.isEnabled = updates.isAvailable && updates.automaticallyChecks
        checkUpdates.isEnabled = updates.canCheck
        updateStatus.stringValue = updates.status
        lastUpdateCheck.stringValue = updates.lastCheck.map { L("text.last.checked.argument.8363f753", $0.formatted(date: .abbreviated, time: .shortened)) } ?? L("text.not.checked.yet.881d23f6")
    }
    @objc private func automaticChecksChanged() { updates.automaticallyChecks = automaticChecks.state == .on }
    @objc private func automaticInstallsChanged() { updates.automaticallyInstalls = automaticInstalls.state == .on }
    @objc private func refresh() {
        startup.selectItem(at: StartupLocation.allCases.firstIndex(of: preferences.startupLocation) ?? 0)
        appearance.selectItem(at: AppAppearance.allCases.firstIndex(of: preferences.appearance) ?? 0)
        viewMode.selectItem(at: FileViewMode.allCases.firstIndex(of: preferences.viewMode) ?? 0)
        scope.selectItem(at: preferences.searchScope == .folder ? 0 : 1)
        hidden.state = preferences.showHidden ? .on : .off
        shortcutEnabled.state = preferences.shortcutEnabled ? .on : .off
        shortcutAction.selectItem(at: preferences.shortcutOpensNewWindow ? 1 : 0)
        if !recorder.isRecording { recorder.title = preferences.shortcut.title; updateShortcutStatus() }
        refreshLoginStatus()
        refreshUpdates()
        refreshApplications()
    }
    private func refreshLoginStatus() {
        let state = SMAppService.mainApp.status
        launchAtLogin.state = state == .enabled || state == .requiresApproval ? .on : .off
        loginSettings.isHidden = state != .requiresApproval
        switch state {
        case .enabled: loginStatus.stringValue = L("text.explorer.will.open.when.you.sign.in.72bf81f9")
        case .requiresApproval: loginStatus.stringValue = L("text.allow.explorer.in.macos.login.items.to.finish.enabling.this.1b22e16c")
        case .notRegistered: loginStatus.stringValue = L("text.off.enable.to.have.the.global.shortcut.ready.after.login.52cf4aac")
        case .notFound: loginStatus.stringValue = L("text.off.enable.to.register.this.copy.of.explorer.for.login.5fecd6b7")
        @unknown default: loginStatus.stringValue = L("text.login.status.is.unavailable.2045f627")
        }
    }
    private func showShortcutStatus(_ text: String, error: Bool = false) {
        shortcutStatus.stringValue = text; shortcutStatus.textColor = error ? .systemRed : .secondaryLabelColor
    }
    private func updateShortcutStatus() {
        if !preferences.shortcutEnabled { showShortcutStatus(L("text.global.shortcut.is.off.bf77326e")) }
        else if shortcutController.activeShortcut == preferences.shortcut { showShortcutStatus(L("text.argument.is.ready.to.open.explorer.133abeb4", preferences.shortcut.title)) }
        else { showShortcutStatus(L("text.the.shortcut.is.unavailable.choose.another.combination.or.turn.it.fa71107f"), error: true) }
    }
    private func finishRecording(_ binding: LaunchShortcut?) {
        do {
            try shortcutController.apply(preferences.shortcutEnabled ? (binding ?? preferences.shortcut) : nil)
            if let binding { preferences.shortcut = binding }
            recorder.title = preferences.shortcut.title; updateShortcutStatus()
        } catch {
            let message = error.localizedDescription
            // Recording temporarily releases the old key; restore it on failure/cancel.
            try? shortcutController.apply(preferences.shortcutEnabled ? preferences.shortcut : nil)
            recorder.title = preferences.shortcut.title
            showShortcutStatus(message + (shortcutController.activeShortcut != nil ? L("text.your.previous.shortcut.is.still.active.9e5bf42d") : ""), error: true)
        }
    }
    @objc private func enabledChanged() {
        recorder.cancel()
        do {
            let enabled = shortcutEnabled.state == .on
            try shortcutController.apply(enabled ? preferences.shortcut : nil)
            preferences.shortcutEnabled = enabled; updateShortcutStatus()
        } catch {
            shortcutEnabled.state = preferences.shortcutEnabled ? .on : .off
            showShortcutStatus(error.localizedDescription, error: true)
        }
    }
    @objc private func resetShortcut() { recorder.cancel(); finishRecording(.defaultShortcut) }
    @objc private func startupChanged() { preferences.startupLocation = StartupLocation.allCases[startup.indexOfSelectedItem] }
    @objc private func appearanceChanged() { preferences.appearance = AppAppearance.allCases[appearance.indexOfSelectedItem] }
    @objc private func viewChanged() { preferences.viewMode = FileViewMode.allCases[viewMode.indexOfSelectedItem] }
    @objc private func scopeChanged() { preferences.searchScope = scope.indexOfSelectedItem == 0 ? .folder : .subfolders }
    @objc private func hiddenChanged() { preferences.showHidden = hidden.state == .on }
    @objc private func shortcutActionChanged() { preferences.shortcutOpensNewWindow = shortcutAction.indexOfSelectedItem == 1 }
    @objc private func loginChanged() {
        do {
            if launchAtLogin.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus(); loginStatus.stringValue = L("text.could.not.update.login.settings.argument.89d2e074", error.localizedDescription)
        }
    }
    @objc private func openLoginSettings() { SMAppService.openSystemSettingsLoginItems() }
    func windowWillClose(_ notification: Notification) { recorder.cancel() }
    func windowDidResignKey(_ notification: Notification) { recorder.cancel() }
}
