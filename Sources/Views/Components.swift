import SwiftUI

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat { Swift.min(Swift.max(self, range.lowerBound), range.upperBound) }
}

/// Deterministic random numbers, so a paper's cover pattern is the same on every launch.
private struct SeededRandom {
    private var state: UInt64
    init(seed: String) {
        state = seed.utf8.reduce(14695981039346656037) { ($0 ^ UInt64($1)) &* 1099511628211 }
    }
    mutating func next() -> CGFloat {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return CGFloat((z ^ (z >> 31)) % 10_000) / 10_000
    }
}

/// Generated book-style cover in a flat, printed style: a bold geometric composition on top,
/// the title on solid colour below, and a faint paper grain.
struct CoverView: View {
    let paper: Paper
    var width: CGFloat = 120

    private var palette: CoverPalette { paper.topic.palette }
    private var artHeight: CGFloat { width * 0.62 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            palette.bg
            VStack(alignment: .leading, spacing: 0) {
                art.frame(width: width, height: artHeight).clipped()
                VStack(alignment: .leading, spacing: width * 0.04) {
                    Rectangle().fill(palette.ink.opacity(0.6)).frame(width: width * 0.12, height: max(1, width * 0.012))
                    Text(paper.shortTitle)
                        .font(Theme.serif(width * 0.15))
                        .foregroundStyle(palette.ink)
                        .lineLimit(3)
                        .minimumScaleFactor(0.5)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                    Text(String(paper.year))
                        .font(.system(size: width * 0.08, weight: .semibold)).tracking(1.5)
                        .foregroundStyle(palette.ink.opacity(0.7))
                }
                .padding(.horizontal, width * 0.1).padding(.top, width * 0.09).padding(.bottom, width * 0.08)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            grain
            // binding edge
            HStack(spacing: 0) {
                Rectangle().fill(.black.opacity(0.18)).frame(width: width * 0.035)
                Rectangle().fill(.white.opacity(0.14)).frame(width: 1)
            }
        }
        .frame(width: width, height: width * 1.4)
        .clipShape(RoundedRectangle(cornerRadius: width * 0.04))
        .overlay(RoundedRectangle(cornerRadius: width * 0.04).strokeBorder(.white.opacity(0.1), lineWidth: 1))
        .shadow(color: .black.opacity(0.22), radius: width * 0.05, x: 0, y: width * 0.03)
    }

