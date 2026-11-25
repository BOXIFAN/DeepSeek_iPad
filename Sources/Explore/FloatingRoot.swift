import SwiftUI

// MARK: - 方向 B · 浮岛
//
// 极简对话。没有常驻侧栏，会话历史收进浮层；输入框是一块悬浮玻璃。
// 目标：打开就问，注意力只在答案上。

enum FloatingPalette {
    static let accent = Color(red: 0.302, green: 0.420, blue: 0.996)
    static let bg = Color(red: 0.973, green: 0.976, blue: 1.0)
    static let bubble = Color(red: 0.929, green: 0.937, blue: 0.969)
    static let ink = Color(red: 0.09, green: 0.09, blue: 0.11)
    static let faint = Color(red: 0.52, green: 0.53, blue: 0.58)
}

struct FloatingRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var showList = false
    @State private var draft = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [FloatingPalette.bg, .white, .white],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()

            if sizeClass == .regular { regular } else { compact }
        }
        .tint(FloatingPalette.accent)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showList) {
            FloatingHistory()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: iPad

    private var regular: some View {
        ZStack(alignment: .top) {
            ScrollView {
                messageColumn(700)
                    .padding(.top, 104)
                    .padding(.bottom, 220)
                    .padding(.horizontal, 32)
            }

            header
                .padding(.horizontal, 26)
                .padding(.top, 10)
        }
        .overlay(alignment: .bottom) {
            composer
                .frame(maxWidth: 660)
                .padding(.horizontal, 32)
                .padding(.bottom, 22)
                .background {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.white.opacity(0), .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 70)
                        Color.white
                    }
                    .padding(.top, -70)
                    .ignoresSafeArea(edges: .bottom)
                }
        }
    }

    // MARK: iPhone

    private var compact: some View {
        ZStack(alignment: .top) {
            ScrollView {
                messageColumn(.infinity)
                    .padding(.top, 96)
                    .padding(.bottom, 200)
                    .padding(.horizontal, 20)
            }

            header
                .padding(.horizontal, 18)
                .padding(.top, 6)
        }
        .overlay(alignment: .bottom) {
            composer
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
                .background {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.white.opacity(0), .white],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: 64)
                        Color.white
                    }
                    .padding(.top, -64)
                    .ignoresSafeArea(edges: .bottom)
                }
        }
    }

    // MARK: 内容

    private func messageColumn(_ width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 30) {
            ForEach(ExploreDemo.messages) { message in
                if message.role == .user {
                    HStack {
                        Spacer(minLength: width.isFinite ? 90 : 36)
                        Text(message.text)
                            .font(.system(size: 17))
                            .lineSpacing(4)
                            .foregroundStyle(FloatingPalette.ink)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 13)
                            .background(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .fill(FloatingPalette.bubble)
                            )
                    }
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        DemoAssistantBody(blocks: message.blocks, bodySize: 17)

                        HStack(spacing: 22) {
                            Image(systemName: "doc.on.doc")
                            Image(systemName: "arrow.clockwise")
                            Image(systemName: "hand.thumbsdown")
                            Spacer()
                        }
                        .font(.system(size: 13))
                        .foregroundStyle(FloatingPalette.faint.opacity(0.8))
                    }
                }
            }
        }
        .frame(maxWidth: width, alignment: .leading)
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: 头部

    private var header: some View {
        HStack {
            Button {
                showList = true
            } label: {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FloatingPalette.ink.opacity(0.7))
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Spacer()

            VStack(spacing: 1) {
                Text("DeepSeek")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FloatingPalette.ink)
                Text(modelLine)
                    .font(.system(size: 10))
                    .foregroundStyle(FloatingPalette.faint)
            }

            Spacer()

            Button {
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FloatingPalette.accent)
                    .frame(width: 38, height: 38)
                    .background(
                        Circle()
                            .fill(.white)
                            .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
                    )
                    .overlay(Circle().stroke(Color.black.opacity(0.05), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private var modelLine: String {
        "deepseek-flash · 深度思考"
    }

    // MARK: 悬浮输入

    private var composer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                FloatingChip(icon: "brain", title: "深度思考", isOn: true)
                FloatingChip(icon: "globe.asia.australia", title: "联网搜索", isOn: false)
            }
            .padding(.leading, 6)

            HStack(alignment: .bottom, spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(FloatingPalette.faint)
                    .frame(width: 32, height: 32)

                TextField("给 DeepSeek 发消息", text: $draft, axis: .vertical)
                    .font(.system(size: 16))
                    .lineLimit(1...5)
                    .padding(.vertical, 7)

                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(FloatingPalette.accent.opacity(0.45)))
            }
            .padding(.leading, 10)
            .padding(.trailing, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.black.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.09), radius: 24, y: 10)
        }
    }
}

// MARK: - 浮层历史

private struct FloatingHistory: View {
    var body: some View {
        NavigationStack {
            List {
                ForEach(ExploreDemo.conversations) { item in
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.title)
                                .font(.system(size: 15, weight: .medium))
                            Text(item.preview)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Text(item.time)
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.plain)
            .navigationTitle("最近")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - 玻璃胶囊

private struct FloatingChip: View {
    let icon: String
    let title: String
    let isOn: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
            Text(title)
                .font(.system(size: 12))
        }
        .foregroundStyle(isOn ? FloatingPalette.accent : FloatingPalette.faint)
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(.white)
                .shadow(color: .black.opacity(0.05), radius: 8, y: 3)
        )
        .overlay(Capsule().stroke(Color.black.opacity(0.055), lineWidth: 1))
    }
}
