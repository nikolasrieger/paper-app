import SwiftUI

/// One idea per page, big type, progress bar on top, back/next at the bottom.
/// Uses its own swipe pager: a paging TabView inside this layout grows taller than the screen.
struct ReaderView: View {
    @Environment(LibraryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let paper: Paper
    @State private var index = 0
    @State private var forward = true
    @State private var started = false
    @State private var highlightMode = false
    @State private var speech = SpeechController()
    @State private var audioOn = false

    private var pages: [ReaderPage] { paper.pages }
    private var isLast: Bool { index == pages.count - 1 }

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                pageView(pages[index])
                    .id(index)
                    .transition(.asymmetric(
                        insertion: .move(edge: forward ? .trailing : .leading),
                        removal: .move(edge: forward ? .leading : .trailing)))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .simultaneousGesture(DragGesture(minimumDistance: 40).onEnded { v in
                guard abs(v.translation.width) > abs(v.translation.height) * 1.5 else { return }
                if v.translation.width < -60, index < pages.count - 1 { go(to: index + 1) }
                if v.translation.width > 60, index > 0 { go(to: index - 1) }
            })
            footer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .glossaryTooltip(bottomInset: 100, resetOn: index)
        .onAppear {
            speech.onSkip = { delta in let n = index + delta; if pages.indices.contains(n) { go(to: n) } }
            speech.onFinish = { if index < pages.count - 1 { go(to: index + 1) } else { audioOn = false; speech.stop() } }
            guard !started else { return }
            started = true
            index = min(store.lastPage(paper), pages.count - 1)
        }
        .onDisappear { speech.stop() }
        .onChange(of: index) { _, new in
            store.setPage(new, for: paper)
            if audioOn { playAudio(at: new) }
        }
    }

    private func go(to new: Int) {
        forward = new > index
        highlightMode = false
        withAnimation(.easeInOut(duration: 0.25)) { index = new }
    }

    private func toggleAudio() {
        if audioOn { speech.stop(); audioOn = false }
        else { audioOn = true; playAudio(at: index) }
    }

    private func playAudio(at i: Int) {
        speech.play(paper, page: pages[i], next: i + 1 < pages.count ? pages[i + 1] : nil, folder: store.folder)
    }

    private var header: some View {
        VStack(spacing: 14) {
            HStack {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.title3).foregroundStyle(Theme.text) }
                Spacer()
                Text(paper.shortTitle).font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).lineLimit(1)
                Spacer()
                Button { toggleAudio() } label: {
                    Image(systemName: audioOn && !speech.isPaused ? "speaker.wave.2.fill" : "speaker.wave.2").font(.title3)
                        .foregroundStyle(audioOn ? Theme.accent : Theme.text)
                }
                .accessibilityLabel(audioOn ? "Stop audio" : "Listen")
            }
            HStack(spacing: 4) {
                ForEach(pages.indices, id: \.self) { i in
                    Capsule().fill(i <= index ? paper.topic.color : Theme.text.opacity(0.15)).frame(height: 4)
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 8)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button { go(to: index - 1) } label: {
                Image(systemName: "chevron.left").font(.headline).frame(width: 54, height: 54)
                    .background(Theme.card, in: Circle()).foregroundStyle(Theme.text)
            }
            .opacity(index == 0 ? 0.3 : 1).disabled(index == 0)

            Button {
                if isLast { store.markRead(paper); store.setPage(0, for: paper); dismiss() }
                else { go(to: index + 1) }
            } label: {
                PrimaryButton(title: isLast ? "Finish" : "Next", icon: isLast ? "checkmark" : "chevron.right")
            }
        }
        .padding(20)
    }

    private func pageView(_ page: ReaderPage) -> some View {
        ScrollView {
            content(for: page)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24).padding(.vertical, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
    }

    private func tools(_ page: ReaderPage, share: (String, String)? = nil) -> some View {
        HStack {
            Button { highlightMode.toggle() } label: {
                Label(highlightMode ? "Done" : "Highlight", systemImage: "highlighter")
                    .font(.footnote.weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(highlightMode ? Theme.highlight : Theme.card, in: Capsule())
                    .foregroundStyle(Theme.text)
            }
            if let share { ShareInsightButton(paper: paper, headline: share.0, body_: share.1).font(.footnote.weight(.semibold)) }
            Spacer()
        }
    }

    @ViewBuilder
    private func prose(_ page: ReaderPage, text: String, font: Font = .system(size: 18, design: .serif)) -> some View {
        RichText(paper: paper, page: page, text: text, highlightMode: $highlightMode, font: font)
        NoteField(paper: paper, page: page)
    }

    @ViewBuilder
    private func content(for page: ReaderPage) -> some View {
        switch page {
        case .intro:
            VStack(alignment: .leading, spacing: 20) {
                CoverView(paper: paper, width: 140)
                Text("What's in it for me?").font(Theme.serif(30))
                Text(paper.hook).font(.title3).foregroundStyle(Theme.muted)
                ForEach(Array(paper.insights.enumerated()), id: \.offset) { i, insight in
                    Label(insight.headline, systemImage: "\(i + 1).circle.fill")
                        .font(.body.weight(.medium)).foregroundStyle(paper.topic.color)
                }
                if !store.prerequisites(of: paper).isEmpty {
                    Text("Read first").font(.footnote.weight(.semibold)).foregroundStyle(Theme.muted).padding(.top, 8)
                    ForEach(store.prerequisites(of: paper)) { Text("• \($0.shortTitle)").font(.subheadline) }
                }
            }
        case .insight(let i):
            let insight = paper.insights[i]
            VStack(alignment: .leading, spacing: 20) {
                Text("INSIGHT \(i + 1) OF \(paper.insights.count)").font(.caption.weight(.bold)).foregroundStyle(paper.topic.color)
                Text(insight.headline).font(Theme.serif(30))
                if let formula = insight.formula { FormulaBlock(formula: formula) }
                tools(page, share: (insight.headline, insight.body))
                prose(page, text: insight.body)
            }
        case .numbers:
            VStack(alignment: .leading, spacing: 16) {
                Text("BY THE NUMBERS").font(.caption.weight(.bold)).foregroundStyle(paper.topic.color)
                Text("Key facts").font(Theme.serif(32))
                ForEach(paper.numbers, id: \.self) { fact in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(fact.value).font(Theme.serif(20)).foregroundStyle(paper.topic.color)
                        Text(fact.label).font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    Divider()
                }
            }
        case .limitations:
            VStack(alignment: .leading, spacing: 20) {
                Text("LIMITATIONS").font(.caption.weight(.bold)).foregroundStyle(paper.topic.color)
                Text("Where it falls short").font(Theme.serif(32))
                tools(page)
                prose(page, text: paper.limitations)
            }
        case .summary:
            VStack(alignment: .leading, spacing: 20) {
                Text("IN A NUTSHELL").font(.caption.weight(.bold)).foregroundStyle(paper.topic.color)
                tools(page)
                prose(page, text: paper.summary, font: Theme.serif(20, .semibold))
            }
        case .apply:
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "lightbulb.max.fill").font(.largeTitle).foregroundStyle(paper.topic.color)
                Text("Takeaway").font(Theme.serif(32))
                tools(page)
                prose(page, text: paper.lesson)
                Link(destination: paper.url) { Label("Read the original paper", systemImage: "arrow.up.right.square") }
            }
        }
    }
}
