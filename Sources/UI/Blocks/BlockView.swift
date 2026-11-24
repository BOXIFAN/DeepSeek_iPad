import SwiftUI

/// 渲染块分发。用 RenderBlock 而不是 ContentBlock，是因为搜索的调用与结果要先合组。
struct BlockView: View {
    let block: RenderBlock

    var body: some View {
        switch block {
        case .thinking(_, let text, let duration):
            ThinkingBlockView(text: text, duration: duration)

        case .search(_, let queries, let results, let errorCode):
            SearchGroupView(queries: queries, results: results, errorCode: errorCode)

        case .fetchedPage(_, let page):
            FetchedPageCard(page: page)

        case .text(_, let text, let citations):
            MarkdownView(text: text, citations: citations)
        }
    }
}

// MARK: - 思考块

struct ThinkingBlockView: View {
    let text: String
    let duration: TimeInterval?

    /// DS_EXPAND_THINKING=1 时默认展开，供命令行截图核对展开态排版。
    @State private var expanded = ProcessInfo.processInfo.environment["DS_EXPAND_THINKING"] == "1"

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Text(title)
                        .font(.footnote)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.secondary.opacity(0.22))
                        .frame(width: 2)
                    Text(text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .transition(.opacity)
            }
        }
    }

    private var title: String {
        if let duration {
            return "已深度思考（用时 \(Int(duration)) 秒）"
        }
        return "深度思考"
    }
}

// MARK: - 搜索（调用 + 结果合成一条）

struct SearchGroupView: View {
    let queries: [String]
    let results: [SearchResult]?
    let errorCode: String?

    /// DS_EXPAND_SEARCH=1 时默认展开，供命令行截图看结果卡片。
    @State private var expanded = ProcessInfo.processInfo.environment["DS_EXPAND_SEARCH"] == "1"

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                    Text(summary)
                        .font(.footnote)
                        .lineLimit(1)
                    if hasContent {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    Spacer(minLength: 0)
                }
                .foregroundStyle(.secondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                content
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorCode {
            Text("搜索失败：\(errorCode)")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if let results, !results.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    SearchResultRow(result: result)
                    if index < results.count - 1 {
                        Divider().padding(.leading, 44)
                    }
                }
            }
            .background(Color(uiColor: .secondarySystemBackground).opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardCorner, style: .continuous))
        }
    }

    private var hasContent: Bool {
        if errorCode != nil { return true }
        return !(results?.isEmpty ?? true)
    }

    private var summary: String {
        let queryPart: String
        if queries.count > 1 {
            queryPart = "搜索 \(queries.count) 个关键词"
        } else if let first = queries.first {
            queryPart = "搜索「\(first)」"
        } else {
            queryPart = "搜索"
        }

        guard let results, !results.isEmpty else { return queryPart }
        return "\(queryPart) · \(results.count) 个结果"
    }
}

private struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SiteIcon(name: result.siteName, url: result.siteIcon)

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let snippet = result.snippet {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .padding(.top, 1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }

    private var subtitle: String {
        [result.siteName ?? result.host, result.pageAge]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

// MARK: - 打开的网页

/// 官方对这种「模型自己打开的页」只给一行轻量提示，不做卡片，避免打断正文节奏。
struct FetchedPageCard: View {
    let page: FetchedPage

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: page.errorCode == nil ? "doc.text" : "exclamationmark.triangle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Text(page.title ?? page.host)
                .font(.footnote)
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text("· \(page.host)")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - 站点图标

/// 服务端返回的 `site_icon` 是 CDN 地址，可能为 nil 或加载失败。
/// 用首字母方块兜底，避免截图和弱网时出现空白。
private struct SiteIcon: View {
    let name: String?
    let url: String?

    var body: some View {
        ZStack {
            if let url, let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 22, height: 22)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var fallback: some View {
        ZStack {
            Theme.accent.opacity(0.12)
            Text(initial)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.accent)
        }
    }

    private var initial: String {
        let source = name ?? url.flatMap { URL(string: $0)?.host } ?? "?"
        return String(source.prefix(1)).uppercased()
    }
}
