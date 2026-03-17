import SwiftUI

struct SplashView: View {
    @State private var glassScale:    CGFloat = 0.72
    @State private var glassOpacity:  Double  = 0
    @State private var bookOpacity:   Double  = 0
    @State private var titleOpacity:  Double  = 0
    @State private var titleOffset:   CGFloat = 22
    @State private var shimmerOffset: CGFloat = -300

    var body: some View {
        ZStack {
            // ── Mesh gradient background ──────────────────────────────────
            MeshLikeGradient()
                .ignoresSafeArea()

            // ── Liquid glass disc ─────────────────────────────────────────
            ZStack {
                // Frosted fill
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 280, height: 280)

                // Shimmer sweep
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.clear,
                                     .white.opacity(0.18),
                                     .clear],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing)
                    )
                    .frame(width: 280, height: 280)
                    .offset(x: shimmerOffset)
                    .blendMode(.plusLighter)
                    .clipShape(Circle())

                // Book icon
                BookSymbol()
                    .frame(width: 120, height: 90)
                    .opacity(bookOpacity)

                // Specular top highlight
                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .clear],
                            startPoint: .top,
                            endPoint: .center)
                    )
                    .frame(width: 220, height: 90)
                    .offset(y: -88)
                    .blendMode(.plusLighter)
            }
            // Border ring
            .overlay(
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.55),
                                     .white.opacity(0.15),
                                     .white.opacity(0.40)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing),
                        lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.35), radius: 40, y: 20)
            .scaleEffect(glassScale)
            .opacity(glassOpacity)
            .offset(y: -24)

            // ── Title block ───────────────────────────────────────────────
            VStack(spacing: 6) {
                Spacer()
                Spacer()
                Text("小黑书")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("阅读 · 音乐 · 收藏")
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.65))
                    .tracking(4)
                Spacer()
                    .frame(height: 60)
            }
            .opacity(titleOpacity)
            .offset(y: titleOffset)
        }
        .onAppear { animate() }
    }

    private func animate() {
        // Glass disc springs in
        withAnimation(.spring(response: 0.65, dampingFraction: 0.68)) {
            glassScale   = 1.0
            glassOpacity = 1.0
        }
        // Book fades in
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            bookOpacity = 1.0
        }
        // Shimmer sweep
        withAnimation(.easeInOut(duration: 1.1).delay(0.5)) {
            shimmerOffset = 320
        }
        // Title slides up
        withAnimation(.easeOut(duration: 0.45).delay(0.45)) {
            titleOpacity = 1.0
            titleOffset  = 0
        }
    }
}

// MARK: - Mesh-like gradient background

private struct MeshLikeGradient: View {
    var body: some View {
        ZStack {
            // Base layer
            LinearGradient(
                colors: [
                    Color(red: 0.345, green: 0.110, blue: 0.529),   // deep purple
                    Color(red: 0.114, green: 0.306, blue: 0.847),   // vivid blue
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing)

            // Colour blobs (simulate mesh)
            Circle()
                .fill(Color(red: 0.427, green: 0.157, blue: 0.929).opacity(0.7))
                .frame(width: 360)
                .blur(radius: 90)
                .offset(x: -80, y: -160)

            Circle()
                .fill(Color(red: 0.031, green: 0.714, blue: 0.831).opacity(0.55))
                .frame(width: 300)
                .blur(radius: 100)
                .offset(x: 120, y: 200)

            Circle()
                .fill(Color(red: 0.388, green: 0.400, blue: 0.945).opacity(0.5))
                .frame(width: 260)
                .blur(radius: 80)
                .offset(x: 80, y: -80)
        }
    }
}

// MARK: - Book symbol (flat, SF-Symbol style)

private struct BookSymbol: View {
    var body: some View {
        Canvas { ctx, size in
            let w   = size.width
            let h   = size.height
            let cx  = w / 2
            let gap: CGFloat = 5     // spine half-gap
            let sw: CGFloat  = 3.5  // stroke width
            let white = GraphicsContext.Shading.color(.white)

            // Left page
            var lp = Path()
            lp.move(to:    .init(x: cx - gap,  y: 0))
            lp.addLine(to: .init(x: 2,          y: 10))
            lp.addLine(to: .init(x: 2,          y: h - 8))
            lp.addLine(to: .init(x: cx - gap,   y: h))
            ctx.fill(lp, with: .color(.white.opacity(0.22)))
            ctx.stroke(lp, with: white, lineWidth: sw)

            // Right page
            var rp = Path()
            rp.move(to:    .init(x: cx + gap,  y: 0))
            rp.addLine(to: .init(x: w - 2,      y: 10))
            rp.addLine(to: .init(x: w - 2,      y: h - 8))
            rp.addLine(to: .init(x: cx + gap,   y: h))
            ctx.fill(rp, with: .color(.white.opacity(0.22)))
            ctx.stroke(rp, with: white, lineWidth: sw)

            // Spine
            ctx.stroke(Path { p in
                p.move(to:    .init(x: cx, y: 0))
                p.addLine(to: .init(x: cx, y: h))
            }, with: white, lineWidth: sw)

            // Binding arc at top
            ctx.stroke(Path { p in
                p.addArc(center: .init(x: cx, y: 0),
                         radius: w * 0.42,
                         startAngle: .degrees(195),
                         endAngle:   .degrees(345),
                         clockwise:  false)
            }, with: white, lineWidth: sw)

            // 3 text lines per page
            let lineAlpha: CGFloat = 0.6
            for i in 1...3 {
                let y = 22 + CGFloat(i) * (h - 34) / 4
                // left
                ctx.stroke(Path { p in
                    p.move(to:    .init(x: cx - gap - 6, y: y))
                    p.addLine(to: .init(x: i == 3 ? cx - gap - 6 - (cx - 16) * 0.55
                                                  : 10,          y: y))
                }, with: .color(.white.opacity(lineAlpha)), lineWidth: 2)
                // right
                ctx.stroke(Path { p in
                    p.move(to:    .init(x: cx + gap + 6, y: y))
                    p.addLine(to: .init(x: i == 3 ? cx + gap + 6 + (w - cx - 16) * 0.55
                                                  : w - 10,      y: y))
                }, with: .color(.white.opacity(lineAlpha)), lineWidth: 2)
            }
        }
    }
}
