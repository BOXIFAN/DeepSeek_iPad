import SwiftUI

// MARK: - 方向 D · 卡片
//
// 一轮问答一张卡。卡片头是问题、卡片体是回答、卡片脚是检索与操作；
// 左侧是本对话的问题轴，长对话回看和转发都按卡片来。

enum CardsPalette {
    static let bg = Color(red: 0.953, green: 0.953, blue: 0.965)
    static let card = Color.white
    static let ink = Color(red: 0.094, green: 0.098, blue: 0.114)
    static let sub = Color(red: 0.408, green: 0.424, blue: 0.455)
    static let faint = Color(red: 0.588, green: 0.604, blue: 0.631)
    static let hairline = Color.black.opacity(0.07)
    static let accent = Color(red: 0.302, green: 0.420, blue: 0.996)
    static let tint = Color(red: 0.945, green: 0.949, blue: 0.965)
    static let green = Color(red: 0.133, green: 0.549, blue: 0.396)
}

struct Round {
    var question: String
    var time: String
    var blocks: [ContentBlock]
    var meta: String
}

struct CardsRoot: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        Group {
            if sizeClass == .regular { regular } else { compact }
        }
        .background(CardsPalette.bg.ignoresSafeArea())
        .tint(CardsPalette.accent)
        .preferredColorScheme(.light)
    }

    // MARK: iPad

    private var regular: some View {
        VStack(spacing: 0) {
            CardsHeader(compact: false)
            Rectangle().fill(CardsPalette.hairline).frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                CardsTimeline()
                    .frame(width: 208)
                    .padding(.trailing, 8)

                VStack(spacing: 0) {
                    ScrollView {
                        VStack(spacing: 18) {
                            ForEach(Array(rounds.enumerated()), id: \.offset) { index, round in
                                CardsCard(index: index, round: round, compact: false)
                            }
                            Color.clear.frame(height: 1)
                        }
                        .frame(maxWidth: 700)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 24)
                        .padding(.bottom, 10)
                        .frame(maxWidth: .infinity)
                    }

                    CardsComposer()
                        .frame(maxWidth: 700)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 16)
                }
            }
        }
    }

    // MARK: iPhone

    private var compact: some View {
        VStack(spacing: 0) {
            CardsHeader(compact: true)
            Rectangle().fill(CardsPalette.hairline).frame(height: 1)

            HStack(spacing: 7) {
                ForEach(Array(rounds.enumerated()), id: \.offset) { index, round in
                    Text("Q\(index + 1) · \(shorten(round.question, to: 12))")
                        .font(.system(size: 11))
                        .lineLimit(1)
                        .foregroundStyle(index == 0 ? CardsPalette.accent : CardsPalette.sub)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule().fill(index == 0 ? CardsPalette.accent.opacity(0.1) : CardsPalette.tint)
                        )
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(rounds.enumerated()), id: \.offset) { index, round in
                        CardsCard(index: index, round: round, compact: true)
                    }
                    Color.clear.frame(height: 1)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 12)
            }

            CardsComposer(compact: true)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
    }

    // MARK: 数据

    private var rounds: [Round] {
        let all = ExploreDemo.messages
        var result: [Round] = []
        var pendingQuestion: String?
        for message in all {
            if message.role == .user {
                pendingQuestion = message.text
            } else if let question = pendingQuestion {
                result.append(
                    Round(
                        question: question,
                        time: result.isEmpty ? "今天 4:01" : "今天 4:03",
                        blocks: message.blocks,
                        meta: result.isEmpty ? "思考 13 秒 · 搜索 2 次 · 3 个来源" : "直接计算 · 无检索"
                    )
                )
                pendingQuestion = nil
            }
        }
        return result
    }

    private func shorten(_ text: String, to limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit)) + "…"
    }
}

// MARK: - 顶部

private struct CardsHeader: View {
    var compact: Bool

    var body: some View {
        HStack(spacing: 10) {
            if compact {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(CardsPalette.sub)
            } else {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(CardsPalette.accent)
                        .frame(width: 18, height: 18)
                        .overlay(
                            Text("D")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        )
                    Text("DeepSeek")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(CardsPalette.ink)
                }
                Rectangle().fill(CardsPalette.hairline).frame(width: 1, height: 16)
            }

            Text(ExploreDemo.conversationTitle)
                .font(.system(size: compact ? 14 : 12.5, weight: compact ? .semibold : .regular))
                .foregroundStyle(compact ? CardsPalette.ink : CardsPalette.sub)
                .lineLimit(1)

            Spacer()

            if !compact {
                Text("\(roundsCount) 张卡片")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(CardsPalette.faint)
            }

            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 14))
                .foregroundStyle(CardsPalette.sub)
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14))
                .foregroundStyle(CardsPalette.accent)
        }
        .padding(.horizontal, compact ? 16 : 22)
        .frame(height: compact ? 46 : 54)
    }

    private var roundsCount: Int {
        ExploreDemo.messages.filter { $0.role == .assistant }.count
    }
}

