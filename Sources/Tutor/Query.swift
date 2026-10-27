import Foundation

// Scryfall-style query language → SQL over the `cards` table.
//
// Supported: bare words (name), "quoted phrases", !"Exact Name", -negation, ( ) grouping, `or`,
// and keyword filters: name o t c id mv pow tou loy r s f banned restricted kw m is not year usd
// produces layout cn.

struct CompiledQuery {
    var sql: String
    var binds: [Bind]
    var warnings: [String]
    var isBlank: Bool
}

struct QTerm {
    var field: String?
    var op: String
    var value: String
    var quoted: Bool
}

indirect enum QNode {
    case term(QTerm)
    case and([QNode])
    case or([QNode])
    case not(QNode)
}

// MARK: - Parser

struct QParser {
    private let s: [Character]
    private var i = 0

    init(_ str: String) { s = Array(str) }

    private var atEnd: Bool { i >= s.count }

    mutating func parse() -> QNode? {
        var nodes: [QNode] = []
        while true {
            if let n = parseOr() { nodes.append(n) }
            if i < s.count, s[i] == ")" { i += 1 } else { break }
        }
        if nodes.isEmpty { return nil }
        return nodes.count == 1 ? nodes[0] : .and(nodes)
    }

    private mutating func skipWS() {
        while i < s.count, s[i].isWhitespace { i += 1 }
    }

    private func isOrKeyword() -> Bool {
        guard i + 1 < s.count, s[i] == "o" || s[i] == "O", s[i + 1] == "r" || s[i + 1] == "R" else { return false }
        return i + 2 >= s.count || s[i + 2].isWhitespace || s[i + 2] == "("
    }

    private mutating func parseOr() -> QNode? {
        var parts: [QNode] = []
        if let a = parseAnd() { parts.append(a) }
        while true {
            skipWS()
            guard isOrKeyword() else { break }
            i += 2
            if let b = parseAnd() { parts.append(b) }
        }
        if parts.isEmpty { return nil }
        return parts.count == 1 ? parts[0] : .or(parts)
    }

    private mutating func parseAnd() -> QNode? {
        var parts: [QNode] = []
        while true {
            skipWS()
            if atEnd || s[i] == ")" || isOrKeyword() { break }
            if let u = parseUnary() { parts.append(u) }
        }
        if parts.isEmpty { return nil }
        return parts.count == 1 ? parts[0] : .and(parts)
    }

    private mutating func parseUnary() -> QNode? {
        if s[i] == "-" {
            if i + 1 >= s.count || s[i + 1].isWhitespace { i += 1; return nil }
            i += 1
            if i < s.count, s[i] == ")" { return nil }
            return parseUnary().map { .not($0) }
        }
        if s[i] == "(" {
            i += 1
            let e = parseOr()
            skipWS()
            if !atEnd, s[i] == ")" { i += 1 }
            return e
        }
        return parseTerm()
    }

    private mutating func parseTerm() -> QNode? {
        var chars: [(Character, Bool)] = []
        var sawQuote = false
        while i < s.count {
            let ch = s[i]
            if ch == "\"" {
                sawQuote = true
                i += 1
                while i < s.count, s[i] != "\"" { chars.append((s[i], true)); i += 1 }
                if i < s.count { i += 1 }
                continue
            }
            if ch.isWhitespace || ch == ")" { break }
            chars.append((ch, false))
            i += 1
        }
        if chars.isEmpty { return nil }

        if chars[0] == ("!", false) {
            let v = String(chars.dropFirst().map { $0.0 })
            return .term(QTerm(field: "!", op: ":", value: v, quoted: true))
        }

        var j = 0
        while j < chars.count, !chars[j].1, chars[j].0.isLetter { j += 1 }
        if j > 0, j < chars.count, !chars[j].1, let op = opAt(chars, j) {
            let field = String(chars[0..<j].map { $0.0 })
            let rest = chars[(j + op.count)...]
            return .term(QTerm(field: field, op: op, value: String(rest.map { $0.0 }), quoted: rest.contains { $0.1 }))
        }
        return .term(QTerm(field: nil, op: ":", value: String(chars.map { $0.0 }), quoted: sawQuote))
    }

    private func opAt(_ c: [(Character, Bool)], _ j: Int) -> String? {
        let a = c[j]
        guard !a.1 else { return nil }
        let b: Character? = j + 1 < c.count && !c[j + 1].1 ? c[j + 1].0 : nil
        switch (a.0, b) {
        case ("<", "="): return "<="
        case (">", "="): return ">="
        case ("!", "="): return "!="
        case (":", _): return ":"
        case ("=", _): return "="
        case ("<", _): return "<"
        case (">", _): return ">"
        default: return nil
        }
    }
}

// MARK: - Compiler

struct QCompiler {
    var binds: [Bind] = []
    var warnings: [String] = []

