import SwiftUI

/// Everything the user highlighted or wrote, grouped by paper.
struct NotebookView: View {
    @Environment(LibraryStore.self) private var store

    private struct Quote: Identifiable { let id: String; let page: String; let text: String }
    private struct Note: Identifiable { let id: String; let page: String; let text: String }

    private func quotes(_ paper: Paper) -> [Quote] {
        store.highlights.compactMap { key in
            let parts = key.split(separator: "|").map(String.init)
            guard parts.count == 3, parts[0] == paper.id, let page = paper.page(forKey: parts[1]),
                  let sentence = Int(parts[2]), let prose = paper.prose(for: page) else { return nil }
            let ranges = sentenceRanges(in: prose)
            guard sentence < ranges.count else { return nil }
            return Quote(id: key, page: paper.title(for: page),
                         text: String(prose[ranges[sentence]]).trimmingCharacters(in: .whitespacesAndNewlines))
        }.sorted { $0.id < $1.id }
    }

    private func notes(_ paper: Paper) -> [Note] {
        store.notes.compactMap { key, text in
            let parts = key.split(separator: "|").map(String.init)
            guard parts.count == 2, parts[0] == paper.id, let page = paper.page(forKey: parts[1]) else { return nil }
            return Note(id: key, page: paper.title(for: page), text: text)
        }.sorted { $0.id < $1.id }
    }

    private func exportText(_ paper: Paper) -> String {
        var lines = ["Notes on \(paper.title)", paper.url.absoluteString, ""]
        lines += quotes(paper).map { "“\($0.text)”" }
        lines += notes(paper).map { "Note (\($0.page)): \($0.text)" }
        return lines.joined(separator: "\n")
    }

    var body: some View {
        let entries = store.papers.filter { !quotes($0).isEmpty || !notes($0).isEmpty }
        List {
            ForEach(entries) { paper in
                Section {
                    ForEach(quotes(paper)) { q in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(q.text).font(.system(size: 16, design: .serif))
                                .padding(.vertical, 2).background(Theme.highlight)
                            Text(q.page).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    ForEach(notes(paper)) { n in
                        VStack(alignment: .leading, spacing: 4) {
                            Label(n.text, systemImage: "note.text").font(.subheadline)
                            Text(n.page).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                } header: {
                    HStack {
                        NavigationLink(value: paper) { Text(paper.shortTitle).font(.headline).foregroundStyle(Theme.text) }
                        Spacer()
                        ShareLink(item: exportText(paper)) { Image(systemName: "square.and.arrow.up") }
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
        .listRowBackground(Theme.card)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Notebook")
        .navigationDestination(for: Paper.self) { PaperDetailView(paper: $0) }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Nothing yet", systemImage: "highlighter",
                    description: Text("While reading, tap Highlight to mark sentences, or add a note under any insight."))
            }
        }
    }
}