// MARK: - 左侧问题轴

private struct CardsTimeline: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text("本对话")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(CardsPalette.faint)
                Text("2 个问题 · 4:01 开始")
                    .font(.system(size: 10))
                    .foregroundStyle(CardsPalette.faint)
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 16)

            VStack(alignment: .leading, spacing: 0) {
                axisRow(number: "01",
                        time: "4:01",
                        question: ExploreDemo.messages.first?.text ?? "",
                        preview: "两个模型的能力与价格对照",
                        active: true)

                axisRow(number: "02",
                        time: "4:03",
                        question: ExploreDemo.messages[2].text,
                        preview: "按每天 200 万 tokens 估算月费",
                        active: false)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 10) {
                Rectangle().fill(CardsPalette.hairline).frame(height: 1)
                Label("导出为 Markdown", systemImage: "arrow.down.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(CardsPalette.sub)
                Label("只看结论", systemImage: "text.justify.left")
                    .font(.system(size: 11))
                    .foregroundStyle(CardsPalette.sub)
                Label("清空本对话", systemImage: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(CardsPalette.faint)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 26)
        }
    }

    private func axisRow(number: String, time: String, question: String, preview: String, active: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 4) {
                Text(number)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(active ? CardsPalette.accent : CardsPalette.faint)
                Rectangle()
                    .fill(active ? CardsPalette.accent.opacity(0.45) : CardsPalette.hairline)
                    .frame(width: 1, height: 78)
            }
            .frame(width: 16)
            .padding(.top, 3)

            VStack(alignment: .leading, spacing: 4) {
                Text(time)
                    .font(.system(size: 9.5))
                    .foregroundStyle(CardsPalette.faint)
                Text(question)
                    .font(.system(size: 11.5, weight: active ? .medium : .regular))
                    .foregroundStyle(active ? CardsPalette.ink : CardsPalette.sub)
                    .lineLimit(3)
                Text(preview)
                    .font(.system(size: 10))
                    .foregroundStyle(CardsPalette.faint)
                    .lineLimit(2)
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 18)
    }
}

// MARK: - 卡片

private struct CardsCard: View {
    let index: Int
    let round: Round
    var compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 7) {
                    Text("Q\(index + 1)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(CardsPalette.accent)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(CardsPalette.accent.opacity(0.1))
                        )
                    Text(round.time)
                        .font(.system(size: 10))
                        .foregroundStyle(CardsPalette.faint)
                    Spacer()
                    Text("deepseek-flash")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(CardsPalette.faint)
                }

                Text(round.question)
                    .font(.system(size: compact ? 16 : 15.5, weight: .medium))
                    .lineSpacing(4)
                    .foregroundStyle(CardsPalette.ink)
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 15)

            Rectangle().fill(CardsPalette.hairline).frame(height: 1)

            DemoAssistantBody(blocks: round.blocks, bodySize: compact ? 15.5 : 15)
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 18)

            Rectangle().fill(CardsPalette.hairline).frame(height: 1)

            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Circle().fill(CardsPalette.green).frame(width: 4, height: 4)
                    Text(round.meta)
                        .font(.system(size: 9.5))
                        .foregroundStyle(CardsPalette.faint)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "doc.on.doc")
                Image(systemName: "arrow.clockwise")
                Image(systemName: "ellipsis")
            }
            .font(.system(size: 11))
            .foregroundStyle(CardsPalette.sub)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(CardsPalette.tint.opacity(0.6))
        }
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(CardsPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(CardsPalette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 16, y: 7)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }
}

// MARK: - 输入

private struct CardsComposer: View {
    var compact: Bool = false
    @State private var text = ""

    var body: some View {
        HStack(alignment: .bottom, spacing: 9) {
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(CardsPalette.sub)
                .frame(width: 28, height: 28)
                .background(Circle().fill(CardsPalette.tint))

            TextField("继续问，或者让它把结论整理成卡片", text: $text, axis: .vertical)
                .font(.system(size: 13.5))
                .lineLimit(1...4)
                .padding(.vertical, 6)

            Image(systemName: "arrow.up")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(CardsPalette.accent.opacity(0.4)))
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(CardsPalette.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(CardsPalette.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 16, y: 6)
    }
}
