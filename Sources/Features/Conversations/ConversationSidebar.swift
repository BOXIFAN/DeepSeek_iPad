import SwiftUI

struct ConversationSidebar: View {
    @Binding var selection: UUID?

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(Conversation.samples) { conversation in
                    row(conversation)
                        .tag(conversation.id)
                }
            } header: {
                Text("最近")
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("对话")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建对话")
            }
            ToolbarItem(placement: .bottomBar) {
                Button {
                } label: {
                    Label("设置", systemImage: "gearshape")
                        .font(.footnote)
                }
            }
        }
    }

    private func row(_ conversation: Conversation) -> some View {
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
