import Foundation

/// One paper, written as a short "daily read": a hook, numbered key insights, a summary and a lesson.
struct Paper: Identifiable, Hashable, Codable {
    let id: String              // stable slug, used for persistence
    let title: String
    let shortTitle: String      // shown on the generated cover
    let authors: String         // byline
    let aboutAuthors: String
    let year: Int
    let venue: String
    let topic: Topic
    let url: URL
    let readMinutes: Int
    let hook: String            // one-sentence promise, shown on cards
    let whoShouldRead: String
    let prerequisites: [String] // ids of papers worth reading first
    let insights: [Insight]
    let numbers: [Fact]         // "By the numbers": sizes, hyperparameters, headline results
    let limitations: String
    let summary: String         // "In a nutshell"
    let lesson: String          // "Apply it"

    // Optional: extra terms to underline in this paper (set by the Mac script).
    var glossary: [GlossaryEntry]? = nil // extra terms to underline in this paper

    struct Insight: Hashable, Codable {
        let headline: String
        let body: String
        var formula: String? = nil   // optional LaTeX; separate several lines with "||"
    }

    struct Fact: Hashable, Codable {
        let label: String
        let value: String
    }

    /// Reader pages, in order.
    var pages: [ReaderPage] {
        [.intro] + insights.indices.map { .insight($0) } + [.numbers, .limitations, .summary, .apply]
    }
}

enum ReaderPage: Hashable {
    case intro
    case insight(Int)
    case numbers
    case limitations
    case summary
    case apply
}

/// Topics are told apart by icon and cover pattern. JSON may use the case name ("vision") or the title.
enum Topic: String, CaseIterable, Hashable, Codable {
    case architectures = "Architectures"
    case language = "Language Models"
    case reasoning = "Reasoning"
    case alignment = "Alignment"
    case vision = "Vision"
    case learning = "Training & RL"
    case other = "Other"

    var icon: String {
        switch self {
        case .architectures: "square.stack.3d.up.fill"
        case .language: "text.bubble.fill"
        case .reasoning: "brain.head.profile"
        case .alignment: "shield.lefthalf.filled"
        case .vision: "eye.fill"
        case .learning: "chart.line.uptrend.xyaxis"
        case .other: "doc.text.fill"
        }
    }

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self).lowercased()
        self = Topic.allCases.first { $0.rawValue.lowercased() == raw || "\($0)".lowercased() == raw } ?? .other
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode("\(self)")
    }
}
