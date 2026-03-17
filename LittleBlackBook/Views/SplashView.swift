import SwiftUI

struct SplashView: View {
    @State private var bookScale:     CGFloat = 0.6
    @State private var bookOpacity:   Double  = 0
    @State private var spineGlow:     Double  = 0
    @State private var titleOpacity:  Double  = 0
    @State private var titleOffset:   CGFloat = 18
    @State private var tagOpacity:    Double  = 0

    var body: some View {
        ZStack {
            // Background — matches UILaunchScreen colour
            Color(red: 0.039, green: 0.039, blue: 0.047)
                .ignoresSafeArea()

            // Warm centre glow
            RadialGradient(
                colors: [
                    Color(red: 0.82, green: 0.58, blue: 0.18).opacity(0.25),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 220
            )
            .frame(width: 440, height: 440)
            .opacity(spineGlow)

            VStack(spacing: 28) {
                // Book icon
                BookIconView()
                    .frame(width: 130, height: 100)
                    .scaleEffect(bookScale)
                    .opacity(bookOpacity)

                // Title
                VStack(spacing: 6) {
                    Text("小黑书")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("阅读 · 音乐 · 收藏")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundStyle(Color(red: 0.82, green: 0.58, blue: 0.18))
                        .tracking(4)
                }
                .opacity(titleOpacity)
                .offset(y: titleOffset)
            }
        }
        .onAppear { animate() }
    }

    private func animate() {
        // Book scales in
        withAnimation(.spring(response: 0.7, dampingFraction: 0.65).delay(0.1)) {
            bookScale   = 1.0
            bookOpacity = 1.0
        }
        // Glow fades in
        withAnimation(.easeOut(duration: 0.9).delay(0.3)) {
            spineGlow = 1.0
        }
        // Title slides up and fades in
        withAnimation(.easeOut(duration: 0.5).delay(0.5)) {
            titleOpacity = 1.0
            titleOffset  = 0
        }
        // Tag line
        withAnimation(.easeOut(duration: 0.5).delay(0.75)) {
            tagOpacity = 1.0
        }
    }
}

// MARK: - Minimal drawn book

private struct BookIconView: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            let cx = w / 2
            let spine: CGFloat = 6

            // Left page
            var lp = Path()
            lp.move(to:    CGPoint(x: cx - spine/2, y: 2))
            lp.addLine(to: CGPoint(x: 4,            y: 14))
            lp.addLine(to: CGPoint(x: 4,            y: h - 14))
            lp.addLine(to: CGPoint(x: cx - spine/2, y: h - 2))
            lp.closeSubpath()
            ctx.fill(lp, with: .color(Color(red: 0.97, green: 0.95, blue: 0.89)))

            // Right page
            var rp = Path()
            rp.move(to:    CGPoint(x: cx + spine/2, y: 2))
            rp.addLine(to: CGPoint(x: w - 4,        y: 14))
            rp.addLine(to: CGPoint(x: w - 4,        y: h - 14))
            rp.addLine(to: CGPoint(x: cx + spine/2, y: h - 2))
            rp.closeSubpath()
            ctx.fill(rp, with: .color(Color(red: 0.93, green: 0.91, blue: 0.84)))

            // Page lines
            let lineColor = Color(red: 0.65, green: 0.62, blue: 0.55).opacity(0.55)
            for i in 1...5 {
                let y = 16 + CGFloat(i) * (h - 28) / 6
                // left
                ctx.stroke(Path { p in
                    p.move(to:    CGPoint(x: cx - spine/2 - 4, y: y))
                    p.addLine(to: CGPoint(x: 14,               y: y + CGFloat(i-3)*0.4))
                }, with: .color(lineColor), lineWidth: 1.2)
                // right
                ctx.stroke(Path { p in
                    p.move(to:    CGPoint(x: cx + spine/2 + 4, y: y))
                    p.addLine(to: CGPoint(x: w - 14,           y: y + CGFloat(i-3)*0.4))
                }, with: .color(lineColor), lineWidth: 1.2)
            }

            // Gold spine
            let gold = Gradient(colors: [
                Color(red: 0.72, green: 0.50, blue: 0.12),
                Color(red: 0.95, green: 0.78, blue: 0.35),
                Color(red: 0.72, green: 0.50, blue: 0.12)
            ])
            ctx.fill(Path(CGRect(x: cx - spine/2, y: 0, width: spine, height: h)),
                     with: .linearGradient(gold,
                                           startPoint: CGPoint(x: cx - spine/2, y: 0),
                                           endPoint:   CGPoint(x: cx + spine/2, y: 0)))

            // Blue bookmark ribbon (top-right)
            var bm = Path()
            let bmx: CGFloat = w - 18
            bm.move(to:    CGPoint(x: bmx,      y: 0))
            bm.addLine(to: CGPoint(x: bmx + 12, y: 0))
            bm.addLine(to: CGPoint(x: bmx + 12, y: 38))
            bm.addLine(to: CGPoint(x: bmx + 6,  y: 30))
            bm.addLine(to: CGPoint(x: bmx,      y: 38))
            bm.closeSubpath()
            ctx.fill(bm, with: .color(Color(red: 0.31, green: 0.44, blue: 0.86)))
        }
    }
}
