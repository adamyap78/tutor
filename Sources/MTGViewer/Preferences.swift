import Foundation

// User preferences that decide which printings exist as far as the app is concerned
// (`ExclusionPreferences`) and which one represents a card in results (`ArtPreferences`).
// The database stores the facts about every printing; everything here is applied at runtime
// on top of it, so changing a setting never needs a re-import.

enum Cutoff: String, Codable, CaseIterable, Identifiable {
    case none, revised, fourth, mirage, sixth, eighth, m15

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No limit"
        case .revised: return "Revised Edition (1994)"
        case .fourth: return "Fourth Edition (1995)"
        case .mirage: return "Mirage (1996)"
        case .sixth: return "Sixth Edition (1999)"
        case .eighth: return "Eighth Edition — modern frame (2003)"
        case .m15: return "Magic 2015 — current frame (2014)"
        }
    }

    /// Early sets that are avoided outright. Legends, The Dark and Fallen Empires postdate Revised
    /// but share the pre-Revised look, so they count as "older" here.
    private static let beforeRevised: Set<String> = [
        "lea", "leb", "2ed", "arn", "atq", "leg", "drk", "fem", "30a", "cei", "ced", "cedi",
    ]

    var avoidSets: Set<String> {
        switch self {
        case .none: return []
        case .revised: return Self.beforeRevised
        default: return Self.beforeRevised.union(["3ed"])
        }
    }

    /// Anything released before this date (ISO, "" for none) is avoided too.
    var minDate: String {
        switch self {
        case .none, .revised, .fourth: return ""
        case .mirage: return "1996-10-08"
        case .sixth: return "1999-04-21"
        case .eighth: return "2003-07-28"
        case .m15: return "2014-07-18"
        }
    }

    func avoids(setCode: String, released: String) -> Bool {
        if self == .none { return false }
        return avoidSets.contains(setCode) || (!minDate.isEmpty && released < minDate)
    }
}

struct ArtPreferences: Codable, Equatable {
    var newestFirst = true
    var cutoff: Cutoff = .none
    var preferEnglish = true
    var preferPaper = true
    var preferNonPromo = true
    var preferStandardFrame = true
}

struct ExclusionPreferences: Codable, Equatable {
    var mtgoOnly = false
    var arenaOnly = false
    var promos = false
    var oversized = false
    var nonEnglish = false
    var setTypes: Set<String> = []
    var sets: Set<String> = []

    var isEmpty: Bool { self == ExclusionPreferences() }

    /// Digital-only printings, joke sets and memorabilia stay out of the way.
    static let recommended = ExclusionPreferences(
        mtgoOnly: true, arenaOnly: true, setTypes: ["funny", "memorabilia"])
}

struct Preferences: Codable, Equatable {
    var art = ArtPreferences()
    var exclude = ExclusionPreferences.recommended

    static let standard = Preferences()
    var isStandard: Bool { self == .standard }

    private static let key = "preferences"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let p = try? JSONDecoder().decode(Preferences.self, from: data) else { return .standard }
        return p
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }
}

// MARK: - Choosing the representative printing

enum PrintingAttr {
    static let english = 1, digital = 2, promo = 4, oversized = 8, plain = 16
    static let paper = 32, mtgo = 64, arena = 128
}

struct PrintingMeta {
    var setCode: String
    var setType: String
    var released: String
    var attrs: Int
    var hasImage: Bool
}

enum Representative {
    static func excluded(_ m: PrintingMeta, _ ex: ExclusionPreferences) -> Bool {
        if ex.isEmpty { return false }
        if ex.sets.contains(m.setCode) || ex.setTypes.contains(m.setType) { return true }
        let a = m.attrs
        if a & PrintingAttr.paper == 0 {
            if ex.mtgoOnly && a & PrintingAttr.mtgo != 0 { return true }
            if ex.arenaOnly && a & PrintingAttr.arena != 0 { return true }
        }
        if ex.promos && a & PrintingAttr.promo != 0 { return true }
        if ex.oversized && a & PrintingAttr.oversized != 0 { return true }
        if ex.nonEnglish && a & PrintingAttr.english == 0 { return true }
        return false
    }

