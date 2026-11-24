import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var chatViewModel = ChatViewModel()
    @State private var selectedID: UUID?
    @State private var compactPath: [UUID] = []

    @Query(sort: \StoredConversation.updatedAt, order: .reverse)
    private var conversations: [StoredConversation]

    var body: some View {
        Group {
            if sizeClass == .regular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .tint(Theme.accent)
        .task {
            // 启动时打开最近一条会话
            if let first = conversations.first, chatViewModel.currentConversation == nil {
                selectedID = first.id
                chatViewModel.load(first)
            }
        }
    }

    // MARK: - iPad

    private var regularLayout: some View {
        NavigationSplitView {
            ConversationSidebar(
                conversations: conversations,
                selection: $selectedID,
                onNew: startNew,
                onDelete: delete
            )
            .navigationSplitViewColumnWidth(min: 260, ideal: 300, max: 380)
        } detail: {
            NavigationStack {
                ChatView(viewModel: chatViewModel)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selectedID) { _, newValue in
            guard let newValue,
                  let conversation = conversations.first(where: { $0.id == newValue }),
                  conversation.id != chatViewModel.currentConversation?.id else { return }
            chatViewModel.load(conversation)
        }
    }

    // MARK: - iPhone

    private var compactLayout: some View {
        NavigationStack(path: $compactPath) {
            ConversationList(
                conversations: conversations,
                onSelect: { conversation in
                    chatViewModel.load(conversation)
                    compactPath = [conversation.id]
                },
                onNew: {
                    startNew()
                    compactPath = []
                },
                onDelete: delete
            )
            .navigationDestination(for: UUID.self) { _ in
                ChatView(viewModel: chatViewModel)
            }
        }
    }

    // MARK: - 动作

    private func startNew() {
        selectedID = nil
        compactPath = []
        chatViewModel.startNew()
    }

    private func delete(_ conversation: StoredConversation) {
        if chatViewModel.currentConversation?.id == conversation.id {
            chatViewModel.startNew()
            selectedID = nil
        }
        ConversationStore.shared.delete(conversation)
    }
}

/// 窄屏下的会话列表页。
struct ConversationList: View {
    var conversations: [StoredConversation]
    var onSelect: (StoredConversation) -> Void
    var onNew: () -> Void
    var onDelete: (StoredConversation) -> Void

    var body: some View {
        List {
            ForEach(conversations) { conversation in
                Button {
                    onSelect(conversation)
                } label: {
                    row(conversation)
                }
                .buttonStyle(.plain)
                .swipeActions {
                    Button(role: .destructive) {
                        onDelete(conversation)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
            }
            if conversations.isEmpty {
                Text("还没有对话")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowSeparator(.hidden)
                    .padding(.top, 40)
            }
        }
        .listStyle(.plain)
        .navigationTitle("对话")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNew) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建对话")
            }
        }
    }

    private func row(_ conversation: StoredConversation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(preview(conversation))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private func preview(_ conversation: StoredConversation) -> String {
        conversation.sortedMessages.last?.plainText ?? "空对话"
    }
}
