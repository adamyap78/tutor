import SwiftUI

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
