import Foundation

/// One way of writing a character: "U+2009", "&#8201;", "\u{2009}" ...
struct CodeFormat: Identifiable, Hashable, Sendable {
    enum Group: String, Sendable {
        case unicode, encoding, web, programming, legacy
    }

    /// Stable id, also used as the localisation key for the title.
    let id: String
    let title: String
    let value: String
    let group: Group
}

enum CodeFormats {
    static func formats(for record: CharacterRecord, database: CharacterDatabase) -> [CodeFormat] {
        let cp = record.codePoint
        let scalar = record.scalar
        var out: [CodeFormat] = []

        // Unicode
        out.append(CodeFormat(id: "codepoint", title: "Code Point", value: codePoint(cp), group: .unicode))
        out.append(CodeFormat(id: "decimal", title: "Decimal", value: String(cp), group: .unicode))

        // Encodings
        let utf8 = Array(String(scalar).utf8)
        out.append(CodeFormat(id: "utf8", title: "UTF-8", value: utf8.map { hex($0, width: 2) }.joined(separator: " "), group: .encoding))
        let utf16 = Array(String(scalar).utf16)
        out.append(CodeFormat(id: "utf16", title: "UTF-16", value: utf16.map { hex($0, width: 4) }.joined(separator: " "), group: .encoding))
        out.append(CodeFormat(id: "utf32", title: "UTF-32", value: hex(cp, width: 8), group: .encoding))
        out.append(CodeFormat(id: "url", title: "URL Encoded", value: utf8.map { "%" + hex($0, width: 2) }.joined(), group: .encoding))

        // Web
        out.append(CodeFormat(id: "html-dec", title: "HTML (decimal)", value: "&#\(cp);", group: .web))
        out.append(CodeFormat(id: "html-hex", title: "HTML (hex)", value: "&#x\(String(cp, radix: 16, uppercase: true));", group: .web))
        if let entity = database.htmlEntity(for: cp) {
            out.append(CodeFormat(id: "html-named", title: "HTML (named)", value: "&\(entity);", group: .web))
        }
        out.append(CodeFormat(id: "css", title: "CSS", value: "\\" + String(cp, radix: 16, uppercase: true), group: .web))

        // Programming languages
        out.append(CodeFormat(id: "swift", title: "Swift", value: "\\u{\(String(cp, radix: 16, uppercase: true))}", group: .programming))
        out.append(CodeFormat(id: "javascript", title: "JavaScript", value: cp > 0xFFFF
            ? "\\u{\(String(cp, radix: 16, uppercase: true))}"
            : "\\u" + hex(cp, width: 4), group: .programming))
        out.append(CodeFormat(id: "python", title: "Python", value: cp > 0xFFFF
            ? "\\U" + hex(cp, width: 8)
            : "\\u" + hex(cp, width: 4), group: .programming))
        out.append(CodeFormat(id: "json", title: "JSON / Java", value: utf16.map { "\\u" + hex($0, width: 4) }.joined(), group: .programming))
        if cp < 0x80 {
            out.append(CodeFormat(id: "c", title: "C", value: "\\x" + hex(cp, width: 2), group: .programming))
        }

        // Legacy single-byte encodings ("ASCII numbers" and Alt codes)
        if cp < 0x80 {
            out.append(CodeFormat(id: "ascii", title: "ASCII", value: "\(cp)  (0x\(hex(cp, width: 2)))", group: .legacy))
        }
        if cp >= 0x80, cp < 0x100 {
            out.append(CodeFormat(id: "latin1", title: "ISO 8859-1", value: "\(cp)  (0x\(hex(cp, width: 2)))", group: .legacy))
        }
        if cp >= 0x80, let b = database.macRomanByte(for: cp) {
            out.append(CodeFormat(id: "macroman", title: "Mac OS Roman", value: "\(b)  (0x\(hex(b, width: 2)))", group: .legacy))
        }
        if cp >= 0x80, let b = database.windows1252Byte(for: cp) {
            out.append(CodeFormat(id: "win1252", title: "Windows-1252 (Alt code)", value: "\(b)  (Alt+0\(b))", group: .legacy))
        }
        return out
    }

    static func codePoint(_ cp: UInt32) -> String {
        "U+" + String(cp, radix: 16, uppercase: true).leftPadded(to: 4)
    }

    static func hex<T: BinaryInteger>(_ v: T, width: Int) -> String {
        String(v, radix: 16, uppercase: true).leftPadded(to: width)
    }
}

extension String {
    func leftPadded(to width: Int, with pad: Character = "0") -> String {
        count >= width ? self : String(repeating: pad, count: width - count) + self
    }
}
