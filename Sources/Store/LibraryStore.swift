import Foundation
import Observation

/// App-wide state: the loaded papers plus the user's saved / read status.
@Observable
final class LibraryStore {
    private(set) var papers: [Paper] = []          // built-in + synced
    private(set) var bundledPapers: [Paper] = []
    let folder = PaperFolder()                     // the synced folder from the Mac
    @ObservationIgnored private var lastAutoSync = Date.distantPast
    private(set) var saved: Set<String>
    private(set) var read: Set<String>
    private(set) var progress: [String: Int]   // last reader page per paper
    private(set) var highlights: Set<String>    // "paperID|pageKey|sentenceIndex"
    private(set) var notes: [String: String]    // "paperID|pageKey" -> text

    private let source: PaperSource
    private let defaults: UserDefaults

    init(source: PaperSource = BundledPaperSource(), defaults: UserDefaults = .standard) {
        self.source = source
        self.defaults = defaults
        self.saved = Set(defaults.stringArray(forKey: "saved") ?? [])
        self.read = Set(defaults.stringArray(forKey: "read") ?? [])
        self.progress = (defaults.dictionary(forKey: "progress") as? [String: Int]) ?? [:]
        self.highlights = Set(defaults.stringArray(forKey: "highlights") ?? [])
        self.notes = (defaults.dictionary(forKey: "notes") as? [String: String]) ?? [:]
    }

    /// Built-in papers and the offline cache first, then the folder in the background.
    func load() async {
        bundledPapers = (try? await source.loadPapers()) ?? []
        rebuild()
        await syncFolder(force: true)
    }

    /// Pulls new papers from the synced folder. Automatic calls are throttled.
    func syncFolder(force: Bool = false) async {
        guard folder.isConfigured else { return }
        if !force, Date.now.timeIntervalSince(lastAutoSync) < 20 { return }
        lastAutoSync = .now
        if await folder.sync() { rebuild() }
    }

    /// Forgets the folder and the papers that came from it.
    func disconnectFolder() {
        folder.disconnect()
        PaperCache.prune(keeping: [])
        AudioCache.prune(keeping: [])
        rebuild()
    }

    /// Built-in papers keep their order; a synced paper with the same id replaces the built-in one.
    private func rebuild() {
        let custom = PaperCache.loadAll()
        let customByID = Dictionary(custom.map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
        let bundledIDs = Set(bundledPapers.map(\.id))
        papers = bundledPapers.map { customByID[$0.id] ?? $0 } + custom.filter { !bundledIDs.contains($0.id) }
        Glossary.extra = papers.flatMap { $0.glossary ?? [] }
    }

    /// One paper per calendar day, cycling through the library. Same paper all day.
    func paperOfTheDay(on date: Date = .now) -> Paper? {
        guard !papers.isEmpty else { return nil }
        let day = Calendar.current.ordinality(of: .day, in: .era, for: date) ?? 0
        return papers[day % papers.count]
    }

    func isSaved(_ paper: Paper) -> Bool { saved.contains(paper.id) }
    func isRead(_ paper: Paper) -> Bool { read.contains(paper.id) }

    func toggleSaved(_ paper: Paper) {
        if !saved.insert(paper.id).inserted { saved.remove(paper.id) }
        defaults.set(Array(saved), forKey: "saved")
    }

    func markRead(_ paper: Paper) {
        read.insert(paper.id)
        defaults.set(Array(read), forKey: "read")
    }

    func lastPage(_ paper: Paper) -> Int { progress[paper.id] ?? 0 }

    func setPage(_ page: Int, for paper: Paper) {
        progress[paper.id] = page
        defaults.set(progress, forKey: "progress")
    }

    /// Papers the user started but hasn't finished.
    var inProgress: [Paper] {
        papers.filter { (progress[$0.id] ?? 0) > 0 && !read.contains($0.id) }
    }

    // MARK: Highlights and notes

    func highlightKey(_ paper: Paper, _ page: ReaderPage, _ sentence: Int) -> String {
        "\(paper.id)|\(page.key)|\(sentence)"
    }

    func isHighlighted(_ paper: Paper, _ page: ReaderPage, _ sentence: Int) -> Bool {
        highlights.contains(highlightKey(paper, page, sentence))
    }

    func toggleHighlight(_ paper: Paper, _ page: ReaderPage, _ sentence: Int) {
        let key = highlightKey(paper, page, sentence)
        if !highlights.insert(key).inserted { highlights.remove(key) }
        defaults.set(Array(highlights), forKey: "highlights")
    }

    func highlightedSentences(_ paper: Paper, _ page: ReaderPage) -> Set<Int> {
        let prefix = "\(paper.id)|\(page.key)|"
        return Set(highlights.compactMap { $0.hasPrefix(prefix) ? Int($0.dropFirst(prefix.count)) : nil })
    }

    func note(_ paper: Paper, _ page: ReaderPage) -> String { notes["\(paper.id)|\(page.key)"] ?? "" }

    func setNote(_ text: String, _ paper: Paper, _ page: ReaderPage) {
        let key = "\(paper.id)|\(page.key)"
        if text.isEmpty { notes.removeValue(forKey: key) } else { notes[key] = text }
        defaults.set(notes, forKey: "notes")
    }

    // MARK: Prerequisite graph

    func prerequisites(of paper: Paper) -> [Paper] { paper.prerequisites.compactMap { id in papers.first { $0.id == id } } }
    func followUps(of paper: Paper) -> [Paper] { papers.filter { $0.prerequisites.contains(paper.id) } }

    /// Depth in the prerequisite DAG: 0 for papers without prerequisites.
    func level(of paper: Paper) -> Int {
        let pre = prerequisites(of: paper)
        return pre.isEmpty ? 0 : 1 + (pre.map { level(of: $0) }.max() ?? 0)
    }
}
