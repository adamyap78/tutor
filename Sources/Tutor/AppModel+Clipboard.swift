import AppKit

// Copy and Scryfall-link actions for the selected card.
extension AppModel {
    func copyOrName() {
        if let tv = NSApp.keyWindow?.firstResponder as? NSTextView, tv.selectedRange().length > 0 {
            tv.copy(nil)
        } else {
            copyName()
        }
    }

    func copyName() {
        guard let c = current else { return }
        put(c.name)
        flash("Copied “\(c.name)”")
    }

    func copyDetails() {
        guard let f = full, let p = printing else { return }
        var lines: [String] = []
        for face in f.faces {
            lines.append(face.manaCost.isEmpty ? face.name : "\(face.name)  \(face.manaCost)")
            lines.append(face.typeLine)
            if !face.oracleText.isEmpty { lines.append(face.oracleText) }
            if let pt = face.powerToughness { lines.append(pt) }
            if let l = face.loyalty { lines.append("Loyalty: \(l)") }
            if let d = face.defense { lines.append("Defense: \(d)") }
            lines.append("")
        }
        lines.append("\(p.setName) (\(p.setCode.uppercased())) #\(p.collector) · \(Rarity.names[p.rarity].capitalized)")
        lines.append("Modern: \(f.status("modern").label)")
        if let usd = p.usd { lines.append("USD \(usd.usdString)") }
        if let url = scryfallURL { lines.append(url.absoluteString) }
        put(lines.joined(separator: "\n"))
        flash("Copied card details")
    }

    var scryfallURL: URL? {
        guard let p = printing else { return nil }
        var c = URLComponents()
        c.scheme = "https"
        c.host = "scryfall.com"
        c.path = "/card/\(p.setCode)/\(p.collector)"
        return c.url
    }

    func openScryfall() {
        if let u = scryfallURL { NSWorkspace.shared.open(u) }
    }

    private func put(_ s: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}
