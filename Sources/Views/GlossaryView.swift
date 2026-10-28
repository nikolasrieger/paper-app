import SwiftUI

struct GlossaryView: View {
    @State private var search = ""
    @State private var selected: GlossaryEntry?

    private var entries: [GlossaryEntry] {
        Glossary.entries.filter {
            search.isEmpty || $0.term.localizedCaseInsensitiveContains(search) || $0.definition.localizedCaseInsensitiveContains(search)
        }.sorted { $0.term.lowercased() < $1.term.lowercased() }
    }

    var body: some View {
        List(entries) { entry in
            Button { selected = entry } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(entry.term).font(.headline).foregroundStyle(Theme.text)
                    Text(entry.definition).font(.subheadline).foregroundStyle(Theme.muted).lineLimit(2)
                }
            }
            .buttonStyle(.plain)
        }
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .listRowBackground(Theme.card)
        .navigationTitle("Glossary")
        .searchable(text: $search)
        .sheet(item: $selected) { GlossarySheet(entry: $0) }
    }
}
