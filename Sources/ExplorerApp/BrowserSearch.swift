import AppKit
import ExplorerCore

extension BrowserViewController {
    func tabTitle(_ tab: BrowserTab) -> String {
        tab.isRecursiveSearch ? L("text.argument.search.results.in.argument.d0e89524", tab.query, title(for: tab.history.current)) : title(for: tab.history.current)
    }

    func updateSearchControls() {
        searchOptions.isHidden = tab.isThisMac
        closeSearchButton?.isHidden = tab.query.isEmpty
        updateSearchMenuState()
        pathBar.update(tab.history.current, searchResults: tab.isRecursiveSearch ? title(for: tab.history.current) : nil)
        tabChips[tab.id]?.update(title: tabTitle(tab), active: true)
        workspace?.updateWindowTitle()
        if tab.isThisMac {
            search.placeholderString = L("text.search.this.mac.6a2313de"); search.setAccessibilityLabel(L("text.search.drives.and.network.locations.a97b0df9"))
            search.toolTip = L("text.filter.drives.and.cloud.folders.by.name.or.account.3ec8011d"); return
        }
        let recursive = tab.searchScope == .subfolders
        search.placeholderString = L("text.search.argument.bb32c4e3", title(for: tab.history.current))
        search.setAccessibilityLabel(recursive ? L("text.search.folder.and.subfolders.41cfeedc") : L("text.filter.this.folder.789c5511"))
        search.toolTip = recursive ? L("text.find.names.in.argument.and.its.subfolders.7bc9d356", tab.history.current.path) : L("text.filter.names.in.the.current.folder.8dab1e79")
    }

