import SwiftUI

struct PaperDetailView: View {
    @Environment(LibraryStore.self) private var store
    let paper: Paper
    @State private var showReader = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                CoverView(paper: paper, width: 170).frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 10) {
                    TopicChip(topic: paper.topic)
                    Text(paper.title).font(Theme.serif(26))
                    Text(paper.authors).font(.subheadline).foregroundStyle(Theme.muted)
                    Text("\(paper.venue) · \(String(paper.year)) · \(paper.readMinutes) min read")
                        .font(.caption).foregroundStyle(Theme.muted)
                }

                Button { showReader = true } label: {
                    PrimaryButton(title: store.lastPage(paper) > 0 ? "Continue reading" : "Start reading", icon: "book.fill")
                }

                section("What's in it for me?") {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(paper.insights.enumerated()), id: \.offset) { i, insight in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(i + 1)").font(Theme.serif(16)).foregroundStyle(Theme.onAccent)
                                    .frame(width: 28, height: 28).background(paper.topic.fill, in: Circle())
                                Text(insight.headline).font(.body.weight(.medium))
                            }
                        }
                    }
                }
                section("Who should read it?") { Text(paper.whoShouldRead).foregroundStyle(Theme.muted) }

                let first = store.prerequisites(of: paper)
                if !first.isEmpty { shelf("Read first", first) }
                let next = store.followUps(of: paper)
                if !next.isEmpty { shelf("Read next", next) }

                section("About the authors") { Text(paper.aboutAuthors).foregroundStyle(Theme.muted) }

                Link(destination: paper.url) {
                    Label("Open original paper", systemImage: "arrow.up.right.square")
                }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ShareLink(item: paper.url, subject: Text(paper.title),
                      message: Text("\(paper.title): \(paper.hook)"))
            Button { store.toggleSaved(paper) } label: {
                Image(systemName: store.isSaved(paper) ? "bookmark.fill" : "bookmark")
            }
        }
        .fullScreenCover(isPresented: $showReader) { ReaderView(paper: paper) }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.serif(20))
            content()
        }
    }

    private func shelf(_ title: String, _ papers: [Paper]) -> some View {
        section(title) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(papers) { p in
                        NavigationLink(value: p) { PaperTile(paper: p, width: 100) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
