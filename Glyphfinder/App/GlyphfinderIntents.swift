import AppIntents
import AppKit

enum CharacterIntentError: Error, CustomLocalizedStringResourceConvertible {
    case noMatch
    case databaseUnavailable

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noMatch: return "No matching character was found."
        case .databaseUnavailable: return "The character database could not be loaded."
        }
    }
}

private func bestMatch(for query: String) throws -> CharacterRecord {
    switch Catalog.shared {
    case .failure:
        throw CharacterIntentError.databaseUnavailable
    case .success(let catalog):
        guard let hit = catalog.engine.search(query, limit: 1).first,
              let record = catalog.database.record(for: hit.codePoint) else {
            throw CharacterIntentError.noMatch
        }
        return record
    }
}

/// Shortcuts action: "Find Character" returns the best match for a description.
struct FindCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "Find Character"
    static let description = IntentDescription("Finds a Unicode character from a description such as “thin space” or “em dash”.")

    @Parameter(title: "Description")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Find the character for \(\.$query)")
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let record = try bestMatch(for: query)
        return .result(value: record.string)
    }
}

/// Shortcuts action: "Copy Character" puts the best match on the clipboard.
struct CopyCharacterIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Character"
    static let description = IntentDescription("Copies the best matching Unicode character to the clipboard.")

    @Parameter(title: "Description")
    var query: String

    static var parameterSummary: some ParameterSummary {
        Summary("Copy the character for \(\.$query)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let record = try bestMatch(for: query)
        Inserter.copy(record.string)
        return .result(value: record.string)
    }
}

struct GlyphfinderShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: FindCharacterIntent(),
            phrases: ["Find a character in \(.applicationName)"],
            shortTitle: "Find Character",
            systemImageName: "textformat.abc"
        )
        AppShortcut(
            intent: CopyCharacterIntent(),
            phrases: ["Copy a character with \(.applicationName)"],
            shortTitle: "Copy Character",
            systemImageName: "doc.on.doc"
        )
    }
}
