import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var model
    @State private var blocksExpanded = false

    var body: some View {
        @Bindable var model = model

        List(selection: $model.sidebar) {
            Section("Library") {
                Label("All Characters", systemImage: "character.book.closed")
                    .tag(SidebarItem.all)
                Label("Favorites", systemImage: "star")
                    .badge(model.favorites.count)
                    .tag(SidebarItem.favorites)
                Label("Recents", systemImage: "clock")
                    .tag(SidebarItem.recents)
            }

            if let database = model.database {
                Section("Collections") {
                    ForEach(database.collections) { collection in
                        Label(LocalizedStringKey("collection.\(collection.id)"), systemImage: collection.symbol)
                            .tag(SidebarItem.collection(collection.id))
                    }
                }

                Section("Unicode Blocks", isExpanded: $blocksExpanded) {
                    ForEach(database.populatedBlocks) { block in
                        Text(block.name)
                            .lineLimit(1)
                            .tag(SidebarItem.block(block.index))
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }
}
