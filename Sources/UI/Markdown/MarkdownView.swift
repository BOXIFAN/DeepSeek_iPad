import SwiftUI

/// 正文渲染：块级结构自己排版，行内样式交给 AttributedString。
///
/// TODO(里程碑 2)：流式时每来一个 delta 都重新解析会掉帧，
/// 需要按块缓存 AST 并把刷新节流到 ~60ms。
struct MarkdownView: View {
    let text: String
    var citations: [Citation] = []

    @State private var activeCitation: Citation?

    var body: some View {
        let blocks = MarkdownParser.parse(text)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "citation",
               let index = Int(url.host ?? ""),
               citations.indices.contains(index) {
                activeCitation = citations[index]
                return .handled
            }
            return .systemAction
        })
        .sheet(item: $activeCitation) { citation in
            CitationSheet(citation: citation)
        }
    }

    @ViewBuilder
    private func blockView(_ block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .font(headingFont(level))
                .fontWeight(level <= 2 ? .semibold : .medium)
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(let text):
            Text(inline(text))
                .font(.body)
                .lineSpacing(3)
                .textSelection(.enabled)

        case .code(let language, let code):
            CodeBlockView(language: language, code: code)

        case .table(let headers, let rows):
            MarkdownTable(headers: headers, rows: rows)

        case .bullets(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        Text(inline(item)).font(.body).lineSpacing(3)
                    }
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(offset + 1).")
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(inline(item)).font(.body).lineSpacing(3)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.secondary.opacity(0.28))
                    .frame(width: 3)
                Text(inline(text))
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

        case .divider:
            Divider()
        }
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: return .title2
        case 2: return .title3
        case 3: return .headline
        default: return .subheadline
        }
    }

    /// 把 `[1]` 这类引用角标改写成 markdown 链接 `[1](citation://0)`，
    /// 这样 AttributedString 会把它渲染成可点击的链接，点击由 OpenURLAction 拦截。
    private func inline(_ raw: String) -> AttributedString {
        var source = raw

        if !citations.isEmpty {
            for number in stride(from: citations.count, through: 1, by: -1) {
                source = source.replacingOccurrences(
                    of: "[\(number)]",
                    with: "[\(number)](citation://\(number - 1))"
                )
            }
        }

        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        guard var attributed = try? AttributedString(markdown: source, options: options) else {
            return AttributedString(raw)
        }

        // 引用角标统一染成品牌色并上标显示
        for run in attributed.runs {
            guard let link = run.link, link.scheme == "citation" else { continue }
            attributed[run.range].foregroundColor = Theme.accent
            attributed[run.range].font = .footnote
            attributed[run.range].baselineOffset = 4
        }
        return attributed
    }
}

// MARK: - 代码块

struct CodeBlockView: View {
    let language: String?
    let code: String

    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language ?? "text")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = code
                    withAnimation { copied = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
                        withAnimation { copied = false }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        Text(copied ? "已复制" : "复制")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)

            Divider().opacity(0.5)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(SyntaxHighlighter.highlight(code, language: language))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

// MARK: - 表格

struct MarkdownTable: View {
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        if headers.count > 4 {
            // 列多时允许横向滚动，否则每列会被压到没法读
            ScrollView(.horizontal, showsIndicators: false) {
                grid.fixedSize(horizontal: true, vertical: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(border)
        } else {
            grid
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(border)
        }
    }

    /// 列数不多时让表格撑满正文宽度。之前用 fixedSize 固定成内容宽度，
    /// 结果外框比表头背景宽出一大截，右侧留白很显眼。
    private var grid: some View {
        Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                    cell(header, isHeader: true)
                }
            }
            .background(Color(uiColor: .tertiarySystemBackground))

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIndex, row in
                Divider()
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, text in
                        cell(text, isHeader: false)
                    }
                }
                .background(rowIndex.isMultiple(of: 2)
                            ? Color.clear
                            : Color(uiColor: .tertiarySystemBackground).opacity(0.45))
            }
        }
    }

    private func cell(_ text: String, isHeader: Bool) -> some View {
        Text(text)
            .font(isHeader ? .footnote.weight(.semibold) : .footnote)
            .lineLimit(isHeader ? 1 : 2)
            .minimumScaleFactor(isHeader ? 0.7 : 0.85)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
    }
}

// MARK: - 引用详情

struct CitationSheet: View {
    let citation: Citation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if let title = citation.title {
                        Text(title).font(.headline)
                    }
                    Text(citation.host)
                        .font(.footnote)
                        .foregroundStyle(Theme.accent)

                    if let excerpt = citation.citedText, !excerpt.isEmpty {
                        Text(excerpt)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(uiColor: .secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }

                    if let url = URL(string: citation.url) {
                        Link(destination: url) {
                            Label("在浏览器中打开", systemImage: "safari")
                                .font(.callout)
                        }
                    }
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .navigationTitle("来源")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
