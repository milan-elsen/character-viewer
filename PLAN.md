# Character Viewer: build plan

Working name: **Glyphfinder** (placeholder).

A native macOS utility for finding Unicode characters by natural-language search. It covers everything the system emoji viewer doesn't (thin spaces, dashes, quotes, combining marks, invisibles) and excludes emoji. For each character it shows code points, related and alternate glyphs, and how to type it on the **currently active keyboard layout**.

---

## 0. Guiding principles

### 0.1 SwiftUI first, AppKit only as a fallback

Rule: **if SwiftUI can do it, use SwiftUI.** Drop to AppKit only when SwiftUI has no API for it, or the API is demonstrably broken for our use. Every AppKit usage is listed in the table below, with a one-line justification in a code comment, and is revisited whenever we raise the minimum OS.

> **Note on "UIKit":** UIKit is the iOS framework. On macOS the equivalent fallback is **AppKit**, and that is what this plan uses. Catalyst/UIKit-on-Mac would produce a worse Mac app and is ruled out.

| Need | Approach | Fallback |
|---|---|---|
| App lifecycle, scenes | SwiftUI `App`, `Window`, `Settings`, `MenuBarExtra` | none needed |
| Menu bar commands | `.commands { CommandGroup / CommandMenu }`, `.keyboardShortcut` | none needed |
| Search | `.searchable` (toolbar search field), `.searchSuggestions`, `.searchScopes` | none needed |
| Layout | `NavigationSplitView`, `LazyVGrid`, `Table`, `.inspector` | none needed |
| Floating panel above other apps | `Window` + `.windowLevel(.floating)`, `.windowResizability`, `.windowStyle` (macOS 15+) | **AppKit** `NSPanel` (non-activating) only if SwiftUI cannot avoid stealing focus from the frontmost app |
| Global hotkey | `KeyboardShortcuts` package (SwiftUI `Recorder` view) | Carbon `RegisterEventHotKey`, which is what the package wraps. No SwiftUI API exists. |
| Keyboard layout introspection | Plain Swift calling Carbon `TextInputSources` and `UCKeyTranslate` | No UI framework involved |
| Glyph alternates, font coverage | Plain Swift calling CoreText | No UI framework involved |
| Insert into the previous app | `NSPasteboard` plus `CGEvent` for ⌘V | AppKit/CoreGraphics only, with no UI |
| Launch at login | `SMAppService` | n/a |
| Copy/drag out of the grid | SwiftUI `.draggable`, `.copyable`, `Transferable` | none needed |
| Invisible-character preview with ruler | SwiftUI `Canvas` / `Shape` | none needed |

Principles that follow from this:
- **No `NSViewRepresentable` unless the table above says so.** Adding one needs a plan update.
- Prefer new SwiftUI APIs and raise the minimum OS rather than write bridging code. **Minimum OS: macOS 15 (Sequoia).**
- Business logic (store, keyboard mapper, glyph inspector) lives in a UI-free Swift package, so it is testable and not tied to the UI framework.

### 0.2 A properly Mac-like app

The aim is an app that feels like it shipped with macOS. Concretely:

**Structure and menus**
- A real menu bar, not just an icon. App menu (About, Settings…, Hide, Quit), **File** (Close Window ⌘W), **Edit** (Copy ⌘C, Select All, Find ⌘F focuses the search field), **View** (sidebar, inspector, grid/list, text size), **Window**, **Help** (the standard Help menu search field comes free).
- Settings in a `Settings` scene, opened with **⌘,**, using a toolbar-style tabbed layout (General, Search, Keyboard, Fonts).
- A standard About panel (`NSApplication.orderFrontStandardAboutPanel`, which `CommandGroup(replacing: .appInfo)` can invoke).
- **Dock presence is the user's choice:** regular app by default, with a setting to run as menu-bar-only (`LSUIElement` switched at runtime via activation policy). Mac users expect both to work.
- Menu bar item: `MenuBarExtra` with `.window` style for the quick-search popover. Its icon is an SF Symbol (template image), and the item can be hidden in Settings.

**Windowing**
- Standard titlebar and toolbar, native traffic lights, full-screen and zoom behave normally.
- Window position, size and sidebar state are restored (`@SceneStorage`, `defaultSize`, `restorationBehavior`).
- The floating "quick lookup" window: ⌘W / Esc closes it, it follows the user across Spaces, it never steals the frontmost app's focus, and the hotkey summons it Spotlight-style.
- Pin-on-top toggle in the toolbar and the Window menu.

**Look and feel**
- Only **system materials, system colors and SF Symbols** (`.regularMaterial`, `.background`, `.secondary`, `Color.accentColor`). No custom chrome. The user's accent color and appearance (light/dark/auto) are respected.
- System fonts and semantic text styles. Monospaced digits for code points. Respect the user's text size settings where they apply.
- Native controls only: `Table` with sortable columns, `Form` with `.formStyle(.grouped)` in Settings, `ControlGroup`, `Picker`, `Toggle`.
- Motion is minimal and honors **Reduce Motion**; transparency honors **Reduce Transparency**.

