import SwiftUI

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selection: UUID? = Conversation.samples.first?.id
    @State private var chatViewModel = ChatViewModel()

    /// 供命令行截图用：DS_START_IN_CHAT=1 时窄屏直接进对话页。
    @State private var compactPath: [UUID] = ProcessInfo.processInfo.environment["DS_START_IN_CHAT"] == "1"
        ? [Conversation.samples[0].id]
        : []

    var body: some View {
        content
            .tint(Theme.accent)
    }

    private var content: some View {
        Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
    }

    /// iPad 全屏与 iPhone 横屏：会话栏 + 对话双栏。
    private var regularLayout: some View {
        NavigationSplitView {
            ConversationSidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            NavigationStack {
                ChatView(conversation: current, viewModel: chatViewModel)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    /// iPhone 竖屏：单列推入式。
    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            ConversationList(selection: $selection)
                .navigationDestination(for: UUID.self) { id in
                    ChatView(conversation: Conversation.samples.first { $0.id == id }, viewModel: chatViewModel)
                }
        }
    }

    private var current: Conversation? {
        Conversation.samples.first { $0.id == selection }
    }
}

/// 窄屏下的会话列表页。
struct ConversationList: View {
    @Binding var selection: UUID?

    var body: some View {
        List {
            ForEach(Conversation.samples) { conversation in
                NavigationLink(value: conversation.id) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conversation.title)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text(conversation.preview)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .listStyle(.plain)
        .navigationTitle("对话")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建对话")
            }
        }
    }
}
