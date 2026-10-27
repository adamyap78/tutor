import SwiftUI

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

/// A small white dot: filled when favourited, a faint ring when not.
struct FavoriteDot: View {
    let on: Bool
    var size: CGFloat = 6

    var body: some View {
        Circle()
            .fill(on ? Color.white : Color.clear)
            .overlay(Circle().strokeBorder(Color.primary.opacity(on ? 0 : 0.5), lineWidth: 1))
            .frame(width: size, height: size)
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
            FavoriteDot(on: on, size: 8)
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
            .overlay(alignment: .bottomLeading) {
                if model.isFavorite(row) { FavoriteDot(on: true, size: max(5, width * 0.04)).opacity(0.8).padding(width * 0.06) }
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
