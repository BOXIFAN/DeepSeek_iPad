import SwiftUI

/// 启动过渡：鲸鱼从左侧游入，名字淡入，三个呼吸点表示还在加载。
///
/// 只负责「显示与入场」，什么时候退场由 `RootView` 决定（最短展示时间到且
/// bootstrap 已跑完）。`DS_SPLASH_ALWAYS=1` 时保持不退，供截图用。
struct SplashView: View {

    @Environment(\.colorScheme) private var scheme
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var whaleIn = false
    @State private var titleIn = false
    @State private var dotsIn = false
    @State private var pulsing = false
    @State private var floating = false

    private var ink: Color {
        scheme == .dark
            ? Color(red: 0.957, green: 0.937, blue: 0.894)
            : Color(red: 0.086, green: 0.137, blue: 0.247)
    }

    private var whaleWidth: CGFloat { sizeClass == .regular ? 260 : 176 }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 20) {
                Image("SplashWhale")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(ink)
                    .frame(width: whaleWidth)
                    .scaleEffect(whaleIn ? 1 : 0.92)
                    .offset(x: whaleIn ? 0 : -whaleWidth, y: floating ? -4 : 0)
                    .opacity(whaleIn ? 1 : 0)

                VStack(spacing: 12) {
                    Text("鲸语")
                        .font(.system(size: 22, weight: .semibold))
                        .tracking(3.5)
                        .foregroundStyle(ink)
                        .padding(.leading, 3.5)
                        .opacity(titleIn ? 1 : 0)
                        .offset(y: titleIn ? 0 : 8)

                    loadingDots
                        .opacity(dotsIn ? 1 : 0)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("鲸语")
        .task {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                whaleIn = true
            }
            try? await Task.sleep(for: .milliseconds(300))
            withAnimation(.easeOut(duration: 0.35)) {
                titleIn = true
            }
            withAnimation(.easeOut(duration: 0.4)) {
                dotsIn = true
            }
            pulsing = true
            try? await Task.sleep(for: .milliseconds(320))
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
                floating = true
            }
        }
    }

    private var background: some View {
        ZStack {
            Color(uiColor: .systemBackground)

            RadialGradient(
                colors: [Theme.accent.opacity(scheme == .dark ? 0.18 : 0.085), .clear],
                center: .center,
                startRadius: 8,
                endRadius: 240
            )
        }
        .ignoresSafeArea()
    }

    private var loadingDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { index in
                Circle()
                    .fill(Theme.accent.opacity(0.5))
                    .frame(width: 4.5, height: 4.5)
                    .opacity(dotsIn ? 1 : 0)
                    .scaleEffect(dotsIn ? (pulsing ? 1.15 : 0.8) : 0.6)
                    .animation(
                        .easeInOut(duration: 0.62)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.16),
                        value: pulsing
                    )
            }
        }
        .frame(height: 6)
    }
}
