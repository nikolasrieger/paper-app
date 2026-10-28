import Foundation

extension ReaderPage {
    /// Stable identifier used to attach highlights and notes to a page.
    var key: String {
        switch self {
        case .intro: "intro"
        case .insight(let i): "i\(i)"
        case .numbers: "numbers"
        case .limitations: "limitations"
        case .summary: "summary"
        case .apply: "apply"
        }
    }
}

extension Paper {
    func page(forKey key: String) -> ReaderPage? { pages.first { $0.key == key } }

    func title(for page: ReaderPage) -> String {
        switch page {
        case .intro: "Overview"
        case .insight(let i): insights[i].headline
        case .numbers: "By the numbers"
        case .limitations: "Limitations"
        case .summary: "In a nutshell"
        case .apply: "Takeaway"
        }
    }

    /// Main prose of a page; only these pages can be highlighted. Nil elsewhere.
    func prose(for page: ReaderPage) -> String? {
        switch page {
        case .insight(let i): insights[i].body
        case .limitations: limitations
        case .summary: summary
        case .apply: lesson
        case .intro, .numbers: nil
        }
    }

    /// What the audio mode reads aloud for a page.
    func spoken(for page: ReaderPage) -> String {
        switch page {
        case .intro:
            "\(title). \(hook) This paper has \(insights.count) key insights."
        case .insight(let i):
            "Insight \(i + 1). \(insights[i].headline). \(insights[i].body)"
        case .numbers:
            "By the numbers. " + numbers.map { "\($0.label): \($0.value)." }.joined(separator: " ")
        case .limitations:
            "Limitations. \(limitations)"
        case .summary:
            "In a nutshell. \(summary)"
        case .apply:
            "Takeaway. \(lesson)"
        }
    }
}

/// Sentence ranges of a text. Highlights are stored as indices into this list.
func sentenceRanges(in text: String) -> [Range<String.Index>] {
    var result: [Range<String.Index>] = []
    text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .bySentences) { _, range, _, _ in
        result.append(range)
    }
    return result
}