    func searchOptionsMenu() -> NSMenu {
        let menu = NSMenu(); menu.autoenablesItems = false
        let title = NSMenuItem(title: L("text.search.options.556a0850"), action: nil, keyEquivalent: "")
        title.image = Palette.buttonSymbol("doc.text.magnifyingglass", size: 14, canvas: 18); menu.addItem(title)
        for (label, tag, action) in [(L("text.current.folder.1a5db523"), 1, #selector(changeSearchScope(_:))),
                                    (L("text.all.subfolders.f25b8ff5"), 2, #selector(changeSearchScope(_:))),
                                    (L("text.stop.search.58bc1824"), 3, #selector(stopSearch)),
                                    (L("text.search.again.998195e4"), 4, #selector(submitSearch))] {
            if tag == 3 { menu.addItem(.separator()) }
            let item = NSMenuItem(title: label, action: action, keyEquivalent: "")
            item.tag = tag; item.target = self; menu.addItem(item)
        }
        return menu
    }
    func updateSearchMenuState() {
        for item in searchOptions.menu?.items ?? [] {
            switch item.tag {
            case 1: item.state = tab.searchScope == .folder ? .on : .off
            case 2: item.state = tab.searchScope == .subfolders ? .on : .off
            case 3: item.isEnabled = tab.searchTask != nil
            case 4: item.isEnabled = !tab.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            default: break
            }
        }
    }
    func layoutSearchTools(width: CGFloat) {
        let compact = width < 1040
        let title = compact ? L("text.search.49c266ba") : L("text.search.options.556a0850")
        if searchOptions.menu?.items.first?.title != title { searchOptions.menu?.items.first?.title = title }
        let optionsWidth: CGFloat = compact ? 86 : 132, closeWidth: CGFloat = compact ? 32 : 110
        if searchOptionsWidth?.constant != optionsWidth { searchOptionsWidth?.constant = optionsWidth }
        if closeSearchWidth?.constant != closeWidth { closeSearchWidth?.constant = closeWidth }
        let closeTitle = compact ? "" : L("text.close.search.55656b5e")
        if closeSearchButton?.title != closeTitle {
            closeSearchButton?.title = closeTitle
            closeSearchButton?.imagePosition = compact ? .imageOnly : .imageLeading
        }
    }
    @objc func changeSearchScope(_ sender: NSMenuItem) {
        let scope: SearchScope = sender.tag == 1 ? .folder : .subfolders
        guard scope != tab.searchScope else { return }
        rememberSelection(); tab.searchScope = scope
        loadFolder(clear: true); updateSearchControls()
    }
    func closeSearch(focusFiles: Bool = true) {
        guard !tab.query.isEmpty else {
            if focusFiles { view.window?.makeFirstResponder(activeFileView) }
            return
        }
        rememberSelection(); cancelSearchWork(); closeQuickLook()
        tab.query = ""; search.stringValue = ""
        loadFolder(clear: true)
        if focusFiles { view.window?.makeFirstResponder(activeFileView) }
    }
    @objc func submitSearch() {
        guard !tab.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { focusFilter(); return }
        if tab.isRecursiveSearch { startSearch() }
        else if tab.isThisMac { storageChanged() }
        else { applyView() }
    }
    func focusRecursiveSearch() {
        if tab.isThisMac { focusFilter(); return }
        if tab.searchScope != .subfolders { tab.searchScope = .subfolders; loadFolder(clear: true) }
        updateSearchControls(); focusFilter()
    }
    func cancelSearchWork() {
        tab.searchTask?.cancel(); tab.searchTask = nil; tab.searchGeneration = UUID()
    }
    @objc func stopSearch() {
        guard tab.searchTask != nil else { return }
        cancelSearchWork(); tab.loading = false; tab.searchStopped = true
        updateStatus(); updateEmptyState()
    }
    func startSearch(debounce: Bool = false) {
        cancelSearchWork(); tab.loadTask?.cancel(); tab.sortTask?.cancel(); refreshTask?.cancel()
        watcher = nil; watcherURL = nil; watcherTabID = nil
        let tab = self.tab, generation = tab.searchGeneration
        let root = tab.history.current, query = tab.query, hidden = showHidden
        tab.searchScanned = 0; tab.searchSkipped = 0; tab.searchLimited = false; tab.searchStopped = false
        tab.error = nil; tab.loading = true; tab.items = []; tab.clearVisible()
        suppressSelection = true; cancelVisibleThumbnails(); table.reloadData(); collection.reloadData()
        table.deselectAll(nil); collection.selectionIndexPaths = []; suppressSelection = false
        applyPresentationMode(); updateSearchControls(); updateQuickLookSelection(); updateEmptyState()
        tab.searchTask = Task { [weak self, weak tab] in
            if debounce { try? await Task.sleep(for: .milliseconds(300)) }
            guard !Task.isCancelled, let self, let tab, self.tab === tab, tab.searchGeneration == generation else { return }
            let worker = Task.detached(priority: .userInitiated) { [self, tab] in
                try await DirectorySearch.run(root: root, query: query, showHidden: hidden) { update in
                    await MainActor.run { [self, tab] in
                        guard self.tab === tab, tab.searchGeneration == generation else { return }
                        tab.searchScanned = update.scanned; tab.searchSkipped = update.unreadableFolders; tab.searchLimited = update.reachedLimit
                        if !update.matches.isEmpty {
                            tab.scrollPositions[self.scrollKey] = self.activeScroll.contentView.bounds.origin.y
                            tab.items.append(contentsOf: update.matches); self.applyView()
                        }
                        self.updateStatus()
                    }
                }
            }
            do {
                _ = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled, self.tab === tab, tab.searchGeneration == generation else { return }
                tab.loading = false; tab.searchTask = nil; self.updateStatus(); self.updateEmptyState()
            } catch {
                guard !Task.isCancelled, self.tab === tab, tab.searchGeneration == generation else { return }
                tab.loading = false; tab.searchTask = nil; tab.error = error.localizedDescription
                self.updateStatus(); self.updateEmptyState()
            }
        }
        updateStatus()
    }
    func updateSearchStatus() {
        if tab.loading { progress.startAnimation(nil) } else { progress.stopAnimation(nil) }
        let count = tab.visible.count, scanned = tab.searchScanned
        if tab.error != nil { status.stringValue = L("text.search.unavailable.23ae8063"); detail.stringValue = ""; return }
        status.stringValue = L("text.argument.results.2edd6105", count)
        if !selectedItems.isEmpty { status.stringValue += L("text.argument.selected.b78421e3", selectedItems.count) }
        if tab.loading { detail.stringValue = L("text.searching.argument.checked.c3568a31", scanned) }
        else if tab.searchStopped { detail.stringValue = L("text.stopped.partial.results.fcc2c6d9") }
        else if tab.searchLimited { detail.stringValue = L("text.20.000.result.limit.refine.search.6f3efb24") }
        else { detail.stringValue = tab.searchSkipped > 0 ? L("text.argument.folders.unreadable.a1c480f6", tab.searchSkipped) : L("text.search.complete.227a147b") }
        if tab.loading, tab.searchSkipped > 0 { detail.stringValue += L("text.argument.unreadable.fc0784f7", tab.searchSkipped) }
    }
    func suspend() {
        closeQuickLook(); cancelSearchWork(); tab.loadTask?.cancel(); tab.sortTask?.cancel(); refreshTask?.cancel()
        watcher = nil; watcherURL = nil; watcherTabID = nil; cancelVisibleThumbnails(); tab.loading = false
    }
    @objc func openContainingFolder() {
        guard let item = selectedItems.first else { return }
        revealInContainingFolder(item.url)
    }
    func revealInContainingFolder(_ file: URL) {
        guard view.window?.attachedSheet == nil else { return }
        workspace?.activate(self)
        navigate(file.deletingLastPathComponent())
        tab.pendingSelections[tab.selectionKey] = [FileOperationController.itemPath(file)]
        view.window?.makeFirstResponder(activeFileView)
    }
    @objc func favoritesChanged() {
        guard isViewLoaded else { return }
        let pinned = FavoriteStore.shared.favorites.contains(tab.history.current)
        pinButton?.isEnabled = !tab.isThisMac
        pinButton?.active = pinned
        pinButton?.toolTip = pinned ? L("text.unpin.current.folder.d.b3dd99ff") : L("text.pin.current.folder.d.17b29efc")
        pinButton?.setAccessibilityLabel(pinned ? L("text.unpin.current.folder.from.favorites.21ff9e5f") : L("text.pin.current.folder.to.favorites.71f4a6fe"))
    }
    func togglePin() { if !tab.isThisMac { FavoriteStore.shared.toggle(tab.history.current) } }
    @objc func pinSelectedFolder() {
        if let item = selectedItems.first, item.isNavigable { FavoriteStore.shared.toggle(item.url) }
    }
    @objc func openSelectedInOtherPane() {
        if let item = selectedItems.first, item.isNavigable { workspace?.openOtherPane(item.url) }
    }
    func transferToOtherPane(move: Bool) { workspace?.transfer(from: self, move: move) }
    func updateTransferButtons() {
        copyOtherButton?.isEnabled = workspace?.canTransfer(from: self, move: false) == true
        moveOtherButton?.isEnabled = workspace?.canTransfer(from: self, move: true) == true
    }
}
