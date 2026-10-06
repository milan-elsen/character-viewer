import Foundation

struct SearchResult: Hashable, Sendable {
    let codePoint: UInt32
    let score: Double
}

/// Natural-language search over the character database.
///
/// How it works
///  1. Every record contributes weighted terms from its synonyms, name, aliases, CLDR keywords, notes and a few
///     words derived from its general category ("space", "dash", "currency" ...).
///  2. A query is tokenised the same way. Each token matches terms exactly, by prefix, or (for longer tokens
///     that match nothing) with one typo.
///  3. Records matching every token rank first; records matching only some tokens follow with a penalty, so
///     rambling queries ("the space that is narrower than a normal one") still find something sensible.
///  4. The best candidates are re-ranked with phrase bonuses (exact name / alias / synonym match) and the
///     everyday-typography priority.
final class SearchEngine: @unchecked Sendable {
    private struct Posting {
        let record: Int32
        let weight: Float
    }

    private let database: CharacterDatabase
    private var postings: [String: [Posting]] = [:]
    private var sortedTerms: [String] = []
    private var phrases: [[String]] = []   // per record: normalised phrases (name, aliases, synonyms)

    private enum Weight {
        static let synonym: Float = 4.0
        static let name: Float = 3.0
        static let alias: Float = 3.0
        static let keyword: Float = 1.5
        static let category: Float = 1.0
        static let notes: Float = 0.4
    }

    private static let categoryWords: [String: String] = [
        "Zs": "space whitespace blank",
        "Zl": "line separator",
        "Zp": "paragraph separator",
        "Cf": "invisible format control formatting",
        "Cc": "control",
        "Pd": "dash hyphen",
        "Pi": "quote quotation opening",
        "Pf": "quote quotation closing",
        "Ps": "bracket opening",
        "Pe": "bracket closing",
        "Sc": "currency money",
        "Sm": "math mathematical operator",
        "Sk": "modifier accent",
        "Mn": "combining accent diacritic mark",
        "Mc": "combining mark",
        "Me": "combining enclosing mark",
        "Nd": "digit number",
        "No": "number",
        "Nl": "number numeral",
    ]

    private static let stopWords: Set<String> = [
        "the", "an", "of", "for", "to", "that", "thats", "is", "it", "my", "me", "i", "want", "need", "find",
        "show", "with", "than", "which", "looks", "like", "how", "do", "type", "char", "please", "key",
    ]

    /// Everyday phrases that Unicode spells differently. Applied to the folded query before tokenising.
    private static let phraseReplacements: [(String, String)] = [
        ("upside down", "inverted"), ("upside-down", "inverted"), ("turned over", "turned"),
        ("back to front", "reversed"), ("left to right", "left-to-right"),
    ]

    /// Single words with the Unicode term (or terms) that mean the same thing.
    private static let tokenAlternates: [String: [String]] = [
        "backwards": ["reversed"], "backward": ["reversed"], "mirrored": ["reversed"], "flipped": ["turned", "inverted"],
        "umlaut": ["diaeresis"], "trema": ["diaeresis"], "dieresis": ["diaeresis"],
        "quote": ["quotation"], "quotes": ["quotation"], "tick": ["check"], "checkmark": ["check"],
        "hyphen": ["dash"], "dash": ["hyphen"], "parenthesis": ["parenthesis", "bracket"], "paren": ["parenthesis"],
        "brace": ["curly"], "braces": ["curly"], "hat": ["circumflex"], "caret": ["circumflex"],
        "squiggle": ["tilde"], "wavy": ["tilde", "wave"], "backtick": ["grave"], "accent": ["acute", "grave"],
        "currency": ["sign"], "ligature": ["ligature"], "enter": ["return"], "newline": ["line"],
    ]

    init(database: CharacterDatabase) {
        self.database = database
        build()
    }

    // MARK: Tokenising

    static func fold(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
    }

