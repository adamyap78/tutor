import Foundation

// MARK: - Formats

enum Formats {
    /// Bit position in the legal / restricted / banned masks is the index in this array.
    static let keys = [
        "standard", "pioneer", "modern", "legacy", "vintage", "commander", "pauper", "brawl",
        "historic", "timeless", "explorer", "alchemy", "oathbreaker", "penny", "paupercommander",
        "duel", "oldschool", "premodern", "predh", "gladiator", "standardbrawl", "future",
    ]

    static let titles: [String: String] = [
        "standard": "Standard", "pioneer": "Pioneer", "modern": "Modern", "legacy": "Legacy",
        "vintage": "Vintage", "commander": "Commander", "pauper": "Pauper", "brawl": "Brawl",
        "historic": "Historic", "timeless": "Timeless", "explorer": "Explorer", "alchemy": "Alchemy",
        "oathbreaker": "Oathbreaker", "penny": "Penny", "paupercommander": "Pauper Commander",
        "duel": "Duel", "oldschool": "Old School", "premodern": "Premodern", "predh": "PreDH",
        "gladiator": "Gladiator", "standardbrawl": "Standard Brawl", "future": "Future",
    ]

    /// Formats shown in the detail view's legality grid, in order.
    static let detailFormats = ["standard", "pioneer", "modern", "legacy", "vintage", "commander"]

    static let headline = [
        "standard", "pioneer", "modern", "legacy", "vintage", "commander", "pauper", "brawl",
        "historic", "timeless", "explorer", "oathbreaker",
    ]

    static let aliases: [String: String] = [
        "edh": "commander", "cmdr": "commander", "std": "standard", "pdh": "paupercommander",
        "old": "oldschool", "os": "oldschool", "ps": "pauper",
    ]

    static func bit(_ name: String) -> Int? {
        let k = name.lowercased()
        if let i = keys.firstIndex(of: k) { return i }
        if let a = aliases[k], let i = keys.firstIndex(of: a) { return i }
        return nil
    }
}

enum LegalStatus {
    case legal, restricted, banned, notLegal

    var label: String {
        switch self {
        case .legal: return "Legal"
        case .restricted: return "Restricted"
        case .banned: return "Banned"
        case .notLegal: return "Not legal"
        }
    }
}

// MARK: - Colours, rarity, flags

enum Colors {
    static let bits: [Character: Int] = ["w": 1, "u": 2, "b": 4, "r": 8, "g": 16]

    static let names: [String: Int] = [
        "white": 1, "blue": 2, "black": 4, "red": 8, "green": 16,
        "azorius": 3, "dimir": 6, "rakdos": 12, "gruul": 24, "selesnya": 17,
        "orzhov": 5, "izzet": 10, "golgari": 20, "boros": 9, "simic": 18,
        "bant": 19, "esper": 7, "grixis": 14, "jund": 28, "naya": 25,
        "abzan": 21, "jeskai": 11, "sultai": 22, "mardu": 13, "temur": 26,
        "chaos": 30, "aggression": 29, "altruism": 27, "growth": 23, "artifice": 15,
        "wubrg": 31, "rainbow": 31,
    ]

    /// Parses "rg", "red", "izzet" ... into a WUBRG bitmask.
    static func mask(_ s: String) -> Int? {
        let v = s.lowercased()
        if let m = names[v] { return m }
        var m = 0
        for ch in v {
            guard let b = bits[ch] else { return nil }
            m |= b
        }
        return v.isEmpty ? nil : m
    }
}

enum Rarity {
    static let names = ["common", "uncommon", "rare", "mythic", "special", "bonus"]
    static func index(_ s: String) -> Int? {
        let v = s.lowercased()
        if let i = names.firstIndex(of: v) { return i }
        switch v {
        case "c": return 0
        case "u": return 1
        case "r": return 2
        case "m": return 3
        case "s": return 4
        case "b": return 5
        default: return nil
        }
    }
}

/// Boolean card properties computed at import time and queried with `is:`.
enum CardFlag: Int, CaseIterable {
    case dfc, mdfc, transform, split, flip, adventure, saga, meld, leveler, classCard, battle
    case reversible, reserved, commander, permanent, spell, vanilla, historic, reprint, funny
    case gamechanger, planeswalker, creature, legendary

    var searchName: String {
        switch self {
        case .classCard: return "class"
        default: return String(describing: self)
        }
    }

    static let byName: [String: CardFlag] = {
        var d = [String: CardFlag]()
        for f in CardFlag.allCases { d[f.searchName] = f }
        d["transforming"] = .transform
        d["modal"] = .mdfc
        d["doublefaced"] = .dfc
        d["cmdr"] = .commander
        return d
    }()
}

// MARK: - Card data

struct CardRow: Identifiable, Hashable {
    let id: Int64
    let oracleID: String
    let name: String
    let manaCost: String
    let typeLine: String
    let setCode: String
    let rarity: Int
    let scryID: String
    let hasImage: Bool
    let hasBack: Bool
}

struct Face: Codable, Hashable {
    var name: String
    var manaCost: String
    var typeLine: String
    var oracleText: String
    var power: String?
    var toughness: String?
    var loyalty: String?
    var defense: String?
    var flavor: String?

    enum CodingKeys: String, CodingKey {
        case name = "n", manaCost = "m", typeLine = "t", oracleText = "o"
        case power = "p", toughness = "u", loyalty = "l", defense = "d", flavor = "f"
    }

    var powerToughness: String? {
        if let p = power, let t = toughness { return "\(p)/\(t)" }
        return nil
    }
}

struct DetailBlob: Codable {
    var layout: String
    var faces: [Face]
    var keywords: [String]
}

struct Printing: Identifiable, Hashable {
    let id: Int64
    let scryID: String
    let setCode: String
    let setName: String
    let collector: String
    let rarity: Int
    let released: String
    let usd: Double?
    let usdFoil: Double?
    let usdEtched: Double?
    let hasImage: Bool
}

struct CardFull {
    let row: CardRow
    let oracleID: String
    let layout: String
    let faces: [Face]
    let keywords: [String]
    let legal: Int
    let restricted: Int
    let banned: Int
    let edhrec: Int?
    let printings: [Printing]
    let repIndex: Int

    func status(_ format: String) -> LegalStatus {
        guard let b = Formats.bit(format) else { return .notLegal }
        let m = 1 << b
        if banned & m != 0 { return .banned }
        if restricted & m != 0 { return .restricted }
        if legal & m != 0 { return .legal }
        return .notLegal
    }

    /// Faces to show when `face` is selected: DFCs show one face, split/adventure show all.
    func visibleFaces(face: Int) -> [Face] {
        if row.hasBack, faces.indices.contains(face) { return [faces[face]] }
        return faces
    }
}

// MARK: - Helpers

enum TextNorm {
    /// Lowercases and strips diacritics.
    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
    }

    /// Normalised form used for name matching: folded, punctuation removed, hyphens as spaces.
    static func normName(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.utf8.count)
        var lastSpace = true
        for ch in fold(s) {
            switch ch {
            case ",", "'", "’", "\"", "!", "?", ".", ":", ";", "*", "(", ")":
                continue
            case "-", "–", "—", "_":
                if !lastSpace { out.append(" "); lastSpace = true }
            case " ", "\t", "\n":
                if !lastSpace { out.append(" "); lastSpace = true }
            default:
                out.append(ch)
                lastSpace = false
            }
        }
        if out.hasSuffix(" ") { out.removeLast() }
        return out
    }
}

extension Double {
    var usdString: String { String(format: "$%.2f", self) }
}
