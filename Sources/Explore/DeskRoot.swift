import SwiftUI

// MARK: - 方向 C · 台面
//
// 工作台。左栏会话与项目、中间对话、右栏本轮上下文（模型、检索、用量、费用、来源）。
// 目标：把 DeepSeek 当成每天要用的工具，成本和上下文一眼可见。

enum DeskPalette {
    static let bg = Color(red: 0.949, green: 0.953, blue: 0.961)
    static let rail = Color(red: 0.925, green: 0.929, blue: 0.941)
    static let panel = Color.white
    static let ink = Color(red: 0.090, green: 0.098, blue: 0.118)
    static let sub = Color(red: 0.420, green: 0.443, blue: 0.478)
    static let faint = Color(red: 0.596, green: 0.616, blue: 0.647)
    static let line = Color(red: 0.886, green: 0.894, blue: 0.906)
    static let accent = Color(red: 0.302, green: 0.420, blue: 0.996)
    static let green = Color(red: 0.133, green: 0.549, blue: 0.396)
    static let amber = Color(red: 0.78, green: 0.53, blue: 0.12)
}

struct DeskRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular { regular } else { compact }
        }
        .background(DeskPalette.bg.ignoresSafeArea())
        .tint(DeskPalette.accent)
        .preferredColorScheme(.light)
    }

    // MARK: iPad

    private var regular: some View {
        HStack(spacing: 0) {
            DeskRail()
                .frame(width: 232)

            Rectangle().fill(DeskPalette.line).frame(width: 1)

            VStack(spacing: 0) {
                DeskToolbar(compact: false)
                Rectangle().fill(DeskPalette.line).frame(height: 1)

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        ForEach(ExploreDemo.messages) { message in
                            if message.role == .user {
                                DeskQuestion(text: message.text)
                            } else {
                                DeskAnswer(
                                    blocks: message.blocks,
                                    bodySize: 15,
                                    meta: message.id == "a1" ? "13 秒 · 2 次调用" : "直接计算 · 无检索"
                                )
                            }
                        }
                        Color.clear.frame(height: 1)
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 22)
                    .padding(.bottom, 12)
                }

                DeskComposer()
                    .padding(.horizontal, 22)
                    .padding(.bottom, 14)
            }
            .background(DeskPalette.panel)

            Rectangle().fill(DeskPalette.line).frame(width: 1)

            DeskContextPanel()
                .frame(width: 272)
                .background(DeskPalette.panel)
        }
    }

    // MARK: iPhone

    private var compact: some View {
        VStack(spacing: 0) {
            DeskToolbar(compact: true)
            Rectangle().fill(DeskPalette.line).frame(height: 1)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 6) {
                        DeskBadge(text: "12.4k / 1M", tone: .normal)
                        DeskBadge(text: "0.0147 元", tone: .cost)
                        DeskBadge(text: "搜索 2 次", tone: .normal)
                    }

                    ForEach(ExploreDemo.messages) { message in
                        if message.role == .user {
                            DeskQuestion(text: message.text)
                        } else {
                            DeskAnswer(
                                blocks: message.blocks,
                                bodySize: 15.5,
                                meta: message.id == "a1" ? "13 秒 · 2 次调用" : "直接计算 · 无检索"
                            )
                        }
                    }
                    Color.clear.frame(height: 1)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .padding(.bottom, 10)
            }

            DeskComposer(compact: true)
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 12)

            Rectangle().fill(DeskPalette.line).frame(height: 1)
            DeskTabBar()
        }
    }
}

// MARK: - 左栏