    mutating func node(_ n: QNode) -> String? {
        switch n {
        case .term(let t):
            return term(t)
        case .and(let ps):
            let parts = ps.compactMap { node($0) }
            return parts.isEmpty ? nil : "(" + parts.joined(separator: " AND ") + ")"
        case .or(let ps):
            let parts = ps.compactMap { node($0) }
            return parts.isEmpty ? nil : "(" + parts.joined(separator: " OR ") + ")"
        case .not(let c):
            guard let s = node(c) else { return nil }
            return "NOT COALESCE(\(s),0)"
        }
    }

    private mutating func b(_ x: Bind) { binds.append(x) }

    private func sqlOp(_ op: String) -> String {
        switch op {
        case ":", "=": return "="
        case "!=": return "<>"
        default: return op
        }
    }

    private mutating func nameLike(_ v: String) -> String? {
        let n = TextNorm.normName(v)
        if n.isEmpty { return nil }
        b(.text(n))
        return "instr(name_norm, ?) > 0"
    }

    private mutating func numeric(_ col: String, _ t: QTerm, label: String, other: [String: String] = [:]) -> String? {
        if let o = other[t.value.lowercased()] {
            return "(\(col) IS NOT NULL AND \(o) IS NOT NULL AND \(col) \(sqlOp(t.op)) \(o))"
        }
        guard let d = Double(t.value) else {
            warnings.append("\(label): “\(t.value)” is not a number")
            return nil
        }
        b(.double(d))
        return "(\(col) IS NOT NULL AND \(col) \(sqlOp(t.op)) ?)"
    }

    private mutating func colorExpr(_ col: String, _ t: QTerm, identity: Bool) -> String? {
        let v = t.value.lowercased()
        var op = t.op
        if op == ":" { op = identity ? "<=" : ">=" }

        if v == "c" || v == "colorless" || v == "0" {
            switch t.op {
            case "!=": return "\(col) <> 0"
            case ":", "=", "<=": return "\(col) = 0"
            case ">=": return "1"
            case ">": return "\(col) <> 0"
            default: return "0"
            }
        }
        if v == "m" || v == "multi" || v == "multicolor" || v == "multicolour" {
            let multi = "(\(col) & (\(col) - 1)) <> 0"
            return t.op == "!=" ? "NOT \(multi)" : multi
        }
        guard let m = Colors.mask(v) else {
            warnings.append("Unknown colour “\(t.value)”")
            return nil
        }
        let M = Int64(m)
        switch op {
        case ">=": b(.int(M)); b(.int(M)); return "((\(col) & ?) = ?)"
        case "<=": b(.int(M)); b(.int(M)); return "((\(col) | ?) = ?)"
        case "=": b(.int(M)); return "\(col) = ?"
        case "!=": b(.int(M)); return "\(col) <> ?"
        case ">": b(.int(M)); b(.int(M)); b(.int(M)); return "((\(col) & ?) = ? AND \(col) <> ?)"
        case "<": b(.int(M)); b(.int(M)); b(.int(M)); return "((\(col) | ?) = ? AND \(col) <> ?)"
        default: return nil
        }
    }

    private func manaCostString(_ v: String) -> String {
        if v.contains("{") { return v.uppercased() }
        var out = ""
        var digits = ""
        func flush() { if !digits.isEmpty { out += "{\(digits)}"; digits = "" } }
        for ch in v.uppercased() {
            if ch.isNumber { digits.append(ch) } else { flush(); out += "{\(ch)}" }
        }
        flush()
        return out
    }

    private mutating func rangeCompare(_ lo: String, _ hi: String, _ t: QTerm, label: String, value: Double?) -> String? {
        guard let x = value else {
            warnings.append("\(label): “\(t.value)” is not a valid value")
            return nil
        }
        switch t.op {
        case ":", "=":
            b(.double(x)); b(.double(x))
            return "(\(lo) IS NOT NULL AND \(lo) <= ? AND \(hi) >= ?)"
        case ">", ">=":
            b(.double(x))
            return "(\(hi) IS NOT NULL AND \(hi) \(t.op) ?)"
        case "<", "<=":
            b(.double(x))
            return "(\(lo) IS NOT NULL AND \(lo) \(t.op) ?)"
        case "!=":
            b(.double(x)); b(.double(x))
            return "(\(lo) IS NOT NULL AND NOT (\(lo) <= ? AND \(hi) >= ?))"
        default:
            return nil
        }
    }

