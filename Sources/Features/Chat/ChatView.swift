import SwiftUI

struct ChatView: View {
    var conversation: Conversation?
    var viewModel: ChatViewModel

    @AppStorage("model") private var model = "deepseek-flash"
    @AppStorage("defaultThinking") private var defaultThinking = true
    @AppStorage("defaultSearch") private var defaultSearch = false

    @State private var showSettings = ProcessInfo.processInfo.environment["DS_SHOW_SETTINGS"] == "1"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if viewModel.messages.isEmpty {
                        emptyState
                    } else {
                        ForEach(viewModel.messages) { message in
                            messageView(message)
                        }
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                }
                .frame(maxWidth: Theme.contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.streamTick) {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Composer(
                isStreaming: viewModel.isStreaming,
                onSend: send,
                onStop: viewModel.stop
            )
        }
        .navigationTitle(displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("设置")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.reset()
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("新建对话")
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .onAppear(perform: autoPromptIfNeeded)
    }

    private var displayTitle: String {
        if let generated = viewModel.generatedTitle, !generated.isEmpty {
            return generated
        }
        return conversation?.title ?? "新对话"
    }

    // MARK: - 消息

    @ViewBuilder
    private func messageView(_ message: ChatViewModel.DisplayMessage) -> some View {
        switch message.role {
        case .user:
            userBubble(message.text)
        case .assistant:
            assistantBody(message)
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 48)
            Text(text)
                .font(.body)
                .lineSpacing(3)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Theme.userBubble)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func assistantBody(_ message: ChatViewModel.DisplayMessage) -> some View {
        VStack(alignment: .leading, spacing: Theme.blockSpacing) {
            ForEach(ContentBlock.grouped(message.blocks)) { block in
                BlockView(block: block)
            }

            if message.isStreaming && message.blocks.isEmpty {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在思考…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = message.errorText {
                errorBanner(error)
            }

            if !message.isStreaming && !message.blocks.isEmpty {
                actionRow
            }
        }
    }

    private func errorBanner(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionRow: some View {
        HStack(spacing: 22) {
            Button {
            } label: {
                Image(systemName: "doc.on.doc")
            }
            Button {
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            Button {
            } label: {
                Image(systemName: "hand.thumbsdown")
            }
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("DeepSeek")
                .font(.largeTitle.weight(.semibold))
            Text("在下面输入问题。可以在输入框上方打开深度思考或联网搜索。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 60)
    }

    // MARK: - 发送

    /// 调试钩子：DS_AUTO_PROMPT=文字 时启动即发一条，用于命令行验证流式链路
    private func autoPromptIfNeeded() {
        guard let prompt = ProcessInfo.processInfo.environment["DS_AUTO_PROMPT"],
              !prompt.isEmpty,
              viewModel.messages.isEmpty else { return }
        send(prompt)
    }

    private func send(_ text: String) {
        let options = ChatClient.Options(
            model: model,
            thinking: defaultThinking,
            webSearch: defaultSearch
        )
        viewModel.send(text, apiKey: KeychainStore.read() ?? "", options: options)
    }
}

// MARK: - 输入条

struct Composer: View {
    var isStreaming: Bool
    var onSend: (String) -> Void
    var onStop: () -> Void

    @AppStorage("defaultThinking") private var deepThinking = true
    @AppStorage("defaultSearch") private var webSearch = false

    @State private var text = ""
    @FocusState private var focused: Bool

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.4)

            HStack(spacing: 8) {
                chip("深度思考", icon: "brain", isOn: $deepThinking)
                chip("联网搜索", icon: "globe", isOn: $webSearch)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)

            HStack(alignment: .bottom, spacing: 10) {
                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 32, height: 32)
                        .background(Color(uiColor: .tertiarySystemFill))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加图片或文件")

                HStack(alignment: .bottom, spacing: 8) {
                    TextField("给 DeepSeek 发送消息", text: $text, axis: .vertical)
                        .font(.callout)
                        .lineLimit(1...6)
                        .focused($focused)
                        .disabled(isStreaming)

                    Button {
                        if isStreaming {
                            onStop()
                        } else {
                            onSend(text)
                            text = ""
                            focused = false
                        }
                    } label: {
                        Image(systemName: isStreaming ? "stop.fill" : "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(buttonBackground)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .disabled(!isStreaming && !canSend)
                    .accessibilityLabel(isStreaming ? "停止" : "发送")
                }
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
                .background(Color(uiColor: .secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 10)
        }
        .background {
            Color(uiColor: .systemBackground)
                .ignoresSafeArea(edges: .bottom)
        }
    }

    private var buttonBackground: Color {
        if isStreaming { return .secondary }
        return canSend ? Theme.accent : Color.secondary.opacity(0.4)
    }

    private func chip(_ title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.wrappedValue.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .medium))
                Text(title)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(isOn.wrappedValue ? Theme.accent : Color.secondary)
            .background(
                isOn.wrappedValue
                    ? Theme.accent.opacity(0.12)
                    : Color(uiColor: .tertiarySystemFill)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