private struct DeskRail: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(DeskPalette.accent)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Text("D")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                    )
                VStack(alignment: .leading, spacing: 0) {
                    Text("DeepSeek")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DeskPalette.ink)
                    Text("客户端")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DeskPalette.faint)
                }
                Spacer()
                Image(systemName: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(DeskPalette.sub)
            }
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 14)

            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    groupLabel("今天")
                    ForEach(Array(ExploreDemo.conversations.prefix(2).enumerated()), id: \.element.id) { index, item in
                        railRow(item, selected: index == 0)
                    }

                    groupLabel("昨天")
                    ForEach(Array(ExploreDemo.conversations.dropFirst(2).prefix(2).enumerated()), id: \.element.id) { _, item in
                        railRow(item, selected: false)
                    }

                    groupLabel("项目")
                    projectRow("客户端开发", count: 12, color: DeskPalette.accent)
                    projectRow("论文与笔记", count: 7, color: DeskPalette.green)
                    projectRow("临时", count: 3, color: DeskPalette.amber)
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 20)
            }

            Rectangle().fill(DeskPalette.line).frame(height: 1)

            HStack(spacing: 7) {
                Circle().fill(DeskPalette.green).frame(width: 6, height: 6)
                Text("Key 已保存 · 本机")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DeskPalette.sub)
                Spacer()
                Text("v4.0")
                    .font(.system(size: 9.5))
                    .foregroundStyle(DeskPalette.faint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
    }

    private func groupLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(DeskPalette.faint)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 6)
    }

    private func railRow(_ item: ExploreDemo.Conversation, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? DeskPalette.accent : DeskPalette.ink)
                .lineLimit(1)
            HStack(spacing: 4) {
                Text(item.time)
                    .font(.system(size: 9.5))
                Text("·")
                    .font(.system(size: 9.5))
                Text(item.tokens)
                    .font(.system(size: 9.5, design: .monospaced))
            }
            .foregroundStyle(DeskPalette.faint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? DeskPalette.accent.opacity(0.10) : Color.clear)
        )
    }

    private func projectRow(_ name: String, count: Int, color: Color) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(color)
                .frame(width: 7, height: 7)
            Text(name)
                .font(.system(size: 12))
                .foregroundStyle(DeskPalette.ink)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(DeskPalette.faint)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
    }
}

// MARK: - 工具条

private struct DeskToolbar: View {
    var compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            if compact {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DeskPalette.sub)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(ExploreDemo.conversationTitle)
                    .font(.system(size: compact ? 14 : 13.5, weight: .semibold))
                    .foregroundStyle(DeskPalette.ink)
                    .lineLimit(1)
                if !compact {
                    Text("2 轮 · 今天 4:01 · 342 tokens/s")
                        .font(.system(size: 10))
                        .foregroundStyle(DeskPalette.faint)
                }
            }

            Spacer(minLength: 4)

            modelPill
            if !compact {
                DeskBadge(text: "12.4k / 1M", tone: .normal)
            }
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(DeskPalette.sub)
        }
        .padding(.horizontal, compact ? 14 : 20)
        .frame(height: compact ? 48 : 54)
    }

    private var modelPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(DeskPalette.accent)
                .frame(width: 5, height: 5)
            Text("flash")
                .font(.system(size: 10.5, weight: .medium))
            Image(systemName: "chevron.down")
                .font(.system(size: 7, weight: .bold))
        }
        .foregroundStyle(DeskPalette.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(DeskPalette.accent.opacity(0.10))
        )
    }
}

private enum BadgeTone { case normal, cost, search }

private struct DeskBadge: View {
    let text: String
    let tone: BadgeTone

    private var color: Color {
        switch tone {
        case .normal: return DeskPalette.sub
        case .cost: return DeskPalette.green
        case .search: return DeskPalette.amber
        }
    }

    var body: some View {
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize()
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(color.opacity(0.09))
            )
    }
}

// MARK: - 消息

private struct DeskQuestion: View {
    let text: String

    var body: some View {
        HStack {
            Spacer(minLength: 40)
            Text(text)
                .font(.system(size: 13.5))
                .lineSpacing(3)
                .foregroundStyle(DeskPalette.ink)
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DeskPalette.bg)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DeskPalette.line, lineWidth: 1)
                )
        }
    }
}

private struct DeskAnswer: View {
    let blocks: [ContentBlock]
    var bodySize: CGFloat = 15
    var meta: String = "13 秒 · 2 次调用"

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(DeskPalette.accent)
                    .frame(width: 3, height: 11)
                Text("deepseek-flash")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DeskPalette.sub)
                Text("· \(meta)")
                    .font(.system(size: 10))
                    .foregroundStyle(DeskPalette.faint)
                Spacer()
            }

            DemoAssistantBody(blocks: blocks, bodySize: bodySize)

            HStack(spacing: 16) {
                Label("复制", systemImage: "doc.on.doc")
                Label("重答", systemImage: "arrow.clockwise")
                Label("继续", systemImage: "arrow.turn.down.right")
                Spacer()
                Text("0.0147 元")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(DeskPalette.green)
            }
            .font(.system(size: 10.5))
            .foregroundStyle(DeskPalette.faint)
        }
    }
}

// MARK: - 右栏：本轮上下文

