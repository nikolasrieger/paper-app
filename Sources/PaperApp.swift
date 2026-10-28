import SwiftUI
import SwiftMath

@main
struct PaperDailyApp: App {
    @State private var store = LibraryStore()
    @State private var reminders = Reminders()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Navigation and tab bars use the theme colours instead of system black/grey.
        func serif(_ size: CGFloat) -> UIFont {
            let base = UIFont.systemFont(ofSize: size, weight: .bold)
            return base.fontDescriptor.withDesign(.serif).map { UIFont(descriptor: $0, size: size) } ?? base
        }
        let text = UIColor(Theme.text)
        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.largeTitleTextAttributes = [.foregroundColor: text, .font: serif(34)]
        nav.titleTextAttributes = [.foregroundColor: text, .font: serif(17)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav

        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        let muted = UIColor(Theme.muted)
        for item in [tab.stackedLayoutAppearance, tab.inlineLayoutAppearance, tab.compactInlineLayoutAppearance] {
            item.normal.iconColor = muted
            item.normal.titleTextAttributes = [.foregroundColor: muted]
        }
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab
        UITabBar.appearance().unselectedItemTintColor = muted
    }

    var body: some Scene {
        WindowGroup {
            RootView().tint(Theme.accent).foregroundStyle(Theme.text).scrollIndicators(.hidden)
                .environment(store)
                .environment(reminders)
                .task {
                    await store.load()
                    await reminders.reschedule(using: store)
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await store.syncFolder() }
                        Task { await reminders.reschedule(using: store) }
                    }
                }
        }
    }
}

struct RootView: View {
    @Environment(LibraryStore.self) private var store
    @State private var tab = 0
    @State private var debugReader: Paper?
    @State private var debugDetail: Paper?
    @State private var debugScreen: String?

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { TodayView() }
                .tabItem { Label("Home", systemImage: "house.fill") }.tag(0)
            NavigationStack { LibraryView() }
                .tabItem { Label("Explore", systemImage: "magnifyingglass") }.tag(1)
            NavigationStack { NotebookView() }
                .tabItem { Label("Notebook", systemImage: "highlighter") }.tag(2)
        }
        .task(id: store.papers.count) {
            #if DEBUG
            // Launch arguments for screenshots: -debugTab N, -debugPaper <id> [-debugReader] [-debugPage N] [-debugSeed]
            let args = ProcessInfo.processInfo.arguments
            func value(_ flag: String) -> String? {
                guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
                return args[i + 1]
            }
            if args.contains("-debugFormulas") {
                let all = store.papers.flatMap { $0.insights.compactMap(\.formula) } + Glossary.entries.compactMap(\.formula)
                var report = ""
                for f in all.flatMap({ $0.components(separatedBy: "||") }) {
                    var r = MathImage(latex: f, fontSize: 20, textColor: .black, labelMode: .text, textAlignment: .left)
                    if r.asImage().0 != nil { report += "FAILED: \(f)\n" }
                }
                try? (report + "DONE\n").write(toFile: "/tmp/formula_check.txt", atomically: true, encoding: .utf8)
            }
            if let dir = value("-debugDumpJSON") {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
                try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
                for paper in store.bundledPapers {
                    try? encoder.encode(paper).write(to: URL(fileURLWithPath: dir).appendingPathComponent("\(paper.id).json"))
                }
            }
            if let screen = value("-debugScreen") { debugScreen = screen }
            if args.contains("-debugSeed"), let p = store.papers.first {
                if !store.isHighlighted(p, .insight(0), 0) { store.toggleHighlight(p, .insight(0), 0) }
                store.setNote("Check how this compares to the decoder-only setup.", p, .insight(0))
            }
            if let t = value("-debugTab").flatMap(Int.init) { tab = t }
            if let id = value("-debugPaper"), let paper = store.papers.first(where: { $0.id == id }) {
                if let page = value("-debugPage").flatMap(Int.init) { store.setPage(page, for: paper) }
                if args.contains("-debugReader") { debugReader = paper } else { debugDetail = paper }
            }
            #endif
        }
        .sheet(item: $debugDetail) { p in NavigationStack { PaperDetailView(paper: p) } }
        .fullScreenCover(item: $debugScreen) { screen in
            NavigationStack {
                switch screen {
                case "glossary": GlossaryView()
                default: SettingsView()
                }
            }
        }
        .fullScreenCover(item: $debugReader) { p in ReaderView(paper: p) }
    }
}

#if DEBUG
extension String: @retroactive Identifiable { public var id: String { self } }
#endif
