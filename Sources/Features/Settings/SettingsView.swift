import SwiftUI

/// 设置页。自用场景只放必要项：Key、默认模型、两个默认开关。
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage("model") private var model = "deepseek-flash"
    @AppStorage("defaultThinking") private var defaultThinking = true
    @AppStorage("defaultSearch") private var defaultSearch = false

    @State private var keyDraft = ""
    @State private var hasSavedKey = KeychainStore.hasAPIKey
    @State private var justSaved = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if hasSavedKey && !justSaved {
                        HStack {
                            Label("已保存 API Key", systemImage: "checkmark.seal.fill")
                                .foregroundStyle(Theme.accent)
                            Spacer()
                            Button("更换") {
                                hasSavedKey = false
                                keyDraft = ""
                            }
                            .font(.footnote)
                        }
                    } else {
                        SecureField("sk-...", text: $keyDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .font(.system(.body, design: .monospaced))

                        Button("保存到 Keychain") {
                            let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            if KeychainStore.save(trimmed) {
                                hasSavedKey = true
                                justSaved = true
                                keyDraft = ""
                            }
                        }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } header: {
                    Text("API Key")
                } footer: {
                    Text("Key 只保存在本机 Keychain，不会离开这台设备。到 platform.deepseek.com 创建。")
                }

                Section("模型") {
                    Picker("默认模型", selection: $model) {
                        Text("deepseek-flash").tag("deepseek-flash")
                        Text("deepseek-v4-pro").tag("deepseek-v4-pro")
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }

                Section {
                    Toggle("默认开启深度思考", isOn: $defaultThinking)
                    Toggle("默认开启联网搜索", isOn: $defaultSearch)
                } footer: {
                    Text("开启联网后，温度这类参数会被服务端忽略。")
                }

                if hasSavedKey {
                    Section {
                        Button("删除已保存的 Key", role: .destructive) {
                            KeychainStore.delete()
                            hasSavedKey = false
                            justSaved = false
                            keyDraft = ""
                        }
                    }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
