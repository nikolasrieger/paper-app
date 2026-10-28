import SwiftUI

/// A card image for sharing one insight.
struct InsightShareCard: View {
    let paper: Paper
    let headline: String
    let excerpt: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Image(systemName: paper.topic.icon).font(.title2).foregroundStyle(paper.topic.palette.ink.opacity(0.9))
            Text(headline).font(Theme.serif(30)).foregroundStyle(paper.topic.palette.ink)
            Text(excerpt).font(.system(size: 17, design: .serif)).foregroundStyle(paper.topic.palette.ink.opacity(0.92)).lineSpacing(5)
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 2) {
                Text(paper.title).font(.footnote.weight(.semibold)).lineLimit(2)
                Text("\(paper.authors) · \(String(paper.year))").font(.caption).lineLimit(1)
            }
            .foregroundStyle(paper.topic.palette.ink.opacity(0.85))
        }
        .padding(28)
        .frame(width: 380, height: 480, alignment: .topLeading)
        .background(paper.topic.palette.bg)
    }
}

/// Share button that renders the insight card to an image on demand.
struct ShareInsightButton: View {
    let paper: Paper
    let headline: String
    let body_: String

    var body: some View {
        let first = sentenceRanges(in: body_).first.map { String(body_[$0]) } ?? body_
        let card = InsightShareCard(paper: paper, headline: headline, excerpt: first)
        let renderer = ImageRenderer(content: card)
        let _ = { renderer.scale = 3 }()
        if let ui = renderer.uiImage {
            ShareLink(item: Image(uiImage: ui), preview: SharePreview(headline, image: Image(uiImage: ui))) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}
