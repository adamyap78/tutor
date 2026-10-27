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
            case .ready: MainView()
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
        }
        return v
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 0) {
            // Kept alive (zero height) while inspecting so the field still receives the keyboard.
            SearchBar()
                .frame(height: model.mode == .detail ? 0 : nil)
                .clipped()
                .opacity(model.mode == .detail ? 0 : 1)
                .allowsHitTesting(model.mode != .detail)
            if model.mode == .detail {
                Color.clear.frame(height: 30)
            } else {
                Divider()
            }
            if model.mode == .detail {
                DetailView()
            } else {
                HStack(spacing: 0) {
                    Group {
                        if model.count == 0 { EmptyResults() }
                        else if model.layout == .list { ResultList() }
                        else { ResultGrid() }
                    }
                    .frame(minWidth: 320, maxWidth: .infinity)
                    Divider()
                    PreviewPane()
                        .frame(width: PreviewPane.width)
                }
            }
            Divider()
            FooterBar()
        }
    }
}

// MARK: - Search

struct SearchBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.tertiary)
            SearchField(model: model)
                .frame(height: 34)
            if !model.query.isEmpty {
                Button {
                    model.escape()
                    model.focusSearch()
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear (Esc)")
            }
            Button {
                model.toggleLayout()
                model.focusSearch()
            } label: {
                Image(systemName: model.layout == .list ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .help(model.layout == .list ? "Show image grid (⌘G)" : "Show compact list (⌘G)")
        }
        .padding(.horizontal, 22)
        .padding(.top, 34)
        .padding(.bottom, 14)
    }
}

final class KeyField: NSTextField {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 34) }

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
        f.font = .systemFont(ofSize: 24, weight: .light)
        f.placeholderAttributedString = NSAttributedString(
            string: "Search cards — name, or  t:creature  c:r  mv<=3  f:modern  o:draw",
            attributes: [.font: NSFont.systemFont(ofSize: 22, weight: .light), .foregroundColor: NSColor.tertiaryLabelColor])
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
                if model.handlesHorizontal { model.arrow(.left); return true }
                return false
            case #selector(NSResponder.moveRight(_:)):
                if model.handlesHorizontal { model.arrow(.right); return true }
                return false
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

struct ResultRow: View {
    let row: CardRow
    let selected: Bool

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Style.rarity(row.rarity))
                .frame(width: 3, height: 26)
                .opacity(selected ? 1 : 0.55)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text(row.typeLine)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            ManaCostView(cost: row.manaCost, size: 13)
            Text(row.setCode.uppercased())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 32, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .frame(height: 46)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Color.accentColor.opacity(0.20) : .clear))
        .contentShape(Rectangle())
    }
}

struct ResultList: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollViewReader { proxy in
            List {
                ForEach(0..<model.count, id: \.self) { i in
                    if let row = model.row(at: i) {
                        ResultRow(row: row, selected: i == model.selection)
                            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .id(i)
                            .onTapGesture(count: 2) { model.select(i); model.enter(); model.focusSearch() }
                            .onTapGesture { model.select(i); model.focusSearch() }
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 46)
            .onChange(of: model.selection) { _, new in proxy.scrollTo(new) }
            .onChange(of: model.resultsVersion) { _, _ in proxy.scrollTo(model.selection, anchor: .top) }
        }
    }
}

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
                ScrollView {
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
                .onChange(of: model.selection) { _, new in proxy.scrollTo(new) }
                .onChange(of: model.resultsVersion) { _, _ in proxy.scrollTo(model.selection, anchor: .top) }
            }
            .onAppear { model.gridColumns = cols }
            .onChange(of: cols) { _, c in model.gridColumns = c }
        }
    }
}

struct GridCell: View {
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
                    Text(usd.usdString)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
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
        HStack(spacing: 5) {
            Circle().fill(Style.legality(status)).frame(width: 6, height: 6)
            Text("\(Formats.titles[format] ?? format) · \(status.label)")
                .font(.system(size: 11, weight: .medium))
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(Style.legality(status).opacity(0.14), in: Capsule())
    }
}

// MARK: - Detail

