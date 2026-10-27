import SwiftUI

struct SearchBar: View {
    @Environment(AppModel.self) private var model
    @StateObject private var help = HelpState()
    static let height: CGFloat = 44
    static let bottomInset: CGFloat = 16
    static let clearance: CGFloat = bottomInset + height + 14

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.secondary)
            SearchField(model: model)
                .frame(height: 28)
            if !model.query.isEmpty {
                Button {
                    model.escape()
                    model.focusSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 20)).foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Clear (Esc)")
            }
            Button {
                help.shown = true
            } label: {
                Image(systemName: "questionmark.circle").font(.system(size: 20)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Search syntax")
        }
        .sheet(isPresented: $help.shown, onDismiss: { model.focusSearch() }) { SearchHelpView() }
        .padding(.horizontal, 18)
        .frame(height: Self.height)
        .modifier(GlassBar())
        .shadow(color: .black.opacity(0.18), radius: 14, y: 5)
        .padding(.horizontal, 34)
        .padding(.bottom, Self.bottomInset)
    }
}

struct GlassBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 0.5))
        }
    }
}

final class CenteredCell: NSTextFieldCell {
    private func centered(_ r: NSRect) -> NSRect {
        let h = cellSize(forBounds: r).height
        var o = r
        o.origin.y += (r.height - h) / 2
        o.size.height = h
        return o
    }
    override func drawingRect(forBounds r: NSRect) -> NSRect { centered(super.drawingRect(forBounds: r)) }
    override func select(withFrame r: NSRect, in v: NSView, editor: NSText, delegate d: Any?, start: Int, length: Int) {
        super.select(withFrame: centered(r), in: v, editor: editor, delegate: d, start: start, length: length)
    }
    override func edit(withFrame r: NSRect, in v: NSView, editor: NSText, delegate d: Any?, event: NSEvent?) {
        super.edit(withFrame: centered(r), in: v, editor: editor, delegate: d, event: event)
    }
}

final class KeyField: NSTextField {
    override class var cellClass: AnyClass? { get { CenteredCell.self } set {} }
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 28) }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let w = self.window else { return }
            w.makeFirstResponder(self)
        }
    }
}

struct SearchField: NSViewRepresentable {
    let model: AppModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeNSView(context: Context) -> KeyField {
        let f = KeyField()
        f.delegate = context.coordinator
        f.isBordered = false
        f.drawsBackground = false
        f.focusRingType = .none
        f.font = .systemFont(ofSize: 17, weight: .regular)
        f.placeholderAttributedString = NSAttributedString(
            string: "Search cards",
            attributes: [.font: NSFont.systemFont(ofSize: 17, weight: .regular), .foregroundColor: NSColor.tertiaryLabelColor])
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.lineBreakMode = .byClipping
        f.stringValue = model.query
        model.searchField = f
        return f
    }

    func updateNSView(_ f: KeyField, context: Context) {
        if f.stringValue != model.query, f.currentEditor() == nil || !(f.currentEditor() as? NSTextView)!.hasMarkedText() {
            f.stringValue = model.query
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        let model: AppModel
        init(model: AppModel) { self.model = model }

        func controlTextDidChange(_ n: Notification) {
            guard let f = n.object as? NSTextField else { return }
            model.setQuery(f.stringValue)
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy sel: Selector) -> Bool {
            switch sel {
            case #selector(NSResponder.moveUp(_:)): model.arrow(.up); return true
            case #selector(NSResponder.moveDown(_:)): model.arrow(.down); return true
            // Plain left/right always navigate; Option/Cmd/Ctrl/Shift variants use other selectors and still edit text.
            case #selector(NSResponder.moveLeft(_:)):
                model.arrow(.left); return true
            case #selector(NSResponder.moveRight(_:)):
                model.arrow(.right); return true
            case #selector(NSResponder.insertNewline(_:)): model.enter(); return true
            case #selector(NSResponder.cancelOperation(_:)): model.escape(); return true
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)): model.flip(); return true
            case #selector(NSResponder.pageDown(_:)): model.page(1); return true
            case #selector(NSResponder.pageUp(_:)): model.page(-1); return true
            case #selector(NSResponder.moveToBeginningOfDocument(_:)): model.first(); return true
            case #selector(NSResponder.moveToEndOfDocument(_:)): model.last(); return true
            default: return false
            }
        }
    }
}
