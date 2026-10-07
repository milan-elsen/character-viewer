import AppKit
import SwiftUI

/// Small floating window opened with the global shortcut: type, arrow to the character, press Return to copy it.
struct QuickLookupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @AppStorage(SettingsKey.previewFont) private var fontName = ""

    @State private var query = ""
    @State private var results: [CharacterRecord] = []
    @State private var selectedIndex = 0
    @State private var titlebarHeight = ChromelessWindow.lastMeasuredTitlebarHeight
    @FocusState private var searchFocused: Bool

    private let rowHeight: CGFloat = 54
    private let visibleRows = 7

    var body: some View {
        VStack(spacing: 0) {
            searchField
            if !results.isEmpty {
                Divider()
                resultList
            } else if !query.isEmpty {
                Divider()
                Text("No characters found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: rowHeight)
            }
            Divider()
            footer
        }
        .frame(width: 640)
        // The window reserves room for its hidden title bar below the content too; take that height back so the panel
        // ends at the footer.
        .padding(.bottom, -titlebarHeight)
        // The window has a (hidden) title bar. Newer macOS versions draw it as an empty glass strip unless the content
        // reaches all the way to the top edge, so the panel ignores the top safe area and the material fills the whole
        // window. The window's own shape provides the rounded corners.
        .ignoresSafeArea(.container, edges: .top)
        .background { Rectangle().fill(.regularMaterial).ignoresSafeArea() }
        .background { ChromelessWindow(titlebarHeight: $titlebarHeight) }
        .background { hiddenShortcuts }
        .toast(model.toast)
        .onAppear {
            model.adopt(openWindow: openWindow, dismissWindow: dismissWindow)
            model.quickLookupDidAppear()
            query = ""
            searchFocused = true
        }
        .onDisappear { model.quickLookupDidDisappear() }
        .task(id: query) { await refreshResults() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            searchFocused = true
        }
    }

    // MARK: Pieces

    private var searchField: some View {
        HStack(spacing: 10) {
            // Dragging the loupe moves the window, like a title bar would.
            Image(systemName: "magnifyingglass")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())
                .accessibilityHidden(true)
            TextField("Search characters", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($searchFocused)
                .onSubmit { choose(selectedIndex) }
                .onKeyPress(.downArrow) { move(1); return .handled }
                .onKeyPress(.upArrow) { move(-1); return .handled }
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var resultList: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(spacing: 2) {
                    // Rows are identified by position only; mixing in another identity (the code point) made the lazy
                    // stack keep showing rows from an earlier query.
                    ForEach(results.indices, id: \.self) { index in
                        QuickRow(record: results[index], index: index, isSelected: index == selectedIndex, fontName: fontName)
                            .onTapGesture { choose(index) }
                    }
                }
                .padding(6)
            }
            .frame(height: CGFloat(min(results.count, visibleRows)) * (rowHeight + 2) + 12)
            .onChange(of: selectedIndex) { _, newValue in
                scroller.scrollTo(newValue)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Label("Copy", systemImage: "return")
            Label("Open in App", systemImage: "arrow.up.forward.app")
            Label("Pick 1–9", systemImage: "command")
            Label("Close", systemImage: "escape")
            Spacer()
            if query.isEmpty, !results.isEmpty {
                Text("Recent")
            }
            if !model.keyboard.layoutName.isEmpty {
                Text(model.keyboard.layoutName)
            }
        }
        .labelStyle(.titleAndIcon)
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    /// Invisible buttons that provide the ⌘1…⌘9 and Escape key equivalents.
    private var hiddenShortcuts: some View {
        ZStack {
            ForEach(0..<9, id: \.self) { index in
                Button("") { choose(index) }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
            }
            Button("") { openInApp(selectedIndex) }
                .keyboardShortcut(.return, modifiers: .command)
            Button("") { model.closeQuickLookup(returnToPreviousApp: true) }
                .keyboardShortcut(.cancelAction)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Behavior

    /// Runs whenever the query changes; the previous run is cancelled automatically.
    private func refreshResults() async {
        if query.isEmpty {
            results = model.recents.prefix(8).compactMap { model.record(for: $0) }
            selectedIndex = 0
            return
        }
        try? await Task.sleep(for: .milliseconds(25))
        if Task.isCancelled { return }
        let found = await model.searchAsync(query, limit: 40)
        if Task.isCancelled { return }
        results = found
        selectedIndex = 0
    }

    private func move(_ delta: Int) {
        guard !results.isEmpty else { return }
        selectedIndex = min(max(selectedIndex + delta, 0), results.count - 1)
    }

    /// ⌘↩: show the selected character in the main window instead of copying it.
    private func openInApp(_ index: Int) {
        guard results.indices.contains(index) else { return }
        model.reveal(results[index])
    }

    private func choose(_ index: Int) {
        guard results.indices.contains(index) else { return }
        model.finishQuickLookup(with: results[index])
    }
}

private struct QuickRow: View {
    @Environment(AppModel.self) private var model
    let record: CharacterRecord
    let index: Int
    let isSelected: Bool
    let fontName: String

    var body: some View {
        HStack(spacing: 12) {
            GlyphView(record: record, pointSize: 28, fontName: fontName)
                .frame(width: 46, height: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.titleCasedName)
                    .lineLimit(1)
                Text(CodeFormats.codePoint(record.codePoint))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let sequence = model.keyboard.map?.sequences(for: record.string, limit: 1).first {
                SequenceView(sequence: sequence)
                    .scaleEffect(0.85, anchor: .trailing)
            }
            if index < 9 {
                Text("⌘\(index + 1)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 28, alignment: .trailing)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 54)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(CharacterInfo.accessibilityLabel(for: record))
        .accessibilityValue(CodeFormats.codePoint(record.codePoint))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
