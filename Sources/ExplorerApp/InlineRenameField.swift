import AppKit
import ExplorerCore

@MainActor
final class RenameTextView: NSTextView {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?
    var onResign: (() -> Void)?
    private var active = true
    private var undoStates: [String] = []
    private var redoStates: [String] = []
    private var lastRecordedValue = ""
    private var lastEditAt = Date.distantPast
    private var restoringHistory = false

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: onCommit?()
        case 53: onCancel?()
        default: super.keyDown(with: event)
        }
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, active {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.active else { return }
                self.onResign?()
            }
        }
        return result
    }

    func beginUndoTracking(with value: String) {
        undoStates.removeAll()
        redoStates.removeAll()
        lastRecordedValue = value
        lastEditAt = .distantPast
    }

    func recordCurrentValue() {
        guard !restoringHistory, string != lastRecordedValue else { return }
        let now = Date()
        if now.timeIntervalSince(lastEditAt) > 0.8 || undoStates.isEmpty {
            undoStates.append(lastRecordedValue)
            if undoStates.count > 100 { undoStates.removeFirst() }
        }
        lastRecordedValue = string
        lastEditAt = now
        redoStates.removeAll()
    }

    func performTextUndo() -> Bool {
        guard let previous = undoStates.popLast() else { return false }
        redoStates.append(string)
        restoreHistoryValue(previous)
        return true
    }

    func performTextRedo() -> Bool {
        guard let next = redoStates.popLast() else { return false }
        undoStates.append(string)
        restoreHistoryValue(next)
        return true
    }

    private func restoreHistoryValue(_ value: String) {
        restoringHistory = true
        string = value
        lastRecordedValue = value
        lastEditAt = .distantPast
        setSelectedRange(NSRange(location: value.utf16.count, length: 0))
        didChangeText()
        restoringHistory = false
    }

    func deactivate() { active = false }
}

@MainActor
private final class RenameOverlayView: NSView, NSTextViewDelegate {
    let editor = RenameTextView()
    var onTextChange: ((String) -> Void)?
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(editor)
        editor.drawsBackground = false
        editor.isRichText = false
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.textContainerInset = NSSize(width: 3, height: 2)
        editor.isHorizontallyResizable = false
        editor.isVerticallyResizable = false
        editor.textContainer?.maximumNumberOfLines = 0
        editor.textContainer?.lineFragmentPadding = 0
        editor.textContainer?.lineBreakMode = .byCharWrapping
        editor.textContainer?.widthTracksTextView = true
        editor.textContainer?.heightTracksTextView = false
        editor.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        editor.frame = bounds.insetBy(dx: 1, dy: 1)
        updateTextContainerWidth()
    }

    private func updateTextContainerWidth() {
        editor.textContainer?.containerSize = NSSize(
            width: max(1, editor.bounds.width - editor.textContainerInset.width * 2),
            height: .greatestFiniteMagnitude)
    }

    func fittingSize(maximumWidth: CGFloat) -> NSSize {
        let textFont = editor.font ?? .systemFont(ofSize: 12)
        let textWidth = ceil((editor.string as NSString).size(withAttributes: [.font: textFont]).width)
        // Include both borders, text insets and room for the insertion caret.
        let width = min(maximumWidth, max(44, textWidth + editor.textContainerInset.width * 2 + 4))
        editor.setFrameSize(NSSize(width: width - 2, height: 22))
        updateTextContainerWidth()
        guard let container = editor.textContainer, let manager = editor.layoutManager else {
            return NSSize(width: width, height: 24)
        }
        manager.ensureLayout(for: container)
        let height = ceil(manager.usedRect(for: container).height) + editor.textContainerInset.height * 2 + 2
        return NSSize(width: width, height: max(24, height))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.textBackgroundColor.setFill()
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 3, yRadius: 3)
        shape.fill()
        NSColor.controlAccentColor.setStroke()
        shape.lineWidth = 1
        shape.stroke()
    }

    func textDidChange(_ notification: Notification) {
        editor.recordCurrentValue()
        onTextChange?(editor.string)
    }
}