private struct DeskContextPanel: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("本轮")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(DeskPalette.ink)
                    Spacer()
                    Text("实时")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DeskPalette.green)
                }

                VStack(spacing: 9) {
                    stat("模型", "deepseek-flash", mono: false)
                    stat("思考", "13 秒", mono: false)
                    stat("工具调用", "2 次", mono: true)
                    stat("输出", "1,842 字", mono: true)
                }

                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text("上下文")
                            .font(.system(size: 10.5))
                            .foregroundStyle(DeskPalette.sub)
                        Spacer()
                        Text("12.4k / 1M")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(DeskPalette.ink)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DeskPalette.line)
                            Capsule()
                                .fill(DeskPalette.accent)
                                .frame(width: max(6, geo.size.width * 0.0124))
                        }
                    }
                    .frame(height: 5)
                }

                VStack(alignment: .leading, spacing: 6) {
                    divider
                    HStack {
                        Text("估算费用")
                            .font(.system(size: 10.5))
                            .foregroundStyle(DeskPalette.sub)
                        Spacer()
                        Text("0.0147 元")
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(DeskPalette.green)
                    }
                    Text("空闲时段单价 · 命中缓存 0.02 元 / 百万 tokens")
                        .font(.system(size: 9.5))
                        .foregroundStyle(DeskPalette.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    divider
                    sectionTitle("来源")
                    ForEach(Array(ExploreDemo.sources.enumerated()), id: \.offset) { index, source in
                        HStack(alignment: .top, spacing: 7) {
                            Text("\(index + 1)")
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundStyle(DeskPalette.accent)
                                .frame(width: 12, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(source.0)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DeskPalette.ink)
                                    .lineLimit(2)
                                Text(source.1)
                                    .font(.system(size: 9.5))
                                    .foregroundStyle(DeskPalette.faint)
                                    .lineLimit(1)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    divider
                    sectionTitle("工具调用")
                    toolRow("deepseek_web_search", "搜索 2 词", DeskPalette.accent)
                    toolRow("web_fetch_tool_result", "打开 1 页", DeskPalette.green)
                }

                VStack(alignment: .leading, spacing: 6) {
                    divider
                    sectionTitle("端点")
                    Text("POST /anthropic/v1/messages")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(DeskPalette.sub)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(DeskPalette.bg)
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 18)
        }
    }

    private var divider: some View {
        Rectangle().fill(DeskPalette.line).frame(height: 1)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9.5, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(DeskPalette.faint)
    }

    private func stat(_ key: String, _ value: String, mono: Bool) -> some View {
        HStack {
            Text(key)
                .font(.system(size: 10.5))
                .foregroundStyle(DeskPalette.sub)
            Spacer()
            Text(value)
                .font(.system(size: 10.5, weight: .medium, design: mono ? .monospaced : .default))
                .foregroundStyle(DeskPalette.ink)
        }
    }

    private func toolRow(_ name: String, _ kind: String, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color.opacity(0.8)).frame(width: 5, height: 5)
            Text(name)
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(DeskPalette.sub)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(kind)
                .font(.system(size: 9))
                .foregroundStyle(DeskPalette.faint)
        }
    }
}

// MARK: - 输入与底栏

private struct DeskComposer: View {
    var compact: Bool = false
    @State private var text = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image(systemName: "paperclip")
                .font(.system(size: 13))
                .foregroundStyle(DeskPalette.faint)
                .frame(width: 26, height: 26)

            TextField("给 DeepSeek 发送消息", text: $text, axis: .vertical)
                .font(.system(size: 13.5))
                .lineLimit(1...5)
                .padding(.vertical, 5)

            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Circle().fill(DeskPalette.accent.opacity(0.4)))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DeskPalette.panel)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DeskPalette.line, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.05), radius: 12, y: 4)
    }
}

private struct DeskTabBar: View {
    var body: some View {
        HStack {
            tab("对话", "bubble.left.and.text.bubble.right", active: true)
            tab("项目", "square.grid.2x2", active: false)
            tab("搜索", "magnifyingglass", active: false)
            tab("设置", "gearshape", active: false)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 2)
        .background(DeskPalette.panel)
    }

    private func tab(_ title: String, _ icon: String, active: Bool) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 15))
            Text(title)
                .font(.system(size: 9))
        }
        .foregroundStyle(active ? DeskPalette.accent : DeskPalette.faint)
        .frame(maxWidth: .infinity)
    }
}