    mutating func term(_ t: QTerm) -> String? {
        guard let rawField = t.field else { return nameLike(t.value) }
        let field = rawField.lowercased()
        let v = t.value

        if field == "!" {
            let n = TextNorm.normName(v)
            if n.isEmpty { return nil }
            b(.text(n)); b(.text(n + " // %"))
            return "(name_norm = ? OR name_norm LIKE ?)"
        }
        if v.isEmpty { return nil }

        switch field {
        case "name", "n":
            return nameLike(v)

        case "o", "oracle", "text":
            b(.text(v.lowercased()))
            return "instr(text_lc, ?) > 0"

        case "t", "type":
            b(.text(v.lowercased()))
            return "instr(type_lc, ?) > 0"

        case "c", "color", "colour":
            return colorExpr("colors", t, identity: false)

        case "id", "identity", "ci", "coloridentity":
            return colorExpr("ci", t, identity: true)

        case "mv", "cmc", "manavalue":
            let lv = v.lowercased()
            if lv == "even" { return "(CAST(cmc AS INTEGER) % 2 = 0)" }
            if lv == "odd" { return "(CAST(cmc AS INTEGER) % 2 = 1)" }
            return numeric("cmc", t, label: "mana value")

        case "pow", "power":
            return numeric("pow", t, label: "power", other: ["tou": "tou", "toughness": "tou"])

        case "tou", "toughness":
            return numeric("tou", t, label: "toughness", other: ["pow": "pow", "power": "pow"])

        case "loy", "loyalty":
            return numeric("loy", t, label: "loyalty")

        case "r", "rarity":
            guard let idx = Rarity.index(v) else { warnings.append("Unknown rarity “\(v)”"); return nil }
            var mask = 0
            switch t.op {
            case ":", "=": mask = 1 << idx
            case ">=": for k in idx...5 { mask |= 1 << k }
            case ">": if idx < 5 { for k in (idx + 1)...5 { mask |= 1 << k } }
            case "<=": for k in 0...idx { mask |= 1 << k }
            case "<": if idx > 0 { for k in 0..<idx { mask |= 1 << k } }
            case "!=":
                b(.int(Int64(1 << idx)))
                return "(rarities & ?) = 0"
            default: break
            }
            b(.int(Int64(mask)))
            return "(rarities & ?) <> 0"

        case "s", "set", "e", "edition":
            b(.text(v.lowercased()))
            let sub = "id IN (SELECT card_id FROM printings WHERE set_code = ?)"
            return t.op == "!=" ? "NOT (\(sub))" : sub

        case "cn", "number":
            b(.text(v.lowercased()))
            return "id IN (SELECT card_id FROM printings WHERE cn = ?)"

        case "f", "format", "legal", "banned", "restricted":
            guard let bit = Formats.bit(v) else { warnings.append("Unknown format “\(v)”"); return nil }
            let col = field == "banned" ? "banned" : field == "restricted" ? "restricted" : "legal"
            b(.int(Int64(1 << bit)))
            return "(\(col) & ?) <> 0"

        case "kw", "keyword":
            b(.text(v.lowercased()))
            return "instr(keywords_lc, ?) > 0"

        case "m", "mana":
            b(.text(manaCostString(v)))
            return "instr(mana_cost, ?) > 0"

        case "produces":
            var m = 0
            for ch in v.lowercased() {
                if let bit = Colors.bits[ch] { m |= bit } else if ch == "c" { m |= 32 }
                else { warnings.append("produces: unknown colour “\(v)”"); return nil }
            }
            b(.int(Int64(m))); b(.int(Int64(m)))
            return "(produced & ?) = ?"

        case "is", "not":
            guard let flag = CardFlag.byName[v.lowercased()] else {
                warnings.append("Unknown is:\(v)")
                return nil
            }
            let e = "(flags & \(1 << flag.rawValue)) <> 0"
            return field == "not" ? "NOT \(e)" : e

        case "year", "date":
            let digits = v.prefix(4)
            return rangeCompare("year_min", "year_max", t, label: "year", value: Double(digits))

        case "usd":
            return rangeCompare("usd_min", "usd_max", t, label: "usd", value: Double(v))

        case "layout":
            b(.text(v.lowercased()))
            return "layout = ?"

        default:
            warnings.append("Unsupported keyword “\(rawField):”")
            return nil
        }
    }
}

enum QueryCompiler {
    static func compile(_ raw: String) -> CompiledQuery {
        var parser = QParser(raw)
        let root = parser.parse()
        var c = QCompiler()

        var whereSQL = "1"
        if let root, let w = c.node(root) { whereSQL = w }

        // Bare words drive relevance ranking.
        var bare: [String] = []
        func collect(_ n: QNode) {
            switch n {
            case .term(let t): if t.field == nil { bare.append(t.value) }
            case .and(let ps): ps.forEach(collect)
            default: break
            }
        }
        if let root { collect(root) }
        let phrase = TextNorm.normName(bare.joined(separator: " "))

        let blank = root == nil || (whereSQL == "1" && c.warnings.isEmpty && raw.trimmingCharacters(in: .whitespaces).isEmpty)
        var order: String
        if blank {
            order = "ORDER BY pop, id"
        } else if !phrase.isEmpty {
            order = "ORDER BY CASE WHEN name_norm = ? THEN 0 WHEN instr(name_norm, ?) = 1 THEN 1 WHEN instr(name_norm, ?) > 0 THEN 2 ELSE 3 END, pop, id"
            c.binds.append(.text(phrase))
            c.binds.append(.text(phrase))
            c.binds.append(.text(" " + phrase))
        } else {
            order = "ORDER BY id"
        }

        return CompiledQuery(
            sql: "SELECT id FROM cards WHERE \(whereSQL) \(order)",
            binds: c.binds,
            warnings: c.warnings,
            isBlank: blank
        )
    }
}
