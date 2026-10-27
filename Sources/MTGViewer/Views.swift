import SwiftUI

// MARK: - Style helpers

enum Style {
    static func rarity(_ r: Int) -> Color {
        switch r {
        case 0: return Color(white: 0.55)
        case 1: return Color(red: 0.62, green: 0.74, blue: 0.84)
        case 2: return Color(red: 0.88, green: 0.72, blue: 0.28)
        case 3: return Color(red: 0.93, green: 0.42, blue: 0.20)
        case 4: return Color(red: 0.62, green: 0.40, blue: 0.85)
        default: return Color(red: 0.90, green: 0.40, blue: 0.62)
        }
    }

    static func legality(_ s: LegalStatus) -> Color {
        switch s {
        case .legal: return Color(red: 0.25, green: 0.70, blue: 0.42)
        case .restricted: return Color(red: 0.90, green: 0.68, blue: 0.18)
        case .banned: return Color(red: 0.88, green: 0.30, blue: 0.30)
        case .notLegal: return Color.secondary
        }
    }

    static let cardAspect: CGFloat = 0.7168
}

// MARK: - Root

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
            switch model.dataState {
            case .ready: MainView().ignoresSafeArea(.container, edges: .top)
            case .needsData: OnboardingView()
            case .loading: EmptyView()
            }
        }
        .background(WindowConfigurator())
    }
}

struct WindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let v = NSView()
        DispatchQueue.main.async {
            v.window?.isMovableByWindowBackground = true
            v.window?.titlebarAppearsTransparent = true
            for b in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                v.window?.standardWindowButton(b)?.isHidden = true
            }
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if model.mode == .detail {
                    DetailView()
                } else {
                    HStack(spacing: 0) {
                        Group {
                            if model.count == 0 { EmptyResults() }
                            else { ResultGrid() }
                        }
                        .frame(minWidth: 320, maxWidth: .infinity)
                        PreviewPane()
                            .frame(width: PreviewPane.width)
                    }
                }
                // Floats over the results column only; kept alive (hidden) while inspecting so the field still receives the keyboard.
                SearchBar()
                    .padding(.trailing, model.mode == .detail ? 0 : PreviewPane.width + 1)
                    .frame(height: model.mode == .detail ? 0 : nil)
                    .clipped()
                    .opacity(model.mode == .detail ? 0 : 1)
                    .allowsHitTesting(model.mode != .detail)
            }
        }
    }
}

// MARK: - Search

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

final class HelpState: ObservableObject { @Published var shown = false }

