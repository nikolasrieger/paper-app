import SwiftUI

/// Builds prose with highlighted sentences and tappable glossary terms.
enum RichTextBuilder {
    static func attributed(_ text: String, highlighted: Set<Int> = [], glossary: Bool = true) -> AttributedString {
        var attr = AttributedString(text)

        let sentences = sentenceRanges(in: text)
        for i in highlighted where i < sentences.count {
            if let r = Range(sentences[i], in: attr) {
                attr[r].backgroundColor = Theme.highlight
            }
        }

        guard glossary else { return attr }
        var taken: [Range<String.Index>] = []
        for entry in Glossary.entries {
            for form in entry.allForms {
                let pattern = "\\b" + NSRegularExpression.escapedPattern(for: form) + "\\b"
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                      let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                      let r = Range(m.range, in: text),
                      !taken.contains(where: { $0.overlaps(r) }),
                      let ar = Range(r, in: attr),
                      let url = URL(string: "gloss://\(entry.id)") else { continue }
                attr[ar].link = url
                attr[ar].underlineStyle = .single
                taken.append(r)
                break   // one link per entry
            }
        }
        return attr
    }
}

/// Body text with tappable glossary terms, saved highlights and a highlight mode.
struct RichText: View {
    @Environment(LibraryStore.self) private var store
    let paper: Paper
    let page: ReaderPage
    let text: String
    @Binding var highlightMode: Bool
    var font: Font = .system(size: 18, design: .serif)

    var body: some View {
        Group {
            if highlightMode { sentenceList } else {
                Text(RichTextBuilder.attributed(text, highlighted: store.highlightedSentences(paper, page)))
                    .font(font).lineSpacing(7).tint(Theme.accent)
            }
        }
        .glossaryLinks()
    }

    private var sentenceList: some View {
        let ranges = sentenceRanges(in: text)
        return VStack(alignment: .leading, spacing: 8) {
            Label("Tap sentences to highlight them", systemImage: "highlighter")
                .font(.footnote).foregroundStyle(Theme.muted)
            ForEach(Array(ranges.enumerated()), id: \.offset) { i, r in
                let on = store.isHighlighted(paper, page, i)
                Button { store.toggleHighlight(paper, page, i) } label: {
                    Text(String(text[r]).trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(font).lineSpacing(5).multilineTextAlignment(.leading)
                        .foregroundStyle(Theme.text)
                        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
                        .background(on ? Theme.highlight : Theme.card, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct GlossarySheet: View {
    let entry: GlossaryEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.term).font(Theme.serif(26))
            Text(entry.definition).font(.system(size: 17, design: .serif)).lineSpacing(5)
            if let f = entry.formula { FormulaBlock(formula: f, fontSize: 18) }
            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.background)
        .presentationDetents([.height(300), .medium])
    }
}
