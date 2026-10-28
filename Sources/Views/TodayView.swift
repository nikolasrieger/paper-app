import SwiftUI

struct TodayView: View {
    @Environment(LibraryStore.self) private var store
    @State private var showSettings = false

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 5..<12: "Good morning"
        case 12..<18: "Good afternoon"
        default: "Good evening"
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month().day()).uppercased())
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
                        Text(greeting).font(Theme.serif(32))
                    }
                    Spacer()
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape").font(.title3)
                            .frame(width: 44, height: 44).background(Theme.card, in: Circle())
                    }
                    .accessibilityLabel("Settings")
                }

                if store.papers.isEmpty { emptyState }
                if let paper = store.paperOfTheDay() { hero(paper) }

                // today's paper is already offered by the hero card
                let continuing = store.inProgress.filter { $0 != store.paperOfTheDay() }
                if !continuing.isEmpty { shelf("Continue reading", papers: continuing) }
                let others = store.papers.filter { $0 != store.paperOfTheDay() }
                if !others.isEmpty { shelf("More to read", papers: others) }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .refreshable { await store.syncFolder(force: true) }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Paper.self) { PaperDetailView(paper: $0) }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showSettings) { SettingsView() }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("No papers yet").font(Theme.serif(24))
            Text("Your summaries come from your Mac. Choose the folder it writes to, and papers will appear here.")
                .foregroundStyle(Theme.muted)
            Button { showSettings = true } label: {
                PrimaryButton(title: "Choose papers folder", icon: "folder.fill")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
    }

    private func hero(_ paper: Paper) -> some View {
        NavigationLink(value: paper) {
            VStack(alignment: .leading, spacing: 16) {
                Text("PAPER OF THE DAY").font(.caption.weight(.bold)).foregroundStyle(paper.topic.color)
                HStack(alignment: .top, spacing: 16) {
                    CoverView(paper: paper, width: 110)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(paper.title).font(Theme.serif(20)).multilineTextAlignment(.leading).lineLimit(4)
                        Text(paper.hook).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                        Label("\(paper.readMinutes) min · \(paper.insights.count) key insights", systemImage: "clock")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                PrimaryButton(title: store.lastPage(paper) > 0 ? "Continue" : "Start reading", icon: "book.fill")
            }
            .padding(20)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 24))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        }
        .buttonStyle(.plain)
    }

    private func shelf(_ title: String, papers: [Paper]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(Theme.serif(22))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(papers) { paper in
                        NavigationLink(value: paper) { PaperTile(paper: paper) }.buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 8)
            }
        }
    }
}
