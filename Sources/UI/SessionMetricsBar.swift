import SwiftUI

// MARK: - 输入条下方的会话指标

/// 一行三个数字：剩余上下文 / 缓存命中 / 生成速度。
/// 数据都在最近一轮的 usage 里，点击展开明细。
struct SessionMetricsBar: View {

    let metrics: SessionMetrics
    /// 流式过程中按字符估算的实时速度，优先于上一轮的均值
    let liveTokensPerSecond: Double?
    var onDetail: () -> Void

    private var speed: Double? {
        liveTokensPerSecond ?? metrics.tokensPerSecond
    }

    private var contextText: String {
        "上下文剩 \(SessionMetrics.tokenText(metrics.remainingTokens))"
    }

    /// 环填的是「剩余」，和旁边的文字同义：越满代表窗口越空。
    private var remainingRatio: CGFloat {
        CGFloat(max(0, min(1, metrics.remainingRatio)))
    }

    private var ringColor: Color {
        metrics.isNearLimit ? .orange : Theme.accent
    }

    var body: some View {
        Button(action: onDetail) {
            HStack(spacing: 8) {
                HStack(spacing: 5) {
                    contextRing
                    Text(contextText)
                        .foregroundStyle(metrics.isNearLimit ? Color.orange : Color.secondary)
                }

                if metrics.hasCacheData, let cache = SessionMetrics.cacheText(metrics.cacheHitRate) {
                    divider
                    Text("缓存命中 \(cache)")
                }

                if let rate = SessionMetrics.rateText(speed) {
                    divider
                    Text(rate)
                }

                Spacer(minLength: 0)
            }
            .font(.system(size: 10.5))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("轻点查看会话用量明细")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(width: 1, height: 9)
    }

    private var contextRing: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.15), lineWidth: 1.8)
            Circle()
                .trim(from: 0, to: max(remainingRatio, 0.05))
                .stroke(ringColor, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 11, height: 11)
    }

    private var accessibilityText: String {
        var parts = ["剩余上下文 \(SessionMetrics.tokenText(metrics.remainingTokens)) token"]
        if let cache = SessionMetrics.cacheText(metrics.cacheHitRate) {
            parts.append("缓存命中 \(cache)")
        }
        if let rate = SessionMetrics.rateText(speed) {
            parts.append(rate)
        }
        return parts.joined(separator: "，")
    }
}

// MARK: - 用量明细

struct SessionStatsSheet: View {

    let metrics: SessionMetrics
    let liveTokensPerSecond: Double?

    @Environment(\.dismiss) private var dismiss

    private var used: Int { metrics.usedTokens }
    private var usage: Usage? { metrics.lastUsage }
    private var speed: Double? { liveTokensPerSecond ?? metrics.tokensPerSecond }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            remainingBlock
            metricsRow

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

            detailRows

            Text("上下文占用 = 最近一轮请求的输入 + 输出。缓存命中与速度取最近一轮；Anthropic 兼容接口暂不返回缓存命中量，服务端未提供时这一项不显示。")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(22)
        .presentationDetents([.height(430)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground))
    }

    private var header: some View {
        HStack {
            Text("会话用量")
                .font(.system(size: 13, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.secondary)
            Spacer()
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
        }
    }

    private var remainingBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(SessionMetrics.tokenText(metrics.remainingTokens))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(metrics.isNearLimit ? Color.orange : Color.primary)

                Text("剩余")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Spacer()

                Text("已用 \(SessionMetrics.tokenText(used)) / 共 \(SessionMetrics.tokenText(metrics.contextWindow))")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }

            GeometryReader { proxy in
                let ratio = max(0, min(1, 1 - metrics.remainingRatio))
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(metrics.isNearLimit ? Color.orange : Theme.accent)
                        .frame(width: max(proxy.size.width * ratio, ratio > 0 ? 3 : 0))
                }
            }
            .frame(height: 4)
        }
    }

    private var metricsRow: some View {
        HStack(spacing: 8) {
            metricTile(title: "缓存命中",
                       value: SessionMetrics.cacheText(metrics.cacheHitRate) ?? "—")
            metricTile(title: "生成速度",
                       value: SessionMetrics.rateText(speed) ?? "—")
            metricTile(title: "本轮输出",
                       value: usage.map { SessionMetrics.tokenText($0.outputTokens) } ?? "—")
        }
    }

    private func metricTile(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
    }

    private var detailRows: some View {
        VStack(spacing: 10) {
            row("模型", ModelCatalog.displayName(for: metrics.model))
            if let usage {
                row("本轮输入", SessionMetrics.tokenText(usage.totalInputTokens))
                row("其中缓存命中", SessionMetrics.tokenText(usage.cacheReadTokens))
                if usage.cacheCreationTokens > 0 {
                    row("写入缓存", SessionMetrics.tokenText(usage.cacheCreationTokens))
                }
                row("本轮输出", SessionMetrics.tokenText(usage.outputTokens))
                if usage.thinkingTokens > 0 {
                    row("其中思考", SessionMetrics.tokenText(usage.thinkingTokens))
                }
            }
            row("上下文窗口", SessionMetrics.tokenText(metrics.contextWindow))
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 12.5, weight: .medium))
                .monospacedDigit()
        }
    }
}