**Interaction conventions**
- Fully keyboard-navigable, including Full Keyboard Access. Arrow keys move through results, ⏎ inserts or copies (configurable), ⌘C copies, ⌘F focuses search, ⌘1–⌘9 pick a result, Space opens a Quick Look style preview, Esc clears the search and then closes.
- Context menus (right-click) on every character: Copy Character, Copy Code Point, Copy as HTML/Swift/…, Add to Favorites, Show in Blocks.
- Drag a character out of the grid into any text field (`Transferable`, plain text).
- Standard **Services menu** support: a "Look Up in Character Viewer" service for selected text. **App Intents** and Shortcuts actions: "Find character" and "Copy character".
- Spotlight and Help integration where cheap (App Intents entities are indexed by Spotlight).
- **Undo** where there is something to undo (for example removing a favorite).

**Accessibility and localization**
- Full VoiceOver labels. Every glyph announces its Unicode *name*, not just the glyph, because invisible characters would otherwise read as silence.
- Respect Increase Contrast, Reduce Motion, Reduce Transparency and Dynamic Type equivalents.
- All strings in a String Catalog (`.xcstrings`) from day one. UI in English first, with Dutch and German as the first translations. Number and date formatting through system formatters.

**System behavior**
- App Sandbox where possible. If auto-paste needs Accessibility, request it with the standard flow, explain it in Settings, and degrade to copy-only without it.
- Hardened Runtime, notarized, Developer ID distribution (the App Store sandbox blocks the auto-paste feature). Auto-update via Sparkle with the standard update UI.
- Launch at login through `SMAppService`, surfaced as a standard toggle, so the user can also manage it in System Settings → General → Login Items.
- Follows the user's current input source live (notification-driven), with no restart needed.

---

## 1. Tech stack

| Concern | Choice |
|---|---|
| Language / UI | Swift 6, **SwiftUI** (AppKit only per §0.1) |
| Minimum OS | macOS 15 |
| Persistence of characters | SQLite + FTS5, built at compile time and bundled (via GRDB.swift) |
| User data | `@AppStorage` for settings, SwiftData (or a small JSON file) for favorites and recents |
| Keyboard mapping | Carbon `TextInputSources` and `UCKeyTranslate` |
| Glyph alternates | CoreText (`CTFontCopyFeatures`, GSUB) |
| Semantic search | `NaturalLanguage` (`NLEmbedding`); on newer macOS, optionally Foundation Models for query rewriting |
| Build / packaging | Xcode project + Swift package (UI-free core), notarized DMG, Sparkle |

---

## 2. Character data pipeline (build-time tool)

A command-line tool (`Tools/build-db`) turns Unicode source files into `characters.sqlite`. It is pinned to a Unicode version and checked in with checksums.

1. **Sources** (unicode.org): `UnicodeData.txt`, `NamesList.txt` (informal aliases and cross-references, the main source for natural-language search), `NameAliases.txt`, `emoji-data.txt` (used to **exclude** emoji), `confusables.txt`, `Blocks.txt`, `Scripts.txt`, and **CLDR annotations** (everyday keywords per language).
2. **Exclude:** unassigned, surrogates, private use, emoji (`Emoji_Presentation` / `Extended_Pictographic`). Characters that are only emoji with a variation selector (©, ™, ↔) are **kept**. The ~98k CJK ideographs are hidden behind a setting.
   **Keep:** all space and format characters (U+2000–200A, NBSP, narrow NBSP, ZWJ, ZWNJ, soft hyphen), combining marks, variation selectors.
3. **Curated synonyms file** (YAML): terms Unicode doesn't use, such as "hair space → very thin space", "em dash → long dash", "guillemets → French quotes". Started early and covered by a test list of expected query → result pairs.
4. **Schema:** `chars`, `aliases`, `related`, and an FTS5 virtual table over names, aliases and keywords.

---

## 3. Search (tiers)

1. **Exact input:** `U+2009`, `2009`, `0x2009`, `&thinsp;`, or a pasted character jumps straight to the result.
2. **Full-text:** BM25 over names, aliases, CLDR keywords and synonyms, with prefix matching, typo tolerance (trigram), and a boost for recents and common typographic characters.
3. **Semantic (optional, on-device):** precomputed embeddings plus `NLEmbedding` query vectors, merged into the ranking. Everything is offline, with no API keys.

---

## 4. "How do I type this?" (core feature)

