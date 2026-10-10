// Lists the characters in Data/characters.json that no font installed on this Mac can draw.
// Run on macOS:  swift Tools/coverage/system_coverage.swift Data/characters.json > missing.txt
// Output: one hex code point per line. Used to decide which glyphs the bundled fallback font must contain.
import CoreText
import Foundation

let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let root = try JSONSerialization.jsonObject(with: data) as! [String: Any]
let rows = root.values.compactMap { $0 as? [[Any]] }.first { $0.count > 20_000 }!
let base = CTFontCreateUIFontForLanguage(.system, 16, nil)!
var missing = 0
for row in rows {
    guard let cp = (row[0] as? NSNumber)?.uint32Value, let scalar = Unicode.Scalar(cp) else { continue }
    let string = String(Character(scalar)) as CFString
    let font = CTFontCreateForString(base, string, CFRange(location: 0, length: CFStringGetLength(string)))
    let name = CTFontCopyPostScriptName(font) as String
    if name.localizedCaseInsensitiveContains("LastResort") {
        print(String(cp, radix: 16))
        missing += 1
    }
}
FileHandle.standardError.write(Data("missing \(missing) of \(rows.count)\n".utf8))
