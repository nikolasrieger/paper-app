import SwiftUI

struct LibraryView: View {
    @Environment(LibraryStore.self) private var store
    @State private var search = ""
    @State private var topic: Topic?
    @State private var savedOnly = false

    private var filtered: [Paper] {
        store.papers.filter { paper in
            (topic == nil || paper.topic == topic)
            && (!savedOnly || store.isSaved(paper))
            && (search.isEmpty
                || paper.title.localizedCaseInsensitiveContains(search)
                || paper.authors.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        filterButton("All", selected: topic == nil) { topic = nil }
                        ForEach(Topic.allCases.filter { t in store.papers.contains { $0.topic == t } }, id: \.self) { t in
                            filterButton(t.rawValue, selected: topic == t) { topic = t }
                        }
                    }
                }
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 24) {
                    ForEach(filtered) { paper in
                        NavigationLink(value: paper) { PaperTile(paper: paper, width: 150) }.buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationTitle("Explore")
        .searchable(text: $search, prompt: "Search title or author")
        .navigationDestination(for: Paper.self) { PaperDetailView(paper: $0) }
        .toolbar {
            NavigationLink { GlossaryView() } label: { Image(systemName: "character.book.closed") }
            Toggle(isOn: $savedOnly) { Image(systemName: savedOnly ? "bookmark.fill" : "bookmark") }
                .toggleStyle(.button)
        }
        .overlay {
            if store.papers.isEmpty {
                ContentUnavailableView("No papers yet", systemImage: "books.vertical",
                    description: Text("Choose your papers folder in Settings on the Home tab."))
            } else if filtered.isEmpty { ContentUnavailableView.search }
        }
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(selected ? Theme.accentFill : Theme.card, in: Capsule())
            .foregroundStyle(selected ? Theme.onAccent : Theme.text)
    }
}
