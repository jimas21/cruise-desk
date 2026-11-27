import SwiftUI
import UIKit

// Decorative artwork, all vector (Canvas and paths, no bitmaps). Every piece is hidden from VoiceOver, frames the
// content without adding words, and stands still under Reduce Motion.

extension Color {
    /// 0xRRGGBB.
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - Motion

/// A slow clock for the artwork, in seconds. It stands still (at 0) under Reduce Motion, and ticks at most
/// 30 times a second otherwise.
struct Drift<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewBuilder let content: (Double) -> Content

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            content(reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600))
        }
    }
}

/// Springs for answers and swipes; a plain fade when Reduce Motion is on.
enum Motion {
    static var spring: Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.2) : .spring(response: 0.42, dampingFraction: 0.82)
    }

    static var snappy: Animation {
        UIAccessibility.isReduceMotionEnabled ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.86)
    }
}

// MARK: - Waves

/// One sine swell: `y(x)` at a time, as a filled shape down to the bottom or as its crest line.
struct Swell {
    var baseline: CGFloat
    var amplitude: CGFloat
    var wavelength: CGFloat
    /// Radians per second; the sign sets the direction of drift.
    var speed: Double
    var offset: Double = 0

    func y(_ x: CGFloat, _ time: Double) -> CGFloat {
        let angle = Double(x / max(wavelength, 1)) * 2 * .pi + time * speed + offset
        return baseline + amplitude * CGFloat(sin(angle))
    }

    func crest(width: CGFloat, time: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: y(0, time)))
        var x: CGFloat = 0
        while x < width {
            x = min(width, x + 3)
            path.addLine(to: CGPoint(x: x, y: y(x, time)))
        }
        return path
    }

    func body(width: CGFloat, bottom: CGFloat, time: Double) -> Path {
        var path = crest(width: width, time: time)
        path.addLine(to: CGPoint(x: width, y: bottom))
        path.addLine(to: CGPoint(x: 0, y: bottom))
        path.closeSubpath()
        return path
    }
}

private func disc(_ center: CGPoint, _ radius: CGFloat) -> Path {
    Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
}

/// A cruise ship in silhouette, bow to the right, centred on its waterline at the origin. Not any real ship.
private func shipPath(width w: CGFloat) -> Path {
    var path = Path()
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: (x - 0.5) * w, y: y * w) }
    path.move(to: p(0, -0.115))
    path.addLine(to: p(0.86, -0.125))
    path.addLine(to: p(1.0, -0.15))
    path.addLine(to: p(0.9, 0.012))
    path.addLine(to: p(0.05, 0.012))
    path.closeSubpath()
    path.addRoundedRect(in: CGRect(origin: p(0.10, -0.205), size: CGSize(width: 0.70 * w, height: 0.11 * w)),
                        cornerSize: CGSize(width: 0.035 * w, height: 0.035 * w), style: .continuous)
    path.addRoundedRect(in: CGRect(origin: p(0.20, -0.285), size: CGSize(width: 0.48 * w, height: 0.1 * w)),
                        cornerSize: CGSize(width: 0.035 * w, height: 0.035 * w), style: .continuous)
    path.move(to: p(0.30, -0.27))
    path.addLine(to: p(0.42, -0.27))
    path.addLine(to: p(0.395, -0.385))
    path.addLine(to: p(0.29, -0.385))
    path.closeSubpath()
    return path
}

/// Fixed pseudo-random stars (same sky every time).
private struct Star {
    let x: Double, y: Double, r: Double, phase: Double

    static let sky: [Star] = {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        return (0..<36).map { _ in Star(x: next(), y: next(), r: 0.5 + next() * 0.9, phase: next() * 6.28) }
    }()
}

// MARK: - Deals header scene

