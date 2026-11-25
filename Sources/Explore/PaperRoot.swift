import SwiftUI

// MARK: - 方向 A · 墨纸
//
// 研究阅读台。暖白纸感底、宋体正文、顶部会话标签条、右侧推理与来源边注。
// 目标：读完一段有出处的答案，而不是刷一段对话。

enum PaperInk {
    static let bg = Color(red: 0.984, green: 0.973, blue: 0.953)
    static let card = Color(red: 0.965, green: 0.950, blue: 0.925)
    static let ink = Color(red: 0.106, green: 0.102, blue: 0.090)
    static let body = Color(red: 0.176, green: 0.169, blue: 0.149)
    static let sub = Color(red: 0.435, green: 0.416, blue: 0.376)
    static let faint = Color(red: 0.573, green: 0.553, blue: 0.510)
    static let rule = Color(red: 0.878, green: 0.859, blue: 0.816)
    static let accent = Color(red: 0.153, green: 0.318, blue: 0.251)
}

func songti(_ size: CGFloat) -> Font { .custom("Songti SC", size: size) }

struct PaperRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular { regular } else { compact }
        }
        .background(PaperInk.bg.ignoresSafeArea())
        .tint(PaperInk.accent)
        .preferredColorScheme(.light)
    }

    // MARK: iPad

    private var regular: some View {
        VStack(spacing: 0) {
            PaperTabStrip()
            Rectangle().fill(PaperInk.rule).frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 34) {
                        ForEach(ExploreDemo.messages) { message in
                            if message.role == .user {
                                PaperQuestion(text: message.text)
                            } else {
                                PaperAnswer(
                                    blocks: message.blocks,
                                    bodySize: 17.5,
                                    meta: message.id == "a1" ? "用时 13 秒 · 搜索 2 次" : "直接计算 · 无检索"
                                )
                            }
                        }
                        Color.clear.frame(height: 1)
                    }
                    .frame(maxWidth: 620, alignment: .leading)
                    .padding(.horizontal, 36)
                    .padding(.top, 38)
                    .padding(.bottom, 24)
                    .frame(maxWidth: .infinity)
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    PaperComposer()
                        .padding(.horizontal, 36)
                        .padding(.bottom, 12)
                        .background(PaperInk.bg.ignoresSafeArea(edges: .bottom))
                }

                Rectangle().fill(PaperInk.rule).frame(width: 1)

                PaperNoteRail()
                    .frame(width: 285)
            }
        }
    }

    // MARK: iPhone

    private var compact: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                Spacer()
                VStack(spacing: 1) {
                    Text(ExploreDemo.conversationTitle)
                        .font(songti(15))
                        .fontWeight(.semibold)
                        .foregroundStyle(PaperInk.ink)
                    Text("深度思考 · 3 个来源")
                        .font(.system(size: 10))
                        .foregroundStyle(PaperInk.faint)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 15))
            }
            .foregroundStyle(PaperInk.sub)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            Rectangle().fill(PaperInk.rule).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    ForEach(ExploreDemo.messages) { message in
                        if message.role == .user {
                            PaperQuestion(text: message.text, compact: true)
                        } else {
                            PaperAnswer(
                                blocks: message.blocks,
                                bodySize: 16.5,
                                meta: message.id == "a1" ? "用时 13 秒 · 搜索 2 次" : "直接计算 · 无检索"
                            )
                        }
                    }
                    Color.clear.frame(height: 1)
                }
                .padding(.horizontal, 22)
                .padding(.top, 26)
                .padding(.bottom, 24)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                PaperComposer()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .background(PaperInk.bg.ignoresSafeArea(edges: .bottom))
            }
        }
    }
}

// MARK: - 顶部会话标签条

private struct PaperTabStrip: View {
    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(PaperInk.accent)
                    .frame(width: 15, height: 15)
                    .overlay(
                        Text("D")
                            .font(songti(10))
                            .foregroundStyle(PaperInk.bg)
                    )
                Text("DeepSeek")
                    .font(songti(13))
                    .fontWeight(.semibold)
                    .foregroundStyle(PaperInk.ink)
            }
            .padding(.trailing, 4)

            Rectangle().fill(PaperInk.rule).frame(width: 1, height: 18)

            ForEach(Array(ExploreDemo.conversations.prefix(4).enumerated()), id: \.element.id) { index, item in
                tab(item.title, active: index == 0)
            }

            Button {
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(PaperInk.sub)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(PaperInk.card))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 8)

            Image(systemName: "magnifyingglass")
                .font(.system(size: 13))
                .foregroundStyle(PaperInk.sub)
            Image(systemName: "gearshape")
                .font(.system(size: 13))
                .foregroundStyle(PaperInk.sub)
        }
        .padding(.horizontal, 22)
        .frame(height: 54)
    }

    private func tab(_ title: String, active: Bool) -> some View {
        Text(title)
            .font(songti(12.5))
            .lineLimit(1)
            .foregroundStyle(active ? PaperInk.ink : PaperInk.sub)
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? PaperInk.card : Color.clear)
            )
            .overlay(alignment: .top) {
                if active {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(PaperInk.accent)
                        .frame(width: 18, height: 2)
                        .offset(y: -1)
                }
            }
    }
}

// MARK: - 一轮问答

