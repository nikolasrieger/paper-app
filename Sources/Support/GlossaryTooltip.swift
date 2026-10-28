import SwiftUI

private struct PresentGlossaryKey: EnvironmentKey {
    static let defaultValue: ((GlossaryEntry) -> Void)? = nil
}

extension EnvironmentValues {
    /// Set by `glossaryTooltip`; text views call it when a glossary term is tapped.
    var presentGlossary: ((GlossaryEntry) -> Void)? {
        get { self[PresentGlossaryKey.self] }
        set { self[PresentGlossaryKey.self] = newValue }
    }
}

/// Floating definition card, like a tooltip: the text underneath stays visible and scrollable.
struct GlossaryCard: View {
    let entry: GlossaryEntry
    let close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(entry.term).font(Theme.serif(20))
                Spacer()
                Button(action: close) { Image(systemName: "xmark.circle.fill").font(.title3).foregroundStyle(Theme.muted) }
                    .accessibilityLabel("Close definition")
            }
            Text(entry.definition).font(.system(size: 15, design: .serif)).lineSpacing(3)
            if let f = entry.formula { FormulaBlock(formula: f, fontSize: 16) }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.accent.opacity(0.3)))
        .shadow(color: .black.opacity(0.18), radius: 16, y: 6)
    }
}

private struct GlossaryTooltipModifier: ViewModifier {
    let bottomInset: CGFloat
    let resetOn: AnyHashable
    @State private var entry: GlossaryEntry?

    func body(content: Content) -> some View {
        content
            .environment(\.presentGlossary, { e in withAnimation(.spring(duration: 0.3)) { entry = e } })
            .overlay(alignment: .bottom) {
                if let entry {
                    GlossaryCard(entry: entry) { withAnimation { self.entry = nil } }
                        .padding(.horizontal, 16).padding(.bottom, bottomInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .id(entry.id)
                }
            }
            .onChange(of: resetOn) { _, _ in entry = nil }
            #if DEBUG
            .task {
                let args = ProcessInfo.processInfo.arguments
                try? await Task.sleep(for: .seconds(1))
                if let i = args.firstIndex(of: "-debugTerm"), i + 1 < args.count { entry = Glossary.entry(id: args[i + 1]) }
            }
            #endif
    }
}

/// Routes taps on glossary links to the surrounding tooltip.
private struct GlossaryLinkModifier: ViewModifier {
    @Environment(\.presentGlossary) private var present
    func body(content: Content) -> some View {
        content.environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "gloss", let entry = Glossary.entry(id: url.host ?? "") else { return .systemAction }
            present?(entry)
            return .handled
        })
    }
}

extension View {
    /// Shows glossary definitions as a floating card above this view's content.
    func glossaryTooltip(bottomInset: CGFloat = 16, resetOn: AnyHashable = 0) -> some View {
        modifier(GlossaryTooltipModifier(bottomInset: bottomInset, resetOn: resetOn))
    }
    func glossaryLinks() -> some View { modifier(GlossaryLinkModifier()) }
}