/// Sky, sun, layered swells and a small ship riding them. Dark mode: night sky, moon and stars, lit portholes.
struct SeaScene: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Drift { time in
            Canvas { context, size in
                SeaPainter(night: scheme == .dark, time: time).paint(&context, size)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct SeaPainter {
    let night: Bool
    let time: Double

    func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let horizon = (h * 0.56).rounded()

        let skyColors: [Color] = night
            ? [Color(hex: 0x06142A), Color(hex: 0x0E2A48), Color(hex: 0x1D4A69)]
            : [Color(hex: 0x8DCAE0), Color(hex: 0xC9E8F0), Color(hex: 0xFBE3C3)]
        ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon + 1)),
                 with: .linearGradient(Gradient(colors: skyColors), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))

        let light = CGPoint(x: w * 0.78, y: horizon * (night ? 0.36 : 0.5))
        let radius = min(h * 0.1, 15)
        if night {
            stars(&ctx, w: w, horizon: horizon)
            ctx.fill(disc(light, radius * 3.4), with: .radialGradient(
                Gradient(colors: [Color.white.opacity(0.2), Color.white.opacity(0)]),
                center: light, startRadius: radius * 0.8, endRadius: radius * 3.4))
            var moon = ctx
            moon.clip(to: disc(CGPoint(x: light.x + radius * 0.5, y: light.y - radius * 0.3), radius * 0.9),
                      options: .inverse)
            moon.fill(disc(light, radius), with: .color(Color(hex: 0xF5EFD6)))
        } else {
            ctx.fill(disc(light, radius * 3.6), with: .radialGradient(
                Gradient(colors: [Color(hex: 0xFFE3A0, opacity: 0.75), Color(hex: 0xFFE3A0, opacity: 0)]),
                center: light, startRadius: radius * 0.6, endRadius: radius * 3.6))
            ctx.fill(disc(light, radius), with: .color(Color(hex: 0xFFF3CF)))
            clouds(&ctx, w: w, horizon: horizon)
        }

        let water: [Color] = night ? [Color(hex: 0x184B69), Color(hex: 0x0C2D45)] : [Color(hex: 0x93D1E1), Color(hex: 0x4FA8C3)]
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                 with: .linearGradient(Gradient(colors: water), startPoint: CGPoint(x: 0, y: horizon),
                                       endPoint: CGPoint(x: 0, y: h)))

        let back = Swell(baseline: horizon + 2, amplitude: 1.6, wavelength: w * 0.34, speed: 0.35, offset: 0.4)
        let mid = Swell(baseline: horizon + h * 0.16, amplitude: 3.6, wavelength: w * 0.55, speed: -0.42, offset: 1.3)
        let front = Swell(baseline: horizon + h * 0.31, amplitude: 4.6, wavelength: w * 0.8, speed: 0.55, offset: 2.6)

        ctx.fill(back.body(width: w, bottom: h, time: time), with: .color(night ? Color(hex: 0x1A4D6B) : Color(hex: 0x86C9DB)))
        glitter(&ctx, x: light.x, from: horizon + 4, to: mid.baseline - 4)

        ship(&ctx, x: w * 0.3, on: mid, width: min(max(w * 0.17, 54), 78))

        ctx.fill(mid.body(width: w, bottom: h, time: time), with: .color(night ? Color(hex: 0x113A55) : Color(hex: 0x3E9EBB)))
        ctx.stroke(mid.crest(width: w, time: time), with: .color(Color.white.opacity(night ? 0.14 : 0.35)), lineWidth: 1.2)
        ctx.fill(front.body(width: w, bottom: h, time: time), with: .linearGradient(
            Gradient(colors: night ? [Color(hex: 0x0B2C43), Color(hex: 0x071E30)] : [Color(hex: 0x12809E), Color(hex: 0x0B6E8A)]),
            startPoint: CGPoint(x: 0, y: front.baseline), endPoint: CGPoint(x: 0, y: h)))
        ctx.stroke(front.crest(width: w, time: time), with: .color(Color.white.opacity(night ? 0.12 : 0.3)), lineWidth: 1.2)
    }

    private func stars(_ ctx: inout GraphicsContext, w: CGFloat, horizon: CGFloat) {
        for star in Star.sky {
            let twinkle = 0.55 + 0.45 * sin(time * 0.9 + star.phase)
            let point = CGPoint(x: star.x * Double(w), y: star.y * Double(horizon - 10) + 4)
            ctx.fill(disc(point, CGFloat(star.r)), with: .color(Color.white.opacity(0.85 * twinkle)))
        }
    }

    private func clouds(_ ctx: inout GraphicsContext, w: CGFloat, horizon: CGFloat) {
        let span = Double(w) + 120
        for (i, cloud) in [(0.12, 0.34, 1.0), (0.55, 0.62, 0.75)].enumerated() {
            let x = CGFloat((cloud.0 * span + time * (3 + Double(i))).truncatingRemainder(dividingBy: span)) - 60
            let y = horizon * CGFloat(cloud.1)
            let k = CGFloat(cloud.2)
            var path = Path(roundedRect: CGRect(x: x, y: y, width: 54 * k, height: 11 * k), cornerRadius: 5.5 * k)
            path.addPath(disc(CGPoint(x: x + 18 * k, y: y + 2 * k), 9 * k))
            path.addPath(disc(CGPoint(x: x + 32 * k, y: y + 1 * k), 12 * k))
            ctx.fill(path, with: .color(Color.white.opacity(0.7)))
        }
    }

    /// Light on the water under the sun or moon.
    private func glitter(_ ctx: inout GraphicsContext, x: CGFloat, from top: CGFloat, to bottom: CGFloat) {
        guard bottom > top else { return }
        let color = night ? Color(hex: 0xF5EFD6) : Color.white
        var y = top
        var i = 0
        while y < bottom {
            let f = Double((y - top) / max(bottom - top, 1))
            let half = CGFloat(6 + 14 * f) * (i % 2 == 0 ? 1 : 0.6)
            let shift = CGFloat(sin(time * 0.8 + Double(i) * 1.9)) * 2.5
            ctx.fill(Path(roundedRect: CGRect(x: x - half + shift, y: y, width: half * 2, height: 1.6), cornerRadius: 0.8),
                     with: .color(color.opacity(0.65 - 0.3 * f)))
            y += 4 + CGFloat(3 * f)
            i += 1
        }
    }

    private func ship(_ ctx: inout GraphicsContext, x: CGFloat, on swell: Swell, width: CGFloat) {
        let y = swell.y(x, time) + width * 0.05
        let slope = (swell.y(x + 8, time) - swell.y(x - 8, time)) / 16
        var c = ctx
        c.translateBy(x: x, y: y)
        c.rotate(by: .radians(atan(Double(slope)) * 0.7))
        c.fill(shipPath(width: width), with: .color(night ? Color(hex: 0x04101C) : Color(hex: 0x173049)))
        if night {
            var windows = Path()
            for k in 0..<7 {
                let wx = (0.16 + 0.085 * CGFloat(k) - 0.5) * width
                windows.addEllipse(in: CGRect(x: wx, y: -0.165 * width, width: 1.8, height: 1.8))
            }
            for k in 0..<4 {
                let wx = (0.27 + 0.1 * CGFloat(k) - 0.5) * width
                windows.addEllipse(in: CGRect(x: wx, y: -0.25 * width, width: 1.8, height: 1.8))
            }
            c.fill(windows, with: .color(Color(hex: 0xFFD58A)))
        }
    }
}

