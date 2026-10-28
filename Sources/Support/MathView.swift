import SwiftUI
import SwiftMath

/// Renders one line of LaTeX with SwiftMath, as an image so SwiftUI can size it reliably.
struct MathView: View {
    let latex: String
    var fontSize: CGFloat = 20
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        var renderer = MathImage(latex: latex, fontSize: fontSize,
                                 textColor: scheme == .dark ? Theme.creamUI : Theme.inkUI,
                                 labelMode: .text, textAlignment: .left)
        let (error, image, _) = renderer.asImage()
        if let image, error == nil {
            Image(uiImage: image)
        } else {
            Text(latex).font(.system(size: 14, design: .monospaced)).foregroundStyle(Theme.muted)
        }
    }
}

/// A card with one or more formulas; lines are separated by "||".
struct FormulaBlock: View {
    let formula: String
    var fontSize: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(formula.components(separatedBy: "||"), id: \.self) { line in
                ScrollView(.horizontal, showsIndicators: false) {
                    MathView(latex: line, fontSize: fontSize)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