private struct PaperQuestion: View {
    let text: String
    var compact: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Text("问")
                    .font(songti(10))
                    .foregroundStyle(PaperInk.accent)
                Rectangle()
                    .fill(PaperInk.accent.opacity(0.35))
                    .frame(width: 1)
                    .frame(maxHeight: .infinity)
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text("你的问题")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(1.4)
                        .foregroundStyle(PaperInk.faint)
                    Text("4:01")
                        .font(.system(size: 9.5))
                        .foregroundStyle(PaperInk.faint)
                }
                Text(text)
                    .font(songti(compact ? 19 : 20))
                    .lineSpacing(7)
                    .foregroundStyle(PaperInk.ink)
            }
            .padding(.bottom, 2)
        }
    }
}

private struct PaperAnswer: View {
    let blocks: [ContentBlock]
    var bodySize: CGFloat = 17.5
    var meta: String = "用时 13 秒 · 搜索 2 次"

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack(spacing: 7) {
                Text("deepseek-flash")
                    .font(.system(size: 9.5, weight: .medium))
                    .tracking(0.8)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().stroke(PaperInk.accent.opacity(0.4), lineWidth: 0.8)
                    )
                    .foregroundStyle(PaperInk.accent)
                Text(meta)
                    .font(.system(size: 9.5))
                    .foregroundStyle(PaperInk.faint)
                Spacer(minLength: 0)
                Text("4:01")
                    .font(.system(size: 9.5))
                    .foregroundStyle(PaperInk.faint)
            }

            DemoAssistantBody(blocks: blocks, serif: true, bodySize: bodySize)

            HStack(spacing: 20) {
                Label("复制", systemImage: "doc.on.doc")
                Label("重答", systemImage: "arrow.clockwise")
                Label("标注", systemImage: "bookmark")
                Spacer()
            }
            .font(.system(size: 10.5))
            .foregroundStyle(PaperInk.faint)
            .padding(.top, 4)
        }
        .padding(.leading, 30)
    }
}

// MARK: - 右侧边注

private struct PaperNoteRail: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                section("本次回答") {
                    VStack(alignment: .leading, spacing: 7) {
                        metaRow("模型", "deepseek-flash")
                        metaRow("思考", "13 秒")
                        metaRow("搜索", "2 次 · 3 个来源")
                        metaRow("输出", "1,842 字")
                    }
                }

                section("来源") {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(ExploreDemo.sources.enumerated()), id: \.offset) { index, source in
                            HStack(alignment: .top, spacing: 9) {
                                Text("[\(index + 1)]")
                                    .font(.system(size: 10.5, design: .monospaced))
                                    .foregroundStyle(PaperInk.accent)
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.0)
                                        .font(songti(12.5))
                                        .foregroundStyle(PaperInk.ink)
                                        .lineLimit(2)
                                    Text("\(source.1) · \(source.2)")
                                        .font(.system(size: 9.5))
                                        .foregroundStyle(PaperInk.faint)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }

                section("关键数字") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(ExploreDemo.keyNumbers.enumerated()), id: \.offset) { _, pair in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(pair.1)
                                    .font(songti(14))
                                    .foregroundStyle(PaperInk.ink)
                                    .frame(width: 84, alignment: .leading)
                                Text(pair.0)
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(PaperInk.sub)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                }

                Button {
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 11))
                        Text("整理成笔记")
                            .font(songti(12.5))
                    }
                    .foregroundStyle(PaperInk.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(PaperInk.card)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(PaperInk.rule, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 22)
            .padding(.top, 36)
            .padding(.bottom, 40)
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .tracking(1.8)
                    .foregroundStyle(PaperInk.faint)
                Rectangle().fill(PaperInk.rule).frame(height: 1)
            }
            content()
        }
    }

    private func metaRow(_ key: String, _ value: String) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 10.5))
                .foregroundStyle(PaperInk.sub)
            Spacer()
            Text(value)
                .font(.system(size: 11))
                .foregroundStyle(PaperInk.ink)
        }
    }
}

// MARK: - 输入条

private struct PaperComposer: View {
    @State private var text = ""
    @State private var thinking = true
    @State private var search = false

    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                toggle("深度思考", on: $thinking)
                toggle("联网搜索", on: $search)
                Spacer()
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField("继续追问…", text: $text, axis: .vertical)
                    .font(songti(15))
                    .lineLimit(1...5)
                    .foregroundStyle(PaperInk.ink)

                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PaperInk.bg)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(PaperInk.accent))
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(PaperInk.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PaperInk.rule, lineWidth: 1)
            )
        }
        .padding(.top, 10)
        .padding(.bottom, 6)
        .background(PaperInk.bg)
    }

    private func toggle(_ title: String, on: Binding<Bool>) -> some View {
        Button {
            on.wrappedValue.toggle()
        } label: {
            HStack(spacing: 5) {
                Circle()
                    .fill(on.wrappedValue ? PaperInk.accent : PaperInk.rule)
                    .frame(width: 5, height: 5)
                Text(title)
                    .font(songti(11.5))
                    .foregroundStyle(on.wrappedValue ? PaperInk.accent : PaperInk.sub)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(on.wrappedValue ? PaperInk.accent.opacity(0.08) : Color.clear)
            )
            .overlay(
                Capsule().stroke(on.wrappedValue ? PaperInk.accent.opacity(0.3) : PaperInk.rule, lineWidth: 0.8)
            )
        }
        .buttonStyle(.plain)
    }
}
