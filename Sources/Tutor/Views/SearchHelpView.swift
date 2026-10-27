import SwiftUI

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
