#!/usr/bin/env python3
"""Generates Typecase/Resources/Localizable.xcstrings (English source, Dutch and German translations).

Keys must match the string literals in the Swift sources exactly (including %@ / %lld for interpolations).
Run:  python3 Tools/make-strings/make_strings.py
"""
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "..", "Typecase", "Resources", "Localizable.xcstrings")

# key: (nl, de).  English is the key itself unless an explicit English value is given in EN_VALUES.
T = {
    # Sidebar / library
    "Library": ("Bibliotheek", "Bibliothek"),
    "All Characters": ("Alle tekens", "Alle Zeichen"),
    "Favorites": ("Favorieten", "Favoriten"),
    "Recents": ("Recent", "Zuletzt"),
    "Collections": ("Collecties", "Sammlungen"),
    "Unicode Blocks": ("Unicode-blokken", "Unicode-Blöcke"),
    "Search Results": ("Zoekresultaten", "Suchergebnisse"),
    # Main window
    "Search by name, code or description": ("Zoek op naam, code of omschrijving", "Nach Name, Code oder Beschreibung suchen"),
    "Copy Character": ("Kopieer teken", "Zeichen kopieren"),
    "Inspector": ("Informatie", "Informationen"),
    "Show or Hide Inspector": ("Informatie tonen of verbergen", "Informationen ein- oder ausblenden"),
    "Loading characters…": ("Tekens laden…", "Zeichen werden geladen …"),
    "Characters Could Not Be Loaded": ("Tekens konden niet worden geladen", "Zeichen konnten nicht geladen werden"),
    "No Favorites Yet": ("Nog geen favorieten", "Noch keine Favoriten"),
    "Control-click a character and choose Add to Favorites.": (
        "Klik met de Control-toets ingedrukt op een teken en kies 'Voeg toe aan favorieten'.",
        "Klicke bei gedrückter Control-Taste auf ein Zeichen und wähle „Zu Favoriten hinzufügen“."),
    "Nothing Copied Yet": ("Nog niets gekopieerd", "Noch nichts kopiert"),
    "Characters you copy appear here.": ("Tekens die je kopieert verschijnen hier.", "Kopierte Zeichen erscheinen hier."),
    "No Characters": ("Geen tekens", "Keine Zeichen"),
    "%lld characters": None,  # plural, handled below
    # Detail
    "No Character Selected": ("Geen teken geselecteerd", "Kein Zeichen ausgewählt"),
    "Select a character to see its codes, related characters and how to type it.": (
        "Selecteer een teken om de codes, verwante tekens en de toetsencombinatie te zien.",
        "Wähle ein Zeichen, um Codes, verwandte Zeichen und die Tastenkombination zu sehen."),
    "Add to Favorites": ("Voeg toe aan favorieten", "Zu Favoriten hinzufügen"),
    "Remove from Favorites": ("Verwijder uit favorieten", "Aus Favoriten entfernen"),
    "Favorite": ("Favoriet", "Favorit"),
    "Codes": ("Codes", "Codes"),
    "Copy": ("Kopieer", "Kopieren"),
    "Copy %@": ("Kopieer %@", "%@ kopieren"),
    "Information": ("Informatie", "Informationen"),
    "Category": ("Categorie", "Kategorie"),
    "Block": ("Blok", "Block"),
    "Script": ("Schrift", "Schrift"),
    "Introduced": ("Geïntroduceerd", "Eingeführt"),
    "Also Called": ("Ook genoemd", "Auch genannt"),
    "Related Characters": ("Verwante tekens", "Verwandte Zeichen"),
    "Font Alternates": ("Lettertypevarianten", "Schriftvarianten"),
    "This font has no alternate forms of this character.": (
        "Dit lettertype heeft geen varianten van dit teken.", "Diese Schrift hat keine Varianten dieses Zeichens."),
    "Installed Fonts": ("Geïnstalleerde lettertypen", "Installierte Schriften"),
    "In %lld font families": ("In %lld lettertypefamilies", "In %lld Schriftfamilien"),
    "No installed font has this character.": (
        "Geen geïnstalleerd lettertype bevat dit teken.", "Keine installierte Schrift enthält dieses Zeichen."),
    "No installed font draws this character": (
        "Geen geïnstalleerd lettertype tekent dit teken", "Keine installierte Schrift stellt dieses Zeichen dar"),
    "Zero width": ("Nulbreedte", "Null Breite"),
    "Width: %@ em": ("Breedte: %@ em", "Breite: %@ em"),
    # Typing
    "Typing": ("Typen", "Eingabe"),
    "Typing on “%@”": ("Typen op “%@”", "Eingabe auf „%@“"),
    "then": ("dan", "dann"),
    ", then ": (", dan ", ", dann "),
    "Option": ("Option", "Wahltaste"),
    "Shift": ("Shift", "Umschalttaste"),
    "Not on this keyboard": ("Niet op dit toetsenbord", "Nicht auf dieser Tastatur"),
    "With the Unicode Hex Input keyboard, hold ⌥ and type %@.": (
        "Met het toetsenbord ‘Unicode hex-invoer’ houd je ⌥ ingedrukt en typ je %@.",
        "Mit der Tastatur „Unicode-Hex-Eingabe“ halte ⌥ gedrückt und tippe %@."),
    "Keyboard Settings…": ("Toetsenbordinstellingen…", "Tastatureinstellungen …"),
    "Character Viewer": ("Tekenweergave", "Zeichenübersicht"),
    "The active keyboard layout can't be read.": (
        "De actieve toetsenbordindeling kan niet worden gelezen.", "Das aktive Tastaturlayout kann nicht gelesen werden."),
    "The current input source has no keyboard layout of its own; showing the last Roman layout instead.": (
        "De huidige invoerbron heeft geen eigen toetsenbordindeling; de laatste Latijnse indeling wordt getoond.",
        "Die aktuelle Eingabequelle hat kein eigenes Tastaturlayout; das zuletzt verwendete lateinische Layout wird angezeigt."),
    # Quick Lookup
    "Quick Lookup": ("Snel opzoeken", "Schnellsuche"),
    "Quick Lookup…": ("Snel opzoeken…", "Schnellsuche …"),
    "Search characters": ("Zoek tekens", "Zeichen suchen"),
    "No characters found": ("Geen tekens gevonden", "Keine Zeichen gefunden"),
    "Clear": ("Wis", "Löschen"),
    "Pick 1–9": ("Kies 1–9", "Wähle 1–9"),
    "Pick": ("Kies", "Wähle"),
    "Close": ("Sluit", "Schließen"),
    "Recent": ("Recent", "Zuletzt"),
    # Menu bar
    "Open Typecase": ("Open Typecase", "Typecase öffnen"),
    "Recent Characters": ("Recente tekens", "Zuletzt verwendete Zeichen"),
    "Nothing copied yet": ("Nog niets gekopieerd", "Noch nichts kopiert"),
    "No favorites yet": ("Nog geen favorieten", "Noch keine Favoriten"),
    "Settings…": ("Instellingen…", "Einstellungen …"),
    "Quit Typecase": ("Stop Typecase", "Typecase beenden"),
    # Commands
    "Character": ("Teken", "Zeichen"),
    "Open Font…": ("Open lettertype…", "Schrift öffnen …"),
    "Close Font": ("Sluit lettertype", "Schrift schließen"),
    "Opened Font": ("Geopend lettertype", "Geöffnete Schrift"),
    "Opened font “%@”": ("Lettertype “%@” geopend", "Schrift „%@“ geöffnet"),
    "Not in “%@”. Showing the fallback font.": (
        "Niet in “%@”. Het reservelettertype wordt getoond.", "Nicht in „%@“. Die Ersatzschrift wird angezeigt."),
    "No installed font has this character. Showing a basic stand-in glyph.": (
        "Geen geïnstalleerd lettertype bevat dit teken. Een eenvoudig vervangend teken wordt getoond.",
        "Keine installierte Schrift enthält dieses Zeichen. Es wird ein einfaches Ersatzzeichen angezeigt."),
    "No installed font has this character.": (
        "Geen geïnstalleerd lettertype bevat dit teken.", "Keine installierte Schrift enthält dieses Zeichen."),
    "Not in the opened font": ("Niet in het geopende lettertype", "Nicht in der geöffneten Schrift"),
    "This character is not in the opened font.": (
        "Dit teken zit niet in het geopende lettertype.", "Dieses Zeichen ist nicht in der geöffneten Schrift enthalten."),
    "This file is not a font that macOS can read.": (
        "Dit bestand is geen lettertype dat macOS kan lezen.", "Diese Datei ist keine Schrift, die macOS lesen kann."),
    "Open in App": ("Open in app", "In der App öffnen"),
    "Find…": ("Zoek…", "Suchen …"),
    "Copy Code Point": ("Kopieer codepunt", "Codepunkt kopieren"),
    "Copy HTML Entity": ("Kopieer HTML-entiteit", "HTML-Entität kopieren"),
    "Copy Name": ("Kopieer naam", "Name kopieren"),
    "Clear Recents": ("Wis recente tekens", "Zuletzt verwendete löschen"),
    "Larger Glyphs": ("Grotere tekens", "Größere Zeichen"),
    "Smaller Glyphs": ("Kleinere tekens", "Kleinere Zeichen"),
    "Default Glyph Size": ("Standaardgrootte", "Standardgröße"),
    # Toasts
    "Copied “%@”": ("“%@” gekopieerd", "„%@“ kopiert"),
    "Copied %@": ("%@ gekopieerd", "%@ kopiert"),
    "code point": ("codepunt", "Codepunkt"),
    "HTML entity": ("HTML-entiteit", "HTML-Entität"),
    "name": ("naam", "Name"),
    # Settings
    "General": ("Algemeen", "Allgemein"),
    "Characters": ("Tekens", "Zeichen"),
    "Keyboard": ("Toetsenbord", "Tastatur"),
    "Startup": ("Opstarten", "Start"),
    "Launch at login": ("Open bij inloggen", "Bei Anmeldung öffnen"),
    "Always show in Dock": ("Altijd tonen in het Dock", "Immer im Dock anzeigen"),
    "The Dock icon appears only while the main window is open.": (
        "Het Dock-symbool verschijnt alleen zolang het hoofdvenster open is.",
        "Das Dock-Symbol erscheint nur, solange das Hauptfenster geöffnet ist."),
    "Show in menu bar": ("Toon in de menubalk", "In der Menüleiste anzeigen"),
    "With both turned off, open Quick Lookup with its keyboard shortcut.": (
        "Als beide uit staan, open je Snel opzoeken met de toetsencombinatie.",
        "Wenn beides ausgeschaltet ist, öffne die Schnellsuche mit dem Tastaturkurzbefehl."),
    "Keyboard shortcut": ("Toetsencombinatie", "Tastaturkurzbefehl"),
    "Off": ("Uit", "Aus"),
    "Close after copying": ("Sluit na kopiëren", "Nach dem Kopieren schließen"),
    "Paste into the previous app": ("Plak in de vorige app", "In die vorherige App einsetzen"),
    "Pasting needs permission under System Settings › Privacy & Security › Accessibility.": (
        "Plakken vereist toestemming in Systeminstellingen › Privacy en beveiliging › Toegankelijkheid.",
        "Einsetzen erfordert eine Freigabe unter Systemeinstellungen › Datenschutz & Sicherheit › Bedienungshilfen."),
    "Characters are copied to the clipboard. Press ⌘V in your document to paste.": (
        "Tekens worden naar het klembord gekopieerd. Druk op ⌘V in je document om te plakken.",
        "Zeichen werden in die Zwischenablage kopiert. Drücke ⌘V in deinem Dokument, um sie einzusetzen."),
    "Display": ("Weergave", "Darstellung"),
    "Font": ("Lettertype", "Schrift"),
    "System Font": ("Systeemlettertype", "Systemschrift"),
    "Glyph size": ("Tekengrootte", "Zeichengröße"),
    "The font is used for previews and to look for alternate forms of a character.": (
        "Het lettertype wordt gebruikt voor voorvertoningen en om varianten van een teken te zoeken.",
        "Die Schrift wird für Vorschauen und zur Suche nach Varianten eines Zeichens verwendet."),
    "History": ("Geschiedenis", "Verlauf"),
    "Active Keyboard": ("Actief toetsenbord", "Aktive Tastatur"),
    "Current layout": ("Huidige indeling", "Aktuelles Layout"),
    "Characters you can type": ("Tekens die je kunt typen", "Zeichen, die du tippen kannst"),
    "Typing instructions follow the keyboard layout you are using right now and update when you switch input sources.": (
        "De typinstructies volgen de toetsenbordindeling die je nu gebruikt en worden bijgewerkt als je van invoerbron wisselt.",
        "Die Tastenanweisungen folgen dem aktuell verwendeten Tastaturlayout und aktualisieren sich beim Wechsel der Eingabequelle."),
    "Open Keyboard Settings…": ("Open toetsenbordinstellingen…", "Tastatureinstellungen öffnen …"),
    "Open Character Viewer": ("Open Tekenweergave", "Zeichenübersicht öffnen"),
    "Other Ways to Type": ("Andere manieren om te typen", "Weitere Eingabemöglichkeiten"),
    "Add “Unicode Hex Input” under Input Sources to type any character by holding ⌥ and entering its code.": (
        "Voeg ‘Unicode hex-invoer’ toe bij Invoerbronnen om elk teken te typen door ⌥ ingedrukt te houden en de code in te voeren.",
        "Füge „Unicode-Hex-Eingabe“ unter Eingabequellen hinzu, um jedes Zeichen mit gedrückter ⌥-Taste und seinem Code einzugeben."),
    # Intents
    "Find Character": ("Zoek teken", "Zeichen suchen"),
    "Copy the character for ${query}": ("Kopieer het teken voor ${query}", "Zeichen für ${query} kopieren"),
    "Find the character for ${query}": ("Zoek het teken voor ${query}", "Zeichen für ${query} suchen"),
    "Finds a Unicode character from a description such as “thin space” or “em dash”.": (
        "Zoekt een Unicode-teken op basis van een omschrijving zoals “thin space” of “em dash”.",
        "Findet ein Unicode-Zeichen anhand einer Beschreibung wie „thin space“ oder „em dash“."),
    "Copies the best matching Unicode character to the clipboard.": (
        "Kopieert het best passende Unicode-teken naar het klembord.",
        "Kopiert das am besten passende Unicode-Zeichen in die Zwischenablage."),
    "No matching character was found.": ("Er is geen passend teken gevonden.", "Es wurde kein passendes Zeichen gefunden."),
    "The character database could not be loaded.": (
        "De tekendatabase kon niet worden geladen.", "Die Zeichendatenbank konnte nicht geladen werden."),
    "Description": ("Omschrijving", "Beschreibung"),
    # Code format titles (CodeFormats.swift)
    "Code Point": ("Codepunt", "Codepunkt"),
    "Decimal": ("Decimaal", "Dezimal"),
    "URL Encoded": ("URL-gecodeerd", "URL-codiert"),
    "HTML (decimal)": ("HTML (decimaal)", "HTML (dezimal)"),
    "HTML (named)": ("HTML (benoemd)", "HTML (benannt)"),
    "Windows-1252 (Alt code)": ("Windows-1252 (Alt-code)", "Windows-1252 (Alt-Code)"),
    # Collections (sidebar)
    "collection.spaces": ("Spaties en onzichtbare tekens", "Leerzeichen und Unsichtbares"),
    "collection.dashes": ("Streepjes en koppeltekens", "Striche und Bindestriche"),
    "collection.quotes": ("Aanhalingstekens", "Anführungszeichen"),
    "collection.punctuation": ("Leestekens", "Satzzeichen"),
    "collection.typography": ("Typografie en tekens", "Typografie und Zeichen"),
    "collection.math": ("Wiskunde", "Mathematik"),
    "collection.arrows": ("Pijlen", "Pfeile"),
    "collection.currency": ("Valuta", "Währungen"),
    "collection.fractions": ("Breuken en superscript", "Brüche und Hochgestelltes"),
    "collection.diacritics": ("Diakritische tekens", "Diakritische Zeichen"),
    "collection.latin": ("Latijnse letters", "Lateinische Buchstaben"),
    "collection.greek": ("Grieks", "Griechisch"),
    "collection.shapes": ("Vormen en symbolen", "Formen und Symbole"),
    "collection.boxdrawing": ("Kaderlijnen", "Rahmenzeichen"),
    "collection.technical": ("Technisch", "Technisch"),
    "collection.keyboard": ("Toetsenbord en Mac-toetsen", "Tastatur und Mac-Tasten"),
}

