import SwiftUI

// MARK: - 历史条目

/// 浮层用的行模型。和 SwiftData 解耦，演示数据也能直接喂进来。
struct HistoryItem: Identifiable, Equatable {
    let id: UUID
    var title: String
    var preview: String
    /// 搜索命中时给正文片段，优先于 preview 显示
    var snippet: String?
    var updatedAt: Date
    var isCurrent: Bool = false
}

// MARK: - 会话历史

/// 浮岛骨架里历史不再常驻，改成从左上角按钮拉出的浮层。
/// iPad 用左侧抽屉，iPhone 用半屏 sheet，内容同一份。
struct HistoryPanel: View {
    let items: [HistoryItem]
    @Binding var searchText: String
    var balance: BalanceStore
    var onSelect: (HistoryItem) -> Void
    var onDelete: (HistoryItem) -> Void
    var onRename: (HistoryItem) -> Void
    var onNew: () -> Void
    var onClose: () -> Void
    var onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar

            if items.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(items) { item in
                        row(item)
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets(top: 1, leading: 10, bottom: 1, trailing: 10))
                            .contentShape(Rectangle())
                            .onTapGesture { onSelect(item) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // 数组第一个排在最右：删除靠边、红色，重命名在它左侧
                                Button(role: .destructive) {
                                    onDelete(item)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                                .tint(.red)

                                Button {
                                    onRename(item)
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                .tint(Theme.accent)
                            }
                            .contextMenu {
                                Button {
                                    onRename(item)
                                } label: {
                                    Label("重命名", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    onDelete(item)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 1)
            }

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("最近")
                .font(.system(size: 17, weight: .semibold))

            Spacer()

            Button(action: onNew) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Theme.accent.opacity(0.1)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("新建对话")

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭")
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)

            TextField("搜索标题和正文", text: $searchText)
                .font(.system(size: 12.5))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空搜索")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: searchText.isEmpty ? "bubble.left.and.bubble.right" : "magnifyingglass")
                .font(.system(size: 22))
                .foregroundStyle(.tertiary)
            Text(searchText.isEmpty ? "还没有对话" : "没有匹配的会话")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func row(_ item: HistoryItem) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(item.title)
                    .font(.system(size: 13.5, weight: item.isCurrent ? .semibold : .regular))
                    .foregroundStyle(item.isCurrent ? Theme.accent : Color.primary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text(Self.timeText(item.updatedAt))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            Text(item.snippet ?? (item.preview.isEmpty ? "空对话" : item.preview))
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(item.isCurrent ? Theme.accent.opacity(0.1) : Color.clear)
        )
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 1)

            Button {
                if balance.hasKey {
                    balance.refresh()
                } else {
                    onSettings()
                }
            } label: {
                HStack(spacing: 8) {
                    Text("API 余额")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer(minLength: 4)

                    Text(balance.amountText)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(balance.isLow ? Color.orange : Color.primary)

                    if balance.isLoading {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: balance.errorText != nil
                              ? "exclamationmark.arrow.circlepath"
                              : "arrow.clockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(balance.errorText != nil ? Color.orange : Color.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: onSettings) {
                HStack(spacing: 8) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 12))
                    Text("设置")
                        .font(.system(size: 12.5))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 18)
                .padding(.top, 2)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    static func timeText(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: date)
        }
        if calendar.isDateInYesterday(date) {
            return "昨天"
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: Date())
        formatter.dateFormat = sameYear ? "M月d日" : "yyyy年M月d日"
        return formatter.string(from: date)
    }
}
