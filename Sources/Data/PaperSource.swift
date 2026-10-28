import Foundation

/// A source of papers for the library.
protocol PaperSource {
    func loadPapers() async throws -> [Paper]
}

/// Optional bundled papers. Return `Paper(...)` values to include papers in the app.
struct BundledPaperSource: PaperSource {
    func loadPapers() async throws -> [Paper] { [] }
}
