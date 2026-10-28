import Foundation

/// Anything that can supply papers. Today the only built-in source is empty and all papers
/// come from the synced folder; a JSON file, an arXiv client or a backend could conform too.
protocol PaperSource {
    func loadPapers() async throws -> [Paper]
}

/// Papers that ship inside the app. None right now: the app shows whatever your Mac syncs.
/// To ship a paper with the app, return `Paper(...)` values here. The earlier built-in papers
/// are kept as JSON in tools/paper-summarize/examples/ and can be dropped into the synced folder.
struct BundledPaperSource: PaperSource {
    func loadPapers() async throws -> [Paper] { [] }
}