EN_VALUES = {
    "collection.spaces": "Spaces & Invisibles",
    "collection.dashes": "Dashes & Hyphens",
    "collection.quotes": "Quotation Marks",
    "collection.punctuation": "Punctuation",
    "collection.typography": "Typography & Marks",
    "collection.math": "Math",
    "collection.arrows": "Arrows",
    "collection.currency": "Currency",
    "collection.fractions": "Fractions & Superscripts",
    "collection.diacritics": "Diacritics",
    "collection.latin": "Latin Letters",
    "collection.greek": "Greek",
    "collection.shapes": "Shapes & Symbols",
    "collection.boxdrawing": "Box Drawing",
    "collection.technical": "Technical",
    "collection.keyboard": "Keyboard & Mac Keys",
}


def unit(value, state="translated"):
    return {"stringUnit": {"state": state, "value": value}}


def plural(one, other):
    return {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}


def main():
    strings = {}
    for key, tr in T.items():
        loc = {}
        if key == "%lld characters":
            loc["en"] = plural("%lld character", "%lld characters")
            loc["nl"] = plural("%lld teken", "%lld tekens")
            loc["de"] = plural("%lld Zeichen", "%lld Zeichen")
        else:
            nl, de = tr
            if key in EN_VALUES:
                loc["en"] = unit(EN_VALUES[key])
            loc["nl"] = unit(nl)
            loc["de"] = unit(de)
        strings[key] = {"extractionState": "manual", "localizations": loc}
    catalog = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8") as f:
        json.dump(catalog, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"{len(strings)} strings -> {os.path.normpath(OUT)}")


if __name__ == "__main__":
    main()