// MARK: - Detail hero backdrop

/// The kind's deep gradient with a soft glow and slow swells along the bottom. Text on it is white.
struct HeroBackdrop: View {
    let kind: DealKind?

    var body: some View {
        let colors = Palette.hero(kind)
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Color.white.opacity(0.22), Color.white.opacity(0)],
                           center: UnitPoint(x: 0.88, y: 0.08), startRadius: 4, endRadius: 190)
            Drift { time in
                Canvas { context, size in
                    let w = size.width, h = size.height
                    let swells = [
                        (Swell(baseline: h * 0.70, amplitude: 4, wavelength: w * 0.6, speed: 0.4, offset: 0.5), 0.07),
                        (Swell(baseline: h * 0.80, amplitude: 5, wavelength: w * 0.75, speed: -0.5, offset: 2.1), 0.09),
                        (Swell(baseline: h * 0.90, amplitude: 5, wavelength: w * 0.9, speed: 0.6, offset: 3.7), 0.12),
                    ]
                    for (swell, opacity) in swells {
                        context.fill(swell.body(width: w, bottom: h, time: time), with: .color(Color.white.opacity(opacity)))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Empty states

/// A round window on a calm sea with a small sailboat bobbing: the empty-state picture.
struct CalmSeaArt: View {
    @Environment(\.colorScheme) private var scheme
    @ScaledMetric(relativeTo: .largeTitle) private var side: CGFloat = 128

    var body: some View {
        let night = scheme == .dark
        Drift { time in
            Canvas { context, size in
                CalmSeaPainter(night: night, time: time).paint(&context, size)
            }
        }
        .frame(width: side, height: side)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(
                LinearGradient(colors: night ? [Color(hex: 0x6E7F88), Color(hex: 0x2B3940)]
                                             : [Color.white, Color(hex: 0xB4C6CD)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: side * 0.07)
        }
        .shadow(color: Color.black.opacity(night ? 0.4 : 0.12), radius: 10, y: 5)
        .accessibilityHidden(true)
    }
}

private struct CalmSeaPainter {
    let night: Bool
    let time: Double

    func paint(_ ctx: inout GraphicsContext, _ size: CGSize) {
        let w = size.width, h = size.height
        let horizon = h * 0.58
        let sky: [Color] = night ? [Color(hex: 0x081A33), Color(hex: 0x1D4A69)] : [Color(hex: 0xA9DAEA), Color(hex: 0xFCE6C8)]
        ctx.fill(Path(CGRect(origin: .zero, size: size)),
                 with: .linearGradient(Gradient(colors: sky), startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
        let light = CGPoint(x: w * 0.7, y: h * 0.3)
        if night {
            for star in Star.sky.prefix(14) {
                let point = CGPoint(x: star.x * Double(w), y: star.y * Double(horizon - 8) + 6)
                ctx.fill(disc(point, CGFloat(star.r) * 0.8),
                         with: .color(Color.white.opacity(0.5 + 0.35 * sin(time * 0.9 + star.phase))))
            }
            var moon = ctx
            moon.clip(to: disc(CGPoint(x: light.x + 4, y: light.y - 3), w * 0.065), options: .inverse)
            moon.fill(disc(light, w * 0.07), with: .color(Color(hex: 0xF5EFD6)))
        } else {
            ctx.fill(disc(light, w * 0.2), with: .radialGradient(
                Gradient(colors: [Color(hex: 0xFFE3A0, opacity: 0.7), Color(hex: 0xFFE3A0, opacity: 0)]),
                center: light, startRadius: w * 0.04, endRadius: w * 0.2))
            ctx.fill(disc(light, w * 0.075), with: .color(Color(hex: 0xFFF3CF)))
        }
        let far = Swell(baseline: horizon, amplitude: 1.2, wavelength: w * 0.4, speed: 0.3, offset: 0)
        let near = Swell(baseline: horizon + h * 0.2, amplitude: 2.2, wavelength: w * 0.6, speed: -0.35, offset: 1.5)
        ctx.fill(far.body(width: w, bottom: h, time: time), with: .color(night ? Color(hex: 0x16425F) : Color(hex: 0x7EC4D8)))

        // The boat sits on the far swell and rocks gently.
        let bx = w * 0.42
        let by = far.y(bx, time) + h * 0.11
        var boat = ctx
        boat.translateBy(x: bx, y: by)
        boat.rotate(by: .degrees(sin(time * 0.9) * 3))
        let s = w * 0.0042
        var hull = Path()
        hull.move(to: CGPoint(x: -26 * s, y: -6 * s))
        hull.addLine(to: CGPoint(x: 26 * s, y: -6 * s))
        hull.addLine(to: CGPoint(x: 18 * s, y: 4 * s))
        hull.addLine(to: CGPoint(x: -18 * s, y: 4 * s))
        hull.closeSubpath()
        var mast = Path()
        mast.addRect(CGRect(x: -1 * s, y: -46 * s, width: 2 * s, height: 40 * s))
        var main = Path()
        main.move(to: CGPoint(x: 2 * s, y: -44 * s))
        main.addLine(to: CGPoint(x: 22 * s, y: -9 * s))
        main.addLine(to: CGPoint(x: 2 * s, y: -9 * s))
        main.closeSubpath()
        var jib = Path()
        jib.move(to: CGPoint(x: -3 * s, y: -38 * s))
        jib.addLine(to: CGPoint(x: -3 * s, y: -9 * s))
        jib.addLine(to: CGPoint(x: -20 * s, y: -9 * s))
        jib.closeSubpath()
        let sail = night ? Color(hex: 0xD8E4EA) : Color.white
        boat.fill(main, with: .color(sail))
        boat.fill(jib, with: .color(sail.opacity(0.88)))
        boat.fill(mast, with: .color(night ? Color(hex: 0x9FB2BC) : Color(hex: 0x3B5566)))
        boat.fill(hull, with: .color(night ? Color(hex: 0x0B2233) : Color(hex: 0x173049)))

        ctx.fill(near.body(width: w, bottom: h, time: time), with: .linearGradient(
            Gradient(colors: night ? [Color(hex: 0x0E3550), Color(hex: 0x082539)] : [Color(hex: 0x3E9EBB), Color(hex: 0x0B6E8A)]),
            startPoint: CGPoint(x: 0, y: near.baseline), endPoint: CGPoint(x: 0, y: h)))
        ctx.stroke(near.crest(width: w, time: time), with: .color(Color.white.opacity(night ? 0.14 : 0.32)), lineWidth: 1)
    }
}

/// An illustrated empty state: the calm-sea picture, a title and one plain sentence.
struct IllustratedEmpty: View {
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            CalmSeaArt()
                .padding(.bottom, 4)
            Text(title)
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Sea scene") {
    VStack(spacing: 16) {
        SeaScene().frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        SeaScene().frame(height: 140).clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .environment(\.colorScheme, .dark)
        HeroBackdrop(kind: .fits).frame(height: 200).clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        HStack {
            CalmSeaArt()
            CalmSeaArt().environment(\.colorScheme, .dark)
        }
    }
    .padding()
}