    static func tokens(_ s: String) -> [String] {
        var out: [String] = []
        var cur = ""
        for ch in fold(s) {
            if ch.isLetter || ch.isNumber {
                cur.append(ch)
            } else if !cur.isEmpty {
                out.append(cur)
                cur = ""
            }
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    // MARK: Index

    private func build() {
        var posting: [String: [Posting]] = [:]
        phrases.reserveCapacity(database.count)

        for (i, r) in database.records.enumerated() {
            var best: [String: Float] = [:]
            func add(_ text: String, _ w: Float) {
                for t in Self.tokens(text) where best[t, default: 0] < w { best[t] = w }
            }
            for s in r.synonyms { add(s, Weight.synonym) }
            add(r.name, Weight.name)
            for a in r.aliases { add(a, Weight.alias) }
            for k in r.keywords { add(k, Weight.keyword) }
            if let words = Self.categoryWords[r.category] { add(words, Weight.category) }
            add(r.notes, Weight.notes)
            for (t, w) in best { posting[t, default: []].append(Posting(record: Int32(i), weight: w)) }

            var p: [String] = [Self.fold(r.name)]
            p.append(contentsOf: r.aliases.map(Self.fold))
            p.append(contentsOf: r.synonyms.map(Self.fold))
            phrases.append(p.map { Self.tokens($0).joined(separator: " ") })
        }
        postings = posting
        sortedTerms = posting.keys.sorted()
    }

    private func idf(_ term: String) -> Double {
        let df = Double(postings[term]?.count ?? 1)
        return log(1.0 + Double(database.count) / df)
    }

    // MARK: Term matching

    struct TermMatch {
        let term: String
        let factor: Double
    }

    private func lowerBound(_ prefix: String) -> Int {
        var lo = 0, hi = sortedTerms.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if sortedTerms[mid] < prefix { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    func matches(for token: String) -> [TermMatch] {
        var out: [TermMatch] = []
        if postings[token] != nil { out.append(TermMatch(term: token, factor: 1.0)) }
        // Prefix matching for tokens of two or more characters ("quot" -> "quotation").
        if token.count >= 2 {
            var i = lowerBound(token)
            var taken = 0
            while i < sortedTerms.count, sortedTerms[i].hasPrefix(token), taken < 400 {
                if sortedTerms[i] != token { out.append(TermMatch(term: sortedTerms[i], factor: 0.6)) }
                i += 1
                taken += 1
            }
        }
        // Typo tolerance when nothing (or only a very rare term) matched: one edit (two for long words)
        // against terms with the same first letter.
        // Only "real" fields count here: a stray mention in a note must not suppress typo correction.
        let strongMatches = out.reduce(0) { sum, m in sum + (postings[m.term]?.filter { $0.weight >= 1.0 }.count ?? 0) }
        if token.count >= 3, out.isEmpty || strongMatches < 4 {
            let maxDistance = token.count >= 8 ? 2 : 1
            let first = token.first
            let tokenChars = Array(token)
            for term in sortedTerms where term.first == first {
                if abs(term.count - token.count) > maxDistance { continue }
                if term != token, Self.editDistance(tokenChars, Array(term), limit: maxDistance) <= maxDistance,
                   !out.contains(where: { $0.term == term }) {
                    out.append(TermMatch(term: term, factor: 0.35))
                }
            }
        }
        return out
    }

    /// Damerau-Levenshtein (optimal string alignment) with an early exit.
    static func editDistance(_ a: [Character], _ b: [Character], limit: Int) -> Int {
        if a == b { return 0 }
        if abs(a.count - b.count) > limit { return limit + 1 }
        var prev2 = [Int](repeating: 0, count: b.count + 1)
        var prev = Array(0...b.count)
        var cur = [Int](repeating: 0, count: b.count + 1)
        for i in 1...max(a.count, 1) where i <= a.count {
            cur[0] = i
            var rowMin = cur[0]
            for j in 1...max(b.count, 1) where j <= b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                var v = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] {
                    v = min(v, prev2[j - 2] + 1)
                }
                cur[j] = v
                rowMin = min(rowMin, v)
            }
            if rowMin > limit { return limit + 1 }
            (prev2, prev, cur) = (prev, cur, prev2)
        }
        return prev[b.count]
    }

    // MARK: Search

    /// - Parameters:
    ///   - boosts: extra score per code point (for example recently used characters).
    func search(_ query: String, limit: Int = 600, boosts: [UInt32: Double] = [:]) -> [SearchResult] {
        if query.isEmpty { return [] }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        var results: [SearchResult] = []
        var seen = Set<UInt32>()

        // Exact input first: "U+2009", "&thinsp;", a pasted character ...
        for cp in QueryParser.exactCodePoints(in: query, database: database) where seen.insert(cp).inserted {
            results.append(SearchResult(codePoint: cp, score: 1_000_000))
        }

        if !trimmed.isEmpty {
            for r in textSearch(trimmed, limit: limit, boosts: boosts) where seen.insert(r.codePoint).inserted {
                results.append(r)
            }
        }
        return Array(results.prefix(limit))
    }

    private func textSearch(_ query: String, limit: Int, boosts: [UInt32: Double]) -> [SearchResult] {
        var folded = Self.fold(query)
        for (phrase, replacement) in Self.phraseReplacements { folded = folded.replacingOccurrences(of: phrase, with: replacement) }
        var tokens = Self.tokens(folded)
        if tokens.isEmpty { return [] }
        let filtered = tokens.filter { !Self.stopWords.contains($0) }
        if !filtered.isEmpty { tokens = filtered }
        // Remove duplicates but keep order.
        var seenTokens = Set<String>()
        tokens = tokens.filter { seenTokens.insert($0).inserted }

        var scores: [Int32: Double] = [:]
        var coverage: [Int32: Int] = [:]

        for token in tokens {
            var termMatches = matches(for: token)
            for alt in Self.tokenAlternates[token] ?? [] where alt != token {
                termMatches += matches(for: alt).map { TermMatch(term: $0.term, factor: $0.factor * 0.9) }
            }
            var best: [Int32: Double] = [:]
            for m in termMatches {
                guard let list = postings[m.term] else { continue }
                let weightIdf = idf(m.term)
                for p in list {
                    let s = Double(p.weight) * weightIdf * m.factor
                    if s > best[p.record, default: 0] { best[p.record] = s }
                }
            }
            for (rec, s) in best {
                scores[rec, default: 0] += s
                coverage[rec, default: 0] += 1
            }
        }

        let total = tokens.count
        var candidates: [(Int32, Double)] = []
        candidates.reserveCapacity(scores.count)
        for (rec, s) in scores {
            let covered = coverage[rec] ?? 0
            let ratio = Double(covered) / Double(total)
            // Full coverage counts fully; partial coverage is squashed so complete matches always win.
            let factor = covered == total ? 1.0 : ratio * ratio * 0.35
            candidates.append((rec, s * factor))
        }
        candidates.sort { $0.1 > $1.1 }
        candidates = Array(candidates.prefix(max(limit * 2, 400)))

        let phraseQuery = tokens.joined(separator: " ")
        let rawPhrase = Self.tokens(query).joined(separator: " ")
        var out: [SearchResult] = []
        out.reserveCapacity(candidates.count)
        for (rec, base) in candidates {
            let r = database.records[Int(rec)]
            var score = base
            // Shorter names are better answers to short queries.
            let nameTokens = Self.tokens(r.name).count
            score /= 1.0 + 0.06 * Double(max(0, nameTokens - total))
            // Phrase bonuses.
            var bonus = 0.0
            for p in phrases[Int(rec)] {
                if p == phraseQuery || p == rawPhrase {
                    bonus = max(bonus, 40)
                } else if p.hasPrefix(phraseQuery + " ") || p.hasPrefix(phraseQuery) {
                    bonus = max(bonus, 10)
                } else if (" " + p + " ").contains(" " + phraseQuery + " ") {
                    bonus = max(bonus, 6)
                }
            }
            score += bonus
            switch r.priority {
            case 0: break
            case 1: score *= 0.7
            default: score *= 0.35
            }
            score += boosts[r.codePoint] ?? 0
            out.append(SearchResult(codePoint: r.codePoint, score: score))
        }
        out.sort { $0.score == $1.score ? $0.codePoint < $1.codePoint : $0.score > $1.score }
        return Array(out.prefix(limit))
    }
}

// MARK: - Exact input

enum QueryParser {
    /// Code points the query names *exactly*: "U+2009", "0x2009", " ", "&#8201;", "&thinsp;", "2009" or the
    /// character itself (also several pasted characters). Only code points present in the database are returned.
    static func exactCodePoints(in query: String, database: CharacterDatabase) -> [UInt32] {
        var found: [UInt32] = []
        func add(_ cp: UInt32?) {
            if let cp, database.record(for: cp) != nil, !found.contains(cp) { found.append(cp) }
        }
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = q.lowercased()

        // Lists such as "U+2009 U+200A" or "2009, 200a".
        let parts = lower.split(whereSeparator: { $0 == " " || $0 == "," || $0 == ";" }).map(String.init)
        if parts.count > 1, parts.count <= 12, parts.allSatisfy({ parseHexReference($0) != nil }) {
            for p in parts { add(parseHexReference(p)) }
            return found
        }

        if let cp = parseHexReference(lower) { add(cp) }
        if lower.hasPrefix("&"), lower.hasSuffix(";") {
            let inner = String(lower.dropFirst().dropLast())
            if inner.hasPrefix("#x"), let v = UInt32(inner.dropFirst(2), radix: 16) {
                add(v)
            } else if inner.hasPrefix("#"), let v = UInt32(inner.dropFirst()) {
                add(v)
            } else if let cp = database.codePoint(forEntity: String(q.dropFirst().dropLast())) {
                add(cp)
            } else if let cp = database.codePoint(forEntity: inner) {
                add(cp)
            }
        }
        // Decimal code point: "8364".
        if lower.count >= 2, lower.count <= 7, lower.allSatisfy(\.isASCII), lower.allSatisfy(\.isNumber), let v = UInt32(lower) {
            add(v)
        }
        // Pasted characters. Plain ASCII letters/digits are ordinary words, except a single one.
        let scalars = Array(query.unicodeScalars)   // untrimmed: a pasted thin space is whitespace
        if !scalars.isEmpty, scalars.count <= 16 {
            let hasWordLike = scalars.contains { $0.isASCII && ($0.properties.isAlphabetic || ("0"..."9").contains($0)) }
            if scalars.count == 1 || !hasWordLike {
                for s in scalars where s.value != 0x20 || scalars.count == 1 {
                    add(s.value)
                }
            }
        }
        return found
    }

    /// "u+2009", "0x2009", " ", "\u{2009}", "U+1F600" or a bare 4-6 digit hex number.
    static func parseHexReference(_ s: String) -> UInt32? {
        var t = s.lowercased()
        var explicitPrefix = false
        for prefix in ["u+", "0x", "\\u{", "\\u", "\\x"] where t.hasPrefix(prefix) && t.count > prefix.count {
            t = String(t.dropFirst(prefix.count))
            explicitPrefix = true
            break
        }
        if t.hasSuffix("}") { t.removeLast() }
        guard !t.isEmpty, t.count <= 6, t.allSatisfy(\.isHexDigit), let v = UInt32(t, radix: 16), v <= 0x10FFFF else { return nil }
        if explicitPrefix || t.count >= 4 { return v }
        return nil
    }
}