    /// Larger sorts as the better preview. Preferences are ranked strictly in this order, then date.
    static func key(_ m: PrintingMeta, _ art: ArtPreferences) -> (Int, String) {
        let a = m.attrs
        var bits = 0
        if m.hasImage { bits |= 1 << 8 }
        if !art.cutoff.avoids(setCode: m.setCode, released: m.released) { bits |= 1 << 7 }
        if !art.preferEnglish || a & PrintingAttr.english != 0 { bits |= 1 << 6 }
        if m.setType != "memorabilia" { bits |= 1 << 5 }
        if !art.preferPaper || a & PrintingAttr.digital == 0 { bits |= 1 << 4 }
        if !art.preferNonPromo || a & PrintingAttr.promo == 0 { bits |= 1 << 3 }
        if a & PrintingAttr.oversized == 0 { bits |= 1 << 2 }
        if !art.preferStandardFrame || a & PrintingAttr.plain != 0 { bits |= 1 << 1 }
        // Oldest wins by inverting the digits so that an earlier date compares greater.
        let date = art.newestFirst ? m.released : String(m.released.map { c -> Character in
            c.wholeNumberValue.map { Character(String(9 - $0)) } ?? c
        })
        return (bits, date)
    }
}

// MARK: - Runtime overlay on the database

struct RepInfo {
    let printingID: Int64
    let scryID: String
    let setCode: String
    let rarity: Int
    let hasImage: Bool
}

/// The result of applying `Preferences` to the whole database: every visible card's chosen
/// printing, and the cards that have no allowed printing left.
final class Overlay {
    let reps: [Int64: RepInfo]
    let hidden: Set<Int64>
    let exclude: ExclusionPreferences

    init(reps: [Int64: RepInfo], hidden: Set<Int64>, exclude: ExclusionPreferences) {
        self.reps = reps
        self.hidden = hidden
        self.exclude = exclude
    }
}

struct SetInfo: Identifiable, Hashable {
    let code: String
    let name: String
    let type: String
    let released: String
    let count: Int
    var id: String { code }
}

enum SetKinds {
    /// Scryfall `set_type` values worth toggling, with a friendly name and examples.
    static let all: [(type: String, title: String, detail: String)] = [
        ("funny", "Joke sets", "Unglued, Unhinged, Unstable, Unfinity"),
        ("memorabilia", "Memorabilia", "Gold-bordered, World Championship & oversized oddities"),
        ("promo", "Promo sets", "Prerelease, Friday Night Magic, judge and store promos"),
        ("alchemy", "Alchemy", "Arena-rebalanced and digital-only designs"),
        ("treasure_chest", "Treasure Chest", "Magic Online prize cards"),
        ("masterpiece", "Masterpiece Series", "Kaladesh Inventions, Zendikar Expeditions…"),
        ("masters", "Masters sets", "Modern Masters, Ultimate Masters, Double Masters…"),
        ("eternal", "Eternal-only sets", "Products legal only in eternal formats"),
        ("commander", "Commander products", "Precon decks and Commander sets"),
        ("arsenal", "Commander Arsenal", "Oversized Commander promos"),
        ("planechase", "Planechase", "Planes and phenomena"),
        ("archenemy", "Archenemy", "Schemes"),
        ("vanguard", "Vanguard", "Avatar cards"),
        ("duel_deck", "Duel Decks", "Jace vs. Chandra and friends"),
        ("from_the_vault", "From the Vault", "Premium foil showcases"),
        ("premium_deck", "Premium Deck Series", "Fire & Lightning, Slivers…"),
        ("spellbook", "Spellbooks", "Jumpstart-style digital spellbooks"),
        ("starter", "Starter & intro sets", "Portal, Starter 1999, Welcome Decks"),
        ("box", "Box sets", "Battle Royale, Beatdown, Deckmasters"),
        ("draft_innovation", "Draft innovation", "Conspiracy, Mystery Booster, Jumpstart"),
        ("minigame", "Minigames", "Mystery cards and Mystical Archive extras"),
    ]
}
