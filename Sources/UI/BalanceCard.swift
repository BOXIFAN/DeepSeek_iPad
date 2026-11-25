import SwiftUI

// MARK: - 左下角余额卡片（iPad）

struct BalanceCard: View {
    let store: BalanceStore
    var onSettings: () -> Void
    var onDetails: () -> Void

    /// 只有「没填 Key」和「余额偏低」把金额标橙。一次网络失败不该把已有数字也染成警告色。
    private var amountWarning: Bool {
        !store.hasKey || store.isLow
    }

    private var hasError: Bool {
        store.hasKey && store.errorText != nil
    }

    var body: some View {
        Button {
            // 出错时轻点就是重试，不用再点进明细里找按钮
            if store.hasKey {
                store.refresh()
            } else {
                onSettings()
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 4) {
                    Text("API 余额")
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 0)

                    if store.isLoading {
                        ProgressView()
                            .controlSize(.mini)
                    } else {
                        Image(systemName: hasError ? "exclamationmark.arrow.circlepath"
                                                   : (store.hasKey ? "arrow.clockwise" : "key"))
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(hasError ? Color.orange : Color.secondary)
                    }
                }

                Text(store.amountText)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(amountWarning ? Color.orange : Color.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Text(store.note)
                    .font(.system(size: 9.5))
                    .foregroundStyle(hasError || amountWarning ? Color.orange : Color.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(width: 150, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 15, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.07), radius: 14, y: 5)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.45).onEnded { _ in onDetails() }
        )
        .accessibilityLabel("API 余额 \(store.amountText)，\(store.note)")
        .accessibilityHint("轻点刷新余额，长按查看明细")
    }
}

// MARK: - 输入条上的余额胶囊（iPhone）

struct BalancePill: View {
    let store: BalanceStore
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle()
                    .fill(store.isLow || !store.hasKey || store.errorText != nil ? Color.orange : Color.green)
                    .frame(width: 5, height: 5)

                Text(store.amountText)
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
            .overlay(
                Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("API 余额 \(store.amountText)")
    }
}

// MARK: - 余额明细

struct BalanceSheet: View {
    let store: BalanceStore
    var onSettings: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text("API 余额")
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

            VStack(alignment: .leading, spacing: 6) {
                Text(store.amountText)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(store.isLow ? Color.orange : Color.primary)

                if let detail = store.detailText {
                    Text(detail)
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }

                Text(store.note)
                    .font(.system(size: 12.5))
                    .foregroundStyle(store.isLow || store.errorText != nil ? Color.orange : Color.secondary)
            }

            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

            HStack(spacing: 10) {
                Button {
                    store.refresh()
                } label: {
                    HStack(spacing: 6) {
                        if store.isLoading {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("刷新余额")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)

                Button {
                    dismiss()
                    onSettings()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                        Text("设置")
                    }
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.accent.opacity(0.12))
                    )
                    .foregroundStyle(Theme.accent)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .presentationBackground(Color(uiColor: .systemBackground))
    }
}