@MainActor
final class InlineRenameField: NSTextField {
    private var originalName = ""
    private var submitting = false
    private var onSubmit: ((String) -> Void)?
    private var overlay: RenameOverlayView?
    private weak var previousFirstResponder: NSResponder?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        drawsBackground = false
        isEditable = false
        isSelectable = false
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func beginRenaming(_ name: String, selectStem: Bool, submit: @escaping (String) -> Void) {
        guard let parent = enclosingScrollView?.superview ?? superview, let window else { return }
        finishEditing(restoreOriginal: true)
        originalName = name
        onSubmit = submit
        submitting = true
        stringValue = name
        previousFirstResponder = window.firstResponder

        let overlay = RenameOverlayView(frame: .zero)
        self.overlay = overlay
        // A long name can grow beyond its collection item or table row.
        parent.addSubview(overlay, positioned: .above, relativeTo: nil)
        isHidden = true

        let editor = overlay.editor
        editor.string = name
        editor.beginUndoTracking(with: name)
        editor.font = font ?? .systemFont(ofSize: 12)
        editor.alignment = alignment
        editor.textColor = .labelColor
        editor.onCommit = { [weak self] in self?.commitRename(clearFocus: true) }
        editor.onCancel = { [weak self] in self?.cancelRename() }
        editor.onResign = { [weak self] in self?.commitRename(clearFocus: false) }
        overlay.onTextChange = { [weak self] _ in self?.updateRenameFrame() }
        updateRenameFrame()

        DispatchQueue.main.async { [weak self, weak editor, weak window] in
            guard let self, self.submitting, let editor, let window else { return }
            guard window.makeFirstResponder(editor) else { NSSound.beep(); return }
            let extensionLength = (name as NSString).pathExtension.utf16.count
            let selectionLength = selectStem && extensionLength > 0 ? name.utf16.count - extensionLength - 1 : name.utf16.count
            editor.setSelectedRange(NSRange(location: 0, length: selectionLength))
        }
    }

    private func updateRenameFrame() {
        guard let overlay, let parent = overlay.superview else { return }
        let labelFrame = parent.convert(bounds, from: self)
        let visibleBounds = enclosingScrollView.map { parent.convert($0.contentView.bounds, from: $0.contentView) }
            ?? parent.bounds
        let available = visibleBounds.intersection(parent.bounds).insetBy(dx: 2, dy: 2)
        var size = overlay.fittingSize(maximumWidth: min(max(44, labelFrame.width + 4), available.width))
        if size.height > available.height {
            size = overlay.fittingSize(maximumWidth: available.width)
        }
        let proposedX: CGFloat
        switch alignment {
        case .center: proposedX = labelFrame.midX - size.width / 2
        case .right: proposedX = labelFrame.maxX - size.width + 2
        default: proposedX = labelFrame.minX - 2
        }
        let proposedY = parent.isFlipped ? labelFrame.midY - 12 : labelFrame.midY + 12 - size.height
        let x = min(max(available.minX, proposedX), available.maxX - size.width)
        let y = min(max(available.minY, proposedY), available.maxY - size.height)
        overlay.frame = NSRect(origin: NSPoint(x: x, y: y), size: size)
        overlay.needsLayout = true
        overlay.layoutSubtreeIfNeeded()
    }

    private func finishEditing(restoreOriginal: Bool) {
        guard submitting || overlay != nil else { return }
        submitting = false
        overlay?.editor.deactivate()
        overlay?.removeFromSuperview()
        overlay = nil
        isHidden = false
        if restoreOriginal { stringValue = originalName }
        onSubmit = nil
    }

    @discardableResult
    private func commitRename(clearFocus: Bool) -> Bool {
        guard submitting, let editor = overlay?.editor else { return true }
        let name = editor.string
        do {
            try FileOperationEngine.validateName(name)
            let submit = onSubmit
            let responder = previousFirstResponder
            stringValue = name
            finishEditing(restoreOriginal: false)
            if clearFocus { window?.makeFirstResponder(responder) }
            previousFirstResponder = nil
            submit?(name)
            return true
        } catch {
            NSSound.beep()
            editor.textColor = .systemRed
            editor.toolTip = error.localizedDescription
            window?.makeFirstResponder(editor)
            return false
        }
    }

    private func cancelRename() {
        let responder = previousFirstResponder
        finishEditing(restoreOriginal: true)
        window?.makeFirstResponder(responder)
        previousFirstResponder = nil
    }
}
