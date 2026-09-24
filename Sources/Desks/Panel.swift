import AppKit

final class Panel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static var main: Panel? { NSApp.windows.first { $0 is Panel } as? Panel }

    private var pending: ((NSTextView) -> Void)?
    private var striking = false
    private var depth = 0
    private var observer: NSObjectProtocol?

    init(frame: NSRect) {
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .floating
        isFloatingPanel = true
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        observer = NotificationCenter.default.addObserver(forName: NSText.didChangeNotification, object: nil, queue: nil) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, self.striking, let editor = note.object as? NSTextView, editor === self.firstResponder else { return }
                self.strike(editor, true)
            }
        }
    }

    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if depth == 0, striking, let editor = firstResponder as? NSTextView { strike(editor, false) }
        depth += 1
        let made = super.makeFirstResponder(responder)
        depth -= 1
        if depth == 0 {
            if let editor = firstResponder as? NSTextView { pending?(editor) }
            pending = nil
        }
        return made
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown { pending = nil }
        super.sendEvent(event)
    }

    func expect(_ setup: @escaping (NSTextView) -> Void) {
        pending = setup
    }

    func strike(_ editor: NSTextView, _ on: Bool) {
        striking = on
        let all = NSRange(location: 0, length: (editor.string as NSString).length)
        if on {
            editor.textStorage?.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: all)
            editor.typingAttributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        } else {
            editor.textStorage?.removeAttribute(.strikethroughStyle, range: all)
            editor.typingAttributes[.strikethroughStyle] = nil
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let edits: [String: Selector] = [
            "x": #selector(NSText.cut(_:)),
            "c": #selector(NSText.copy(_:)),
            "v": #selector(NSText.paste(_:)),
            "a": #selector(NSText.selectAll(_:)),
            "z": Selector(("undo:")),
        ]
        let action = flags == .command ? edits[key] : flags == [.command, .shift] && key == "z" ? Selector(("redo:")) : nil
        if let action, NSApp.sendAction(action, to: nil, from: self) { return true }
        return super.performKeyEquivalent(with: event)
    }

    static func focus() {
        NSApp.windows.first { $0 is Panel }?.makeKey()
    }
}
