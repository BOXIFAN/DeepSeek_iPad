import SwiftUI

// MARK: - 系统提示词

struct SystemPromptView: View {
    @AppStorage("systemPrompt") private var prompt = ""

    @FocusState private var editing: Bool

    private var characterCount: Int {
        prompt.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    var body: some View {
        Form {
            Section {
                TextEditor(text: $prompt)
                    .font(.system(size: 15))
                    .lineSpacing(4)
                    .frame(minHeight: 260)
                    .focused($editing)
                    .scrollContentBackground(.hidden)
            } header: {
                Text("默认提示词")
            } footer: {
                Text("每次请求都会作为 `system` 发给模型，位置在所有对话之前。留空表示不发送。写身份、语气、输出格式这类长期生效的要求比较合适。")
            }

            Section {
                HStack {
                    Text("字数")
                    Spacer()
                    Text(characterCount == 0 ? "空" : "\(characterCount)")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !prompt.isEmpty {
                    Button("清空", role: .destructive) {
                        prompt = ""
                    }
                }
            } footer: {
                Text("提示词会占用上下文，太长会挤掉对话可用的部分。")
            }
        }
        .navigationTitle("系统提示词")
        .navigationBarTitleDisplayMode(.inline)
    }
}
