import SwiftUI

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
    @Environment(AppModel.self) private var model
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
                if let price = model.displayPrice(printing) {
                    Text(price.usd.usdString)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.regularMaterial, in: Capsule())
                        .help("\(price.finish) price in USD for \(printing.setName) (\(printing.setCode.uppercased()))\n"
                              + (price.live ? "Live from Scryfall (TCGplayer market price)"
                                            : "Scryfall bulk data (TCGplayer market price)\nSnapshot" + (model.priceAge.map { ", updated \($0)" } ?? "") + "; refreshing…"))
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
