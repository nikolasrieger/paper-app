import SwiftUI

struct NoteField: View {
    @Environment(LibraryStore.self) private var store
    let paper: Paper
    let page: ReaderPage
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Your note", systemImage: "note.text").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted)
            TextField("Add a note…", text: $text, axis: .vertical)
                .lineLimit(1...6)
                .padding(12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
        .onAppear { text = store.note(paper, page) }
        .onChange(of: text) { _, new in store.setNote(new, paper, page) }
    }
}