1. Read the active layout (`TISCopyCurrentKeyboardLayoutInputSource` → `kTISPropertyUnicodeKeyLayoutData`).
2. Build a **reverse map**: `UCKeyTranslate` over key codes 0–127 × modifier sets (none, ⇧, ⌥, ⇧⌥, ⇪).
3. **Dead keys:** if a key returns a dead-key state (⌥E on US), translate again from that state to find sequences like `⌥E, E → é`.
4. Show **key caps drawn in SwiftUI** using the layout's printed labels, so the same character shows correctly on US, German, Dutch and so on.
5. Rebuild on `kTISNotifySelectedKeyboardInputSourceChanged`.
6. If it can't be typed directly: suggest Unicode Hex Input (⌥ + hex) if enabled, the system Character Viewer (⌃⌘Space), or a text replacement.
7. Optionally show the same character on the user's other enabled layouts.

---

## 5. Detail view

- Large preview. Invisible characters get a dotted box with an **em-width ruler** drawn in a SwiftUI `Canvas`, so thin, hair and non-breaking spaces are visibly different.
- Codes: U+XXXX, decimal, UTF-8 bytes, UTF-16, HTML (named and numeric), CSS, Swift/JS/Python escapes, LaTeX where one exists. Legacy single-byte codes (**Mac Roman, Windows-1252**) appear as "ASCII-style" numbers for characters above 127.
- **Alternates:** related characters (NamesList cross-references, confusables, decompositions) and **font alternates** for a chosen font (`salt`, `ss01`–`ss20`, `swsh`, `case`).
- Font coverage: which installed fonts contain the glyph.
- Actions: copy character, copy any format, insert into the previous app.

---

## 6. UI layout

- **Main window:** `NavigationSplitView`. The sidebar has Collections (Spaces & invisibles, Dashes, Quotes, Math, Arrows, Currency, Diacritics…), Blocks, Recents, Favorites. The content area is a results grid under a toolbar search field. The detail pane is an `.inspector`.
- **Quick-lookup window:** a compact version of the same views (search field, grid, short detail), summoned by a global hotkey or from the menu bar item.
- **Settings:** General (hotkey, Dock/menu bar, launch at login, insert behavior), Search (languages, CJK on/off), Keyboard (layout handling), Fonts (default font).

---

## 7. Project structure

```
character-viewer/
├─ PLAN.md
├─ GlyphfinderApp/              # SwiftUI app target
│  ├─ App/                      # App, scenes, commands, MenuBarExtra, Settings
│  ├─ Views/                    # Search, Grid, Detail, Browse, KeyCaps
│  └─ Resources/                # Assets, Localizable.xcstrings, characters.sqlite
├─ Packages/GlyphCore/          # UI-free Swift package
│  └─ Sources/
│     ├─ CharacterStore         # SQLite/GRDB
│     ├─ Search                 # query parser, ranking
│     ├─ KeyboardMapper         # UCKeyTranslate reverse map
│     ├─ GlyphInspector         # CoreText
│     └─ Formats                # code-format generators
├─ Tools/build-db/              # data pipeline
└─ Tests/                       # mapper per layout, search ranking, formats
```

---

## 8. Milestones

1. **Scaffold + data pipeline:** repo layout, SQLite generation, emoji excluded, spaces included. Tests for the pipeline.
2. **GlyphCore:** store, formats, exact-input parser, FTS search, with unit tests (these also run on Linux CI where possible).
3. **App shell, Mac conventions:** scenes, menu bar commands, Settings, About, toolbar search, grid, detail inspector, copy and drag.
4. **Keyboard mapper:** direct shortcuts, dead-key sequences, layout change handling, key cap view.
5. **Quick-lookup window and menu bar item:** global hotkey, floating window behavior, insertion into the previous app (with Accessibility permission flow).
6. **Related characters and invisible-character visualization.**
7. **Font alternates and coverage.**
8. **Semantic search.**
9. **Polish:** accessibility audit with VoiceOver, localization (nl, de), App Intents and Services, favorites and recents, Sparkle, notarized DMG.

The first useful version is milestones 1–4.

---

## 9. Constraints and risks

- **Development environment:** the cloud session runs Linux. The data pipeline and the UI-free core package can be written and tested there; the SwiftUI app and Carbon/CoreText services need Xcode on a Mac to build and run. Mac-only code is therefore written carefully and isolated behind protocols, so most logic stays testable off-Mac.
- **Floating window focus behavior** in pure SwiftUI is the most likely place to need the AppKit `NSPanel` fallback. Spike it early (milestone 5).
- **Layouts without `UCKeyboardLayout`** (CJK input methods): degrade gracefully, and test with US, ABC Extended, German, French and Dutch.
- **Font alternates** vary per font. Only list alternates reachable through OpenType features.
- **Search quality** depends mostly on the synonyms list. Treat it as a first-class asset.

---

## 10. Open questions

1. Final app name and bundle identifier.
2. Which languages beyond English, Dutch and German should ship first?
3. Default Enter behavior: insert into the previous app, or copy only?
4. Do you want the same app available on iPadOS or iOS later? (It would affect how much UI code we keep in shared packages.)