struct DetailView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let f = model.full, let p = model.printing {
            HStack(alignment: .top, spacing: 40) {
                ZStack(alignment: .bottom) {
                    CardImageView(scryID: p.scryID, hasImage: p.hasImage, face: model.face, size: .large,
                                  title: f.visibleFaces(face: model.face).first?.name ?? f.row.name,
                                  subtitle: f.visibleFaces(face: model.face).first?.typeLine ?? "",
                                  text: f.visibleFaces(face: model.face).first?.oracleText ?? "")
                    if f.row.hasBack {
                        Text("⇥  flip card")
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(.regularMaterial, in: Capsule())
                            .foregroundStyle(.secondary)
                            .offset(y: 4)
                    }
                }
                .frame(minWidth: 320, maxWidth: 520)
                .padding(.vertical, 24)

                DetailInfo(full: f, printing: p)
                    .frame(maxWidth: 560, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.vertical, 24)
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

            section("Legality") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 6, alignment: .leading)], alignment: .leading, spacing: 6) {
                    ForEach(Formats.detailFormats, id: \.self) { fmt in
                        LegalityChip(format: fmt, status: full.status(fmt))
                    }
                }
            }

            section("Price") {
                PriceBlock(printing: printing, age: model.priceAge)
            }

            section("Edition") {
                HStack(spacing: 8) {
                    Circle().fill(Style.rarity(printing.rarity)).frame(width: 8, height: 8)
                    Text(printing.setName).font(.system(size: 13)).lineLimit(1)
                    Text("\(printing.setCode.uppercased()) #\(printing.collector)")
                        .font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
                    Spacer(minLength: 4)
                    Text("\(model.selectedPrintingIndex + 1) of \(full.printings.count)")
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                }
            }

            HStack {
                Button { model.openScryfall() } label: { Label("View on Scryfall", systemImage: "arrow.up.right.square") }
                    .buttonStyle(.link)
                Spacer()
                if let e = full.edhrec { Text("EDHREC rank \(e.formatted())").font(.caption).foregroundStyle(.tertiary) }
            }
        }
    }

    @ViewBuilder
    private func section<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased()).font(.system(size: 10.5, weight: .semibold)).tracking(0.8).foregroundStyle(.tertiary)
            content()
        }
    }
}

struct PriceBlock: View {
    let printing: Printing
    let age: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if printing.usd == nil && printing.usdFoil == nil && printing.usdEtched == nil {
                Text("No price available for this printing").foregroundStyle(.secondary)
            } else {
                HStack(spacing: 22) {
                    if let u = printing.usd { price("Regular", u) }
                    if let u = printing.usdFoil { price("Foil", u) }
                    if let u = printing.usdEtched { price("Etched", u) }
                }
            }
            if let age { Text("Scryfall market data · updated \(age)").font(.caption).foregroundStyle(.tertiary) }
        }
    }

    private func price(_ label: String, _ v: Double) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(v.usdString).font(.system(size: 20, weight: .semibold, design: .rounded))
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Footer

struct Hint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .padding(.horizontal, 4).padding(.vertical, 1)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 11))
        }
        .foregroundStyle(.tertiary)
    }
}

struct FooterBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 14) {
            if let t = model.toast {
                Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            } else {
                Text("\(model.count.formatted()) \(model.count == 1 ? "card" : "cards")" +
                     (model.warnings.isEmpty ? "" : " · \(model.warnings[0])"))
                    .font(.system(size: 11)).foregroundStyle(.tertiary)
            }
            Spacer()
            if model.mode == .detail {
                Hint(key: "↑↓", label: "Printing")
                Hint(key: "←→", label: "Card")
                Hint(key: "⇥", label: "Flip")
                Hint(key: "⌘O", label: "Scryfall")
                Hint(key: "⎋", label: "Back")
            } else {
                Hint(key: "↑↓", label: "Navigate")
                Hint(key: "⏎", label: "Inspect")
                Hint(key: "⌘C", label: "Copy name")
                Hint(key: "⌘G", label: model.layout == .list ? "Grid" : "List")
                Hint(key: "⌘I", label: model.showText ? "Hide text" : "Card text")
                Hint(key: "⎋", label: "Clear")
            }
            if let s = model.updateStatus ?? model.warmStatus {
                Text(s).font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                Hint(key: "⌘R", label: "Refresh data")
            }
        }
        .padding(.horizontal, 20)
        .frame(height: 30)
    }
}

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