    /// Faint speckle, like paper stock.
    private var grain: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: paper.id + "grain")
            for _ in 0..<Int(size.width * 3) {
                let p = CGPoint(x: rng.next() * size.width, y: rng.next() * size.height)
                let light = rng.next() > 0.5
                ctx.fill(Path(CGRect(origin: p, size: CGSize(width: 1, height: 1))),
                         with: .color((light ? Color.white : Color.black).opacity(0.07)))
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private var art: some View {
        Canvas { ctx, size in
            var rng = SeededRandom(seed: paper.id)
            let cell = size.width / 4
            switch paper.topic {
            case .architectures: blocks(&ctx, &rng, cell: cell)
            case .language: truchet(&ctx, &rng, cell: cell)
            case .reasoning: bubbles(&ctx, &rng, size: size)
            case .alignment: sunrise(&ctx, &rng, size: size)
            case .vision: mosaic(&ctx, &rng, size: size)
            case .learning: steps(&ctx, &rng, size: size)
            case .other: rings(&ctx, &rng, size: size)
            }
        }
    }

    private func pick(_ rng: inout SeededRandom) -> Color { [palette.a, palette.b, palette.c][min(2, Int(rng.next() * 3))] }

    /// Bauhaus-style grid of blocks, circles and quarter-circles.
    private func blocks(_ ctx: inout GraphicsContext, _ rng: inout SeededRandom, cell: CGFloat) {
        for row in 0..<3 {
            for col in 0..<4 {
                let r = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell)
                let inner = r.insetBy(dx: cell * 0.09, dy: cell * 0.09)
                switch Int(rng.next() * 5) {
                case 0: ctx.fill(Path(inner), with: .color(pick(&rng)))
                case 1: ctx.fill(Path(ellipseIn: inner), with: .color(pick(&rng)))
                case 2: ctx.fill(Path(roundedRect: inner, cornerRadii: .init(topLeading: inner.width, bottomTrailing: 0)), with: .color(pick(&rng)))
                case 3: ctx.stroke(Path(inner), with: .color(palette.a.opacity(0.5)), lineWidth: max(1, cell * 0.03))
                default: break
                }
            }
        }
    }

    /// Quarter-circle tiling that reads like flowing type.
    private func truchet(_ ctx: inout GraphicsContext, _ rng: inout SeededRandom, cell: CGFloat) {
        for row in 0..<3 {
            for col in 0..<4 {
                let x = CGFloat(col) * cell, y = CGFloat(row) * cell
                let flip = rng.next() > 0.5
                let colors = [pick(&rng), pick(&rng)]
                let corners: [(CGPoint, Double)] = flip
                    ? [(CGPoint(x: x, y: y), 0), (CGPoint(x: x + cell, y: y + cell), 180)]
                    : [(CGPoint(x: x + cell, y: y), 90), (CGPoint(x: x, y: y + cell), 270)]
                for (i, (c, start)) in corners.enumerated() {
                    var path = Path()
                    path.move(to: c)
                    path.addArc(center: c, radius: cell * 0.5, startAngle: .degrees(start), endAngle: .degrees(start + 90), clockwise: false)
                    path.closeSubpath()
                    ctx.fill(path, with: .color(colors[i]))
                }
            }
        }
    }

    /// Overlapping discs joined by a chain of thought.
    private func bubbles(_ ctx: inout GraphicsContext, _ rng: inout SeededRandom, size: CGSize) {
        let discs: [(Color, CGFloat)] = [(palette.a, 0.34), (palette.c, 0.24), (palette.b, 0.16)]
        var centers: [CGPoint] = []
        for (i, (color, radius)) in discs.enumerated() {
            let r = size.width * radius
            let c = CGPoint(x: size.width * (0.22 + 0.28 * CGFloat(i) + 0.1 * rng.next()), y: size.height * (0.3 + 0.4 * rng.next()))
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(color))
            centers.append(c)
        }
        var chain = Path()
        chain.move(to: centers[0])
        for c in centers.dropFirst() { chain.addLine(to: c) }
        ctx.stroke(chain, with: .color(palette.bg), lineWidth: max(1.5, size.width * 0.02))
        for c in centers {
            let r = size.width * 0.03
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .color(palette.bg))
        }
    }

    /// Pixel mosaic, like a coarse image.
    private func mosaic(_ ctx: inout GraphicsContext, _ rng: inout SeededRandom, size: CGSize) {
        let cell = size.width / 8
        let rows = Int(ceil(size.height / cell))
        for row in 0..<rows {
            for col in 0..<8 {
                let roll = rng.next()
                guard roll > 0.18 else { continue }
                let rect = CGRect(x: CGFloat(col) * cell, y: CGFloat(row) * cell, width: cell, height: cell).insetBy(dx: 0.5, dy: 0.5)
                ctx.fill(Path(rect), with: .color(pick(&rng).opacity(0.35 + 0.65 * Double(rng.next()))))
            }
        }
    }

    /// Rising steps with a trend line, like a learning curve.
    private func steps(_ ctx: inout GraphicsContext, _ rng: inout SeededRandom, size: CGSize) {
        let count = 6
        let barWidth = size.width / CGFloat(count)
        var tops: [CGPoint] = []
        for i in 0..<count {
            let height = size.height * (0.22 + 0.7 * CGFloat(i) / CGFloat(count - 1) * (0.85 + 0.3 * rng.next())).clamped(to: 0.2...0.98)
            let rect = CGRect(x: CGFloat(i) * barWidth, y: size.height - height, width: barWidth - 2, height: height)
            ctx.fill(Path(rect), with: .color(pick(&rng)))
            tops.append(CGPoint(x: rect.midX, y: rect.minY - size.width * 0.03))
        }
        var line = Path()
        line.move(to: tops[0])
        for p in tops.dropFirst() { line.addLine(to: p) }
        ctx.stroke(line, with: .color(palette.bg), style: StrokeStyle(lineWidth: max(1.5, size.width * 0.02), lineCap: .round, lineJoin: .round))
        for p in tops {
            let r = size.width * 0.028
            ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2)), with: .color(palette.bg))
        }
    }

    /// Nested rings.
    private func rings(_ ctx: inout GraphicsContext, _ rng: inout SeededRandom, size: CGSize) {
        let center = CGPoint(x: size.width * (0.3 + 0.4 * rng.next()), y: size.height * 0.5)
        let colors = [palette.b, palette.a, palette.c, palette.b, palette.a]
        for (i, color) in colors.enumerated() {
            let r = size.width * (0.5 - 0.085 * CGFloat(i))
            ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)), with: .color(color))
        }
    }

    /// Concentric half-discs, like a rising sun.
    private func sunrise(_ ctx: inout GraphicsContext, _ rng: inout SeededRandom, size: CGSize) {
        let center = CGPoint(x: size.width * (0.4 + 0.2 * rng.next()), y: size.height)
        let layers = [palette.b, palette.c, palette.a, palette.b, palette.c]
        for (i, color) in layers.enumerated() {
            let r = size.width * (0.62 - 0.11 * CGFloat(i))
            var path = Path()
            path.addArc(center: center, radius: r, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            path.closeSubpath()
            ctx.fill(path, with: .color(color))
        }
    }
}

/// Small cover + title, used in horizontal shelves and the library grid.
struct PaperTile: View {
    @Environment(LibraryStore.self) private var store
    let paper: Paper
    var width: CGFloat = 120

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverView(paper: paper, width: width)
            Text(paper.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                .multilineTextAlignment(.leading).foregroundStyle(Theme.text)
            HStack(spacing: 4) {
                Text("\(paper.readMinutes) min")
                if store.isRead(paper) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                if store.isSaved(paper) { Image(systemName: "bookmark.fill").foregroundStyle(Theme.accent) }
            }
            .font(.caption).foregroundStyle(Theme.muted)
        }
        .frame(width: width, alignment: .leading)
    }
}

struct TopicChip: View {
    let topic: Topic
    var body: some View {
        Label(topic.rawValue, systemImage: topic.icon)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(topic.color.opacity(0.15), in: Capsule())
            .foregroundStyle(topic.color)
    }
}

struct PrimaryButton: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 16)
            .background(Theme.accentFill, in: Capsule())
            .foregroundStyle(Theme.onAccent)
    }
}
