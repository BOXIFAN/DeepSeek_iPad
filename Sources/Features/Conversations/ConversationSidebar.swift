import SwiftUI

struct ConversationSidebar: View {
    var conversations: [StoredConversation]
    @Binding var selection: UUID?
    var onNew: () -> Void
    var onDelete: (StoredConversation) -> Void

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(conversations) { conversation in
                    row(conversation)
                        .tag(conversation.id)
                        .swipeActions {
                            Button(role: .destructive) {
                                onDelete(conversation)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                }
            } header: {
                Text("最近")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("对话")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onNew) {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建对话")
            }
        }
        .overlay {
            if conversations.isEmpty {
                ContentUnavailableView {
                    Label("没有对话", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("点右上角新建")
                }
            }
        }
    }

    private func row(_ conversation: StoredConversation) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(conversation.title)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(conversation.sortedMessages.last?.plainText ?? "空对话")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
    }
}