struct SearchHelpView: View {
    @Environment(\.dismiss) private var dismiss
    private let sections: [(String, [(String, String)])] = [
        ("Text", [("lightning bolt", "Name contains words"), ("o:draw", "Oracle text (o:\"draw a card\")"),
                  ("t:creature", "Type line (t:legendary t:elf)"), ("kw:flying", "Keyword ability")]),
        ("Colors & mana", [("c:rg", "Card colors"), ("id<=wu", "Color identity (id:bg)"), ("m:rr", "Mana cost contains"),
                           ("produces:g", "Produces mana")]),
        ("Numbers", [("mv<=3", "Mana value (also cmc)"), ("pow>=5", "Power (tou, loy likewise)"), ("usd<1", "Price in USD"),
                     ("year>=2020", "Release year")]),
        ("Sets & rarity", [("s:mh3", "Set code"), ("r:mythic", "Rarity (r>=rare)"), ("cn:123", "Collector number")]),
        ("Formats & flags", [("f:modern", "Legal in format"), ("banned:legacy", "Banned in format"), ("is:… / not:…", "Card flags"),
                             ("layout:split", "Card layout")]),
        ("Combining", [("a b", "Both terms (AND)"), ("a or b", "Either term"), ("-t:creature", "Negate a term"),
                       ("(c:r or c:g) t:creature", "Group with parentheses")]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Search syntax").font(.title2.weight(.semibold))
                Spacer()
                Text("Operators  :  =  !=  <  <=  >  >=").font(.caption).foregroundStyle(.tertiary)
            }
            HStack(alignment: .top, spacing: 36) {
                column(Array(sections[0..<3]))
                column(Array(sections[3..<6]))
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction).controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 820)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func column(_ secs: [(String, [(String, String)])]) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(secs, id: \.0) { sec in
                VStack(alignment: .leading, spacing: 8) {
                    Text(sec.0).font(.subheadline.weight(.semibold))
                    ForEach(sec.1, id: \.0) { item in
                        HStack(spacing: 10) {
                            Text(item.0)
                                .font(.system(size: 12.5, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                                .frame(width: 150, alignment: .leading)
                            Text(item.1).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
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

// MARK: - Results

struct ResultGrid: View {
    @Environment(AppModel.self) private var model
    private let spacing: CGFloat = 14
    private let pad: CGFloat = 18
    private let minItem: CGFloat = 132

    var body: some View {
        GeometryReader { geo in
            let avail = geo.size.width - pad * 2
            let cols = max(1, Int((avail + spacing) / (minItem + spacing)))
            let w = (avail - spacing * CGFloat(cols - 1)) / CGFloat(cols)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(w), spacing: spacing), count: cols), spacing: spacing) {
                        ForEach(0..<model.count, id: \.self) { i in
                            if let row = model.row(at: i) {
                                GridCell(row: row, selected: i == model.selection, width: w)
                                    .id(i)
                                    .onTapGesture(count: 2) { model.select(i); model.enter(); model.focusSearch() }
                                    .onTapGesture { model.select(i); model.focusSearch() }
                            }
                        }
                    }
                    .padding(pad)
                }
                .contentMargins(.top, 0, for: .scrollContent)
                .contentMargins(.bottom, SearchBar.clearance - pad, for: .scrollContent)
                .onChange(of: model.selection) { _, new in proxy.scrollTo(new) }
                .onChange(of: model.resultsVersion) { _, _ in proxy.scrollTo(model.selection, anchor: .top) }
            }
            .onAppear { model.gridColumns = cols }
            .onChange(of: cols) { _, c in model.gridColumns = c }
        }
    }
}

struct FavoriteStar: View {
    let on: Bool
    var size: CGFloat = 12

    var body: some View {
        Image(systemName: on ? "star.fill" : "star")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(on ? Color.white : Color.primary.opacity(0.55))
            .shadow(color: .black.opacity(on ? 0.5 : 0), radius: 1.5, y: 0.5)
    }
}

struct FavoriteButton: View {
    @Environment(AppModel.self) private var model
    let row: CardRow

    var body: some View {
        let on = model.isFavorite(row)
        Button {
            model.toggleFavorite()
            model.focusSearch()
        } label: {
            FavoriteStar(on: on, size: 11)
                .frame(width: 24, height: 24)
                .background(on ? AnyShapeStyle(Color.black.opacity(0.35)) : AnyShapeStyle(.regularMaterial), in: Circle())
                .overlay(Circle().strokeBorder(.white.opacity(on ? 0.25 : 0.12), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .help("Favourite (,)")
        .padding(8)
    }
}

struct GridCell: View {
    @Environment(AppModel.self) private var model
    let row: CardRow
    let selected: Bool
    let width: CGFloat

    var body: some View {
        CardImageView(scryID: row.scryID, hasImage: row.hasImage, face: 0, size: .small,
                      title: row.name, subtitle: row.typeLine, text: "", shadow: false)
            .frame(width: width, height: width / Style.cardAspect)
            .overlay(
                RoundedRectangle(cornerRadius: width * 0.055)
                    .strokeBorder(Color.accentColor, lineWidth: selected ? 3 : 0)
                    .padding(-2)
            )
            .overlay(alignment: .topTrailing) {
                if model.isFavorite(row) { FavoriteStar(on: true, size: max(11, width * 0.09)).padding(width * 0.06) }
            }
            .scaleEffect(selected ? 1.02 : 1)
    }
}

struct EmptyResults: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 8) {
            Text("No cards found").font(.title3).foregroundStyle(.secondary)
            ForEach(model.warnings, id: \.self) { w in
                Text(w).font(.callout).foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Card image

@MainActor
final class ImageBox: ObservableObject {
    var key: String?
    var image: NSImage?
    func set(_ k: String, _ i: NSImage) {
        key = k
        image = i
        objectWillChange.send()
    }
    func refresh() { objectWillChange.send() }
}

struct CardImageView: View {
    let scryID: String
    let hasImage: Bool
    let face: Int
    let size: ImageSize
    let title: String
    let subtitle: String
    let text: String
    var shadow = true
    var textOverlay: CardFull? = nil

    @StateObject private var box = ImageBox()

    private var key: String { ImageStore.key(scryID, face, size) }

    private func current() -> NSImage? {
        if box.key == key, let img = box.image { return img }
        let store = ImageStore.shared
        if let m = store.memoryImage(key) { return m }
        // Show a smaller cached version while the sharp one loads.
        if size == .large {
            return store.memoryImage(ImageStore.key(scryID, face, .normal)) ?? store.memoryImage(ImageStore.key(scryID, face, .small))
        }
        return nil
    }

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * Style.cardAspect)
            let h = w / Style.cardAspect
            ZStack {
                if let img = current() {
                    Image(nsImage: img).resizable().interpolation(.high)
                } else {
                    CardPlaceholder(title: title, subtitle: subtitle, text: text, width: w)
                }
                if let full = textOverlay {
                    CardTextOverlay(full: full, face: face, width: w)
                }
            }
            .frame(width: w, height: h)
            .clipShape(RoundedRectangle(cornerRadius: w * 0.048, style: .continuous))
            .shadow(color: .black.opacity(shadow ? 0.28 : 0.12), radius: shadow ? 14 : 3, y: shadow ? 6 : 1)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .task(id: key) {
            guard hasImage else { return }
            let store = ImageStore.shared
            if let hit = store.memoryImage(key) {
                // Landed in the cache (e.g. prefetch) after this view first rendered.
                box.set(key, hit)
                return
            }
            if size == .large {
                // Paint something sharp-ish immediately while the large image loads.
                Task {
                    let hit = await store.load(scryID: scryID, face: face, size: .normal, network: false)
                    if hit == nil { _ = await store.load(scryID: scryID, face: face, size: .small) }
                    box.refresh()
                }
            }
            let delays: [Double] = [0.4, 1.5, 4, 10]
            for attempt in 0...delays.count {
                if let img = await store.load(scryID: scryID, face: face, size: size, debounceMs: size == .small ? 50 : 0) {
                    box.set(key, img)
                    return
                }
                if Task.isCancelled || attempt == delays.count { return }
                try? await Task.sleep(nanoseconds: UInt64(delays[attempt] * 1_000_000_000))
            }
        }
    }
}

/// Shown instantly from local data while (or if) the artwork is unavailable.
struct CardPlaceholder: View {
    let title: String
    let subtitle: String
    let text: String
    let width: CGFloat

    var body: some View {
        let s = width / 300
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: width * 0.048, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
            RoundedRectangle(cornerRadius: width * 0.048, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.14), lineWidth: 1)
            VStack(alignment: .leading, spacing: 6 * s) {
                Text(title).font(.system(size: max(9, 17 * s), weight: .semibold)).lineLimit(3)
                if width > 150 {
                    Text(subtitle).font(.system(size: 12 * s)).foregroundStyle(.secondary).lineLimit(2)
                    if !text.isEmpty {
                        Text(text).font(.system(size: 11.5 * s)).foregroundStyle(.secondary).lineLimit(9)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(width * 0.07)
        }
    }
}

// MARK: - Preview pane

struct PreviewPane: View {
    @Environment(AppModel.self) private var model
    /// Just wider than the card at its largest, so the picker gets the rest.
    static let width: CGFloat = 400

    var body: some View {
        Group {
            if let f = model.full, let p = model.printing {
                let face = f.visibleFaces(face: model.face).first
                CardImageView(scryID: p.scryID, hasImage: p.hasImage, face: model.face, size: .large,
                              title: face?.name ?? f.row.name, subtitle: face?.typeLine ?? "",
                              text: face?.oracleText ?? "",
                              textOverlay: model.showText ? f : nil)
                    .overlay(alignment: .bottom) { CardBadges(full: f, printing: p) }
                    .overlay(alignment: .topLeading) { FavoriteButton(row: f.row) }
                    .overlay(alignment: .topTrailing) {
                        if f.row.hasBack {
                            Text("⇥ flip")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
            } else {
                Color.clear
            }
        }
        .frame(maxHeight: .infinity)
    }
}

/// Edition badge and price of the printing being shown, overlaid on the card.
struct CardBadges: View {
    let full: CardFull
    let printing: Printing

    var body: some View {
        GeometryReader { geo in
            let w = min(geo.size.width, geo.size.height * Style.cardAspect)
            let h = w / Style.cardAspect
            HStack(spacing: 6) {
                HStack(spacing: 5) {
                    Circle().fill(Style.rarity(printing.rarity)).frame(width: 7, height: 7)
                    Text(printing.setCode.uppercased())
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(.regularMaterial, in: Capsule())
                .help(printing.setName)
                Spacer(minLength: 4)
                if let usd = printing.usd ?? printing.usdFoil ?? printing.usdEtched {
                    let finish = printing.usd != nil ? "Nonfoil" : printing.usdFoil != nil ? "Foil" : "Etched"
                    Text(usd.usdString)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .help("\(finish) price in USD for \(printing.setName) (\(printing.setCode.uppercased()))\nSource: Scryfall bulk data, sourced from TCGplayer market prices\nSnapshot from the last import; may be out of date")
                }
            }
            .foregroundStyle(.primary)
            .frame(width: w - 16)
            .position(x: geo.size.width / 2, y: (geo.size.height + h) / 2 - 18)
        }
    }
}

/// Rules text drawn over the card art when text mode is on.
struct CardTextOverlay: View {
    let full: CardFull
    let face: Int
    let width: CGFloat

    var body: some View {
        let s = width / 300
        let faces = full.visibleFaces(face: face)
        ZStack(alignment: .topLeading) {
            Color.black.opacity(0.9)
            VStack(alignment: .leading, spacing: 8 * s) {
                ForEach(Array(faces.enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 4 * s) {
                        HStack(alignment: .firstTextBaseline, spacing: 6 * s) {
                            Text(f.name).font(.system(size: 17 * s, weight: .semibold)).lineLimit(2)
                            Spacer(minLength: 4)
                            ManaCostView(cost: f.manaCost, size: 15 * s)
                        }
                        Text(f.typeLine).font(.system(size: 12 * s)).foregroundStyle(.white.opacity(0.65))
                        if !f.oracleText.isEmpty { OracleText(text: f.oracleText, size: 13 * s).padding(.top, 3 * s) }
                        if let pt = f.powerToughness {
                            Text(pt).font(.system(size: 14 * s, weight: .semibold, design: .rounded))
                        } else if let l = f.loyalty {
                            Text("Loyalty \(l)").font(.system(size: 13 * s, weight: .semibold))
                        } else if let d = f.defense {
                            Text("Defense \(d)").font(.system(size: 13 * s, weight: .semibold))
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(width * 0.07)
            .padding(.bottom, 26 * s)
            .environment(\.colorScheme, .dark)
            .foregroundStyle(.white)
        }
    }
}

struct LegalityChip: View {
    let format: String
    let status: LegalStatus

    var body: some View {
        Text(Formats.titles[format] ?? format)
            .font(.system(size: 11, weight: .medium))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 3)
            .background(Style.legality(status).opacity(status == .notLegal ? 0.12 : 0.28), in: Capsule())
            .foregroundStyle(status == .notLegal ? .secondary : .primary)
            .help("\(Formats.titles[format] ?? format): \(status.label)")
    }
}

// MARK: - Detail

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let f = model.full, let p = model.printing {
            HStack(alignment: .top, spacing: 40) {
                CardImageView(scryID: p.scryID, hasImage: p.hasImage, face: model.face, size: .large,
                              title: f.visibleFaces(face: model.face).first?.name ?? f.row.name,
                              subtitle: f.visibleFaces(face: model.face).first?.typeLine ?? "",
                              text: f.visibleFaces(face: model.face).first?.oracleText ?? "")
                    .overlay(alignment: .bottom) { CardBadges(full: f, printing: p) }
                    .overlay(alignment: .topLeading) { FavoriteButton(row: f.row) }
                    .overlay(alignment: .topTrailing) {
                        if f.row.hasBack {
                            Text("⇥ flip")
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(.regularMaterial, in: Capsule())
                                .foregroundStyle(.secondary)
                                .padding(8)
                        }
                    }
                // Same size and vertical position as the card in the grid view's preview pane.
                .frame(width: PreviewPane.width - 40)
                .frame(maxHeight: .infinity)
                .padding(.vertical, 18)

                DetailInfo(full: f, printing: p)
                    .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.vertical, 18)
                    .padding(.trailing, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 36)
        } else {
            Color.clear
        }
    }
}

struct DetailInfo: View {
    @Environment(AppModel.self) private var model
    let full: CardFull
    let printing: Printing

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(full.visibleFaces(face: model.face).enumerated()), id: \.offset) { _, f in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(f.name).font(.system(size: 24, weight: .semibold))
                            Spacer(minLength: 8)
                            ManaCostView(cost: f.manaCost, size: 18)
                        }
                        Text(f.typeLine).font(.system(size: 14)).foregroundStyle(.secondary)
                        if !f.oracleText.isEmpty { OracleText(text: f.oracleText, size: 15).padding(.top, 4) }
                        if let pt = f.powerToughness {
                            Text(pt).font(.system(size: 16, weight: .semibold, design: .rounded)).padding(.top, 2)
                        }
                        if let l = f.loyalty { Text("Loyalty \(l)").font(.system(size: 14, weight: .semibold)) }
                        if let d = f.defense { Text("Defense \(d)").font(.system(size: 14, weight: .semibold)) }
                    }
                }
            }

            Spacer(minLength: 0)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 3), spacing: 6) {
                ForEach(Formats.detailFormats, id: \.self) { fmt in
                    LegalityChip(format: fmt, status: full.status(fmt))
                }
            }
            .padding(.bottom, 14)
        }
    }
}

// MARK: - Footer

// MARK: - First run

struct OnboardingView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "square.stack.3d.up.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.accentColor)
            Text("Setting up your card library").font(.system(size: 22, weight: .semibold))
            Text("A one-time download of every Magic card from Scryfall. After this, everything works offline.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 380)

            if let err = model.importError {
                VStack(spacing: 12) {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 13)).foregroundStyle(.orange)
                        .multilineTextAlignment(.center).frame(maxWidth: 420)
                    Button("Try Again") { model.refreshData(force: true, silent: false) }
                        .keyboardShortcut(.defaultAction)
                        .controlSize(.large)
                }
                .padding(.top, 8)
            } else {
                VStack(spacing: 8) {
                    ProgressView(value: model.progress?.fraction ?? 0).frame(width: 320)
                    Text(model.progress?.detail ?? "Preparing…")
                        .font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.top, 8)
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
