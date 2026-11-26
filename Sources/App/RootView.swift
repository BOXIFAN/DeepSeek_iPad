import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// 浮岛骨架的根视图：对话即首页，历史收进浮层，左下角常驻余额卡片。
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase

    @State private var chat = ChatViewModel()
    @State private var balance = BalanceStore.shared
    @State private var selectedID: UUID?
    @State private var showHistory = false
    @State private var showSettings = ProcessInfo.processInfo.environment["DS_SHOW_SETTINGS"] == "1"
    @State private var showBalanceSheet = ProcessInfo.processInfo.environment["DS_SHOW_BALANCE"] == "1"
    @State private var showSessionStats = ProcessInfo.processInfo.environment["DS_SHOW_USAGE"] == "1"
    @State private var showSplash = ProcessInfo.processInfo.environment["DS_SKIP_SPLASH"] != "1"
    @State private var historySearch = ""
    @State private var renamingID: UUID?
    @State private var renameDraft = ""
    @State private var draft = ""
    @State private var pendingImages: [MessageImage] = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showPhotoPicker = false
    @State private var imageProgress: (done: Int, total: Int)?
    @State private var draggingImageID: UUID?
    @State private var pendingDocuments: [PendingDocument] = []
    @State private var showFilePicker = false
    @State private var documentProgress: (done: Int, total: Int)?
    @State private var documentError: String?
    @State private var gallery: GalleryPresentation?
    @State private var windowWidth: CGFloat = 0
    @FocusState private var composerFocused: Bool

    @AppStorage("model") private var model = "deepseek-flash"
    @AppStorage("keepDocumentLayout") private var keepDocumentLayout = false
    @AppStorage("systemPrompt") private var systemPrompt = ""
    @AppStorage(ThinkingEffort.storageKey) private var effortRaw = ThinkingEffort.standard.rawValue
    @AppStorage("defaultSearch") private var search = false

    @Query(sort: \StoredConversation.updatedAt, order: .reverse)
    private var conversations: [StoredConversation]

    @Query(sort: \StoredSkill.createdAt, order: .forward)
    private var skills: [StoredSkill]

    private var isRegular: Bool { sizeClass == .regular }
    private var effort: ThinkingEffort { ThinkingEffort(rawValue: effortRaw) ?? .standard }
    private var showsCornerBalance: Bool { isRegular && windowWidth >= 980 }

    var body: some View {
        ZStack {
            FloatingBackground()

            VStack(spacing: 0) {
                FloatingChatBody(
                    viewModel: chat,
                    onSuggestion: { suggestion in
                        draft = suggestion
                        composerFocused = true
                    },
                    onOpenSettings: { showSettings = true },
                    onOpenImage: { images, index in
                        gallery = GalleryPresentation(images: images, index: index)
                    },
                    onRetry: retryLastRound
                )
                .safeAreaInset(edge: .top, spacing: 0) {
                    topBar
                }
                composerArea
            }
        }
        .overlay(alignment: .bottomLeading) {
            if showsCornerBalance {
                BalanceCard(
                    store: balance,
                    onSettings: { showSettings = true },
                    onDetails: { showBalanceSheet = true }
                )
                .padding(.leading, 22)
                .padding(.bottom, 24)
            }
        }
        .overlay { historyDrawer }
        .sheet(isPresented: phoneHistoryBinding) { phoneHistorySheet }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .fullScreenCover(item: $gallery) { presentation in
            ImageGalleryView(images: presentation.images, initialIndex: presentation.index)
        }
        .sheet(isPresented: $showBalanceSheet) {
            BalanceSheet(store: balance) {
                showBalanceSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showSettings = true
                }
            }
        }
        .sheet(isPresented: $showSessionStats) {
            SessionStatsSheet(metrics: chat.metrics,
                              liveTokensPerSecond: chat.liveTokensPerSecond)
        }
        .alert("重命名会话", isPresented: renameBinding) {
            TextField("会话名称", text: $renameDraft)
            Button("取消", role: .cancel) { renamingID = nil }
            Button("保存") { commitRename() }
        } message: {
            Text("只改本机的显示名，不影响对话内容与服务端标题。")
        }
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            windowWidth = width
        }
        .task {
            bootstrap()
            // 开屏是唯一的长动效：固定展示约 1 秒再淡出，盖住首帧加载与布局
            guard ProcessInfo.processInfo.environment["DS_SPLASH_ALWAYS"] != "1" else { return }
            try? await Task.sleep(for: .milliseconds(950))
            withAnimation(.easeInOut(duration: 0.32)) {
                showSplash = false
            }
        }
        .photosPicker(
            isPresented: $showPhotoPicker,
            selection: $photoItems,
            maxSelectionCount: ImagePipeline.maxCount,
            matching: .images
        )
        .onChange(of: photoItems) { _, _ in
            loadPickedImages()
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: DocumentKind.allowedTypes,
            allowsMultipleSelection: true
        ) { result in
            handlePickedFiles(result)
        }
        .onChange(of: chat.isStreaming) { _, streaming in
            if !streaming {
                balance.refreshIfStale(within: 10)
                // 调试钩子：失败后自动点一次「重试」，用来验证重试链路
                if ProcessInfo.processInfo.environment["DS_AUTO_RETRY"] == "1",
                   chat.canRetryLastRound {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        retryLastRound()
                    }
                }
            }
        }
        // 从后台回来、切分屏、解锁后都补一次；这是真机上余额卡片停在旧值的主因
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                balance.refreshIfStale(within: 30)
            }
        }
        .overlay {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .tint(Theme.accent)
    }

    // MARK: - 背景

    private struct FloatingBackground: View {
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            LinearGradient(
                colors: scheme == .dark
                    ? [Color(red: 0.055, green: 0.059, blue: 0.078),
                       Color(red: 0.024, green: 0.024, blue: 0.031),
                       Color(red: 0.024, green: 0.024, blue: 0.031)]
                    : [Color(red: 0.973, green: 0.976, blue: 1.0),
                       .white,
                       .white],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
        }
    }

    // MARK: - 顶栏

    private var topBar: some View {
        HStack(spacing: 14) {
            circleButton(icon: "line.3.horizontal", tint: Color.primary.opacity(0.75)) {
                openHistory()
            }
            .accessibilityLabel("会话历史")

            Spacer(minLength: 8)

            VStack(spacing: 1) {
                Text(headerTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(headerSubtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if !sessionImages.isEmpty {
                    circleButton(icon: "photo.on.rectangle", tint: Color.primary.opacity(0.75)) {
                        gallery = GalleryPresentation(images: sessionImages, index: 0)
                    }
                    .accessibilityLabel("查看对话里的 \(sessionImages.count) 张图")
                }

                circleButton(icon: "square.and.pencil", tint: Theme.accent) {
                    startNew()
                }
                .accessibilityLabel("新建对话")
            }
        }
        .padding(.horizontal, isRegular ? 26 : 18)
        .padding(.top, isRegular ? 12 : 4)
        .padding(.bottom, 8)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 0.5)
        }
    }

    private var circleFill: Color {
        colorScheme == .dark
            ? Color(uiColor: .secondarySystemBackground)
            : Color(uiColor: .systemBackground)
    }

    /// 当前会话里的全部图片，按消息顺序。
    private var sessionImages: [MessageImage] {
        chat.messages.flatMap(\.images)
    }

    private var headerTitle: String {
        if chat.messages.isEmpty { return "鲸语" }
        if let generated = chat.generatedTitle, !generated.isEmpty {
            return generated
        }
        return chat.conversationTitle
    }

    private var headerSubtitle: String {
        var parts = [model]
        if effort.isEnabled { parts.append("思考 · \(effort.title)") }
        if search { parts.append("联网") }
        return parts.joined(separator: " · ")
    }

    private func circleButton(icon: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(
                    Circle()
                        .fill(circleFill)
                        .shadow(color: .black.opacity(0.07), radius: 12, y: 5)
                )
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - 历史数据

    private var historyItems: [HistoryItem] {
        let query = historySearch.trimmingCharacters(in: .whitespacesAndNewlines)

        if ProcessInfo.processInfo.environment["DS_DEMO_HISTORY"] == "1" {
            let demo = Self.demoHistory
            guard !query.isEmpty else { return demo }
            return demo.filter {
                $0.title.localizedCaseInsensitiveContains(query)
                    || $0.preview.localizedCaseInsensitiveContains(query)
            }
        }

        let matched = query.isEmpty ? conversations : conversations.filter { conversation in
            conversation.title.localizedCaseInsensitiveContains(query)
                || conversation.sortedMessages.contains {
                    $0.plainText.localizedCaseInsensitiveContains(query)
                }
        }

        return matched.map { conversation in
            let preview = conversation.sortedMessages.last?.plainText ?? ""
            // 标题命中就显示原来的预览；只有正文命中才换成命中的那句
            let titleHit = query.isEmpty || conversation.title.localizedCaseInsensitiveContains(query)
            return HistoryItem(
                id: conversation.id,
                title: conversation.title,
                preview: preview,
                snippet: titleHit ? nil : Self.snippet(in: conversation, matching: query),
                updatedAt: conversation.updatedAt,
                isCurrent: conversation.id == selectedID
            )
        }
    }

    /// 搜索命中时截一段正文，标题对不上但正文命中的会话也能定位。
    private static func snippet(in conversation: StoredConversation,
                                matching query: String) -> String? {
        for message in conversation.sortedMessages {
            let text = message.plainText
            guard let range = text.range(of: query, options: .caseInsensitive) else { continue }
            let start = text.index(range.lowerBound, offsetBy: -16, limitedBy: text.startIndex) ?? text.startIndex
            let end = text.index(range.upperBound, offsetBy: 36, limitedBy: text.endIndex) ?? text.endIndex
            let prefix = start > text.startIndex ? "…" : ""
            let suffix = end < text.endIndex ? "…" : ""
            // 列表行只显示一行，片段里的换行会把命中的词顶到下一行
            return (prefix + text[start..<end] + suffix)
                .replacingOccurrences(of: "\n", with: " ")
        }
        return nil
    }

    private static var demoHistory: [HistoryItem] {
        let now = Date()
        let calendar = Calendar.current
        func daysAgo(_ days: Int, hour: Int, minute: Int) -> Date {
            let base = calendar.date(byAdding: .day, value: -days, to: now) ?? now
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }
        return [
            HistoryItem(id: UUID(), title: "DeepSeek 模型能力与价格",
                        preview: "现在的主力是两个模型，deepseek-flash…",
                        updatedAt: daysAgo(0, hour: 9, minute: 41), isCurrent: true),
            HistoryItem(id: UUID(), title: "Swift 并发里的 actor 隔离",
                        preview: "在 Swift 6 严格并发模式下，MainActor…",
                        updatedAt: daysAgo(0, hour: 9, minute: 12)),
            HistoryItem(id: UUID(), title: "把长文档拆成章节再总结",
                        preview: "先按一级标题切分，每段单独总结，最后…",
                        updatedAt: daysAgo(1, hour: 21, minute: 30)),
            HistoryItem(id: UUID(), title: "SQLite 索引选择",
                        preview: "复合索引的列顺序决定了能命中哪些查询…",
                        updatedAt: daysAgo(1, hour: 15, minute: 4)),
            HistoryItem(id: UUID(), title: "Keychain 存 API Key 的几种做法",
                        preview: "kSecAttrAccessibleAfterFirstUnlock…",
                        updatedAt: daysAgo(4, hour: 11, minute: 48)),
        ]
    }

    // MARK: - 输入区

    private var composerWidth: CGFloat? {
        isRegular ? 640 : nil
    }

    private var composerArea: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                ThinkingEffortChip(effort: Binding(
                    get: { effort },
                    set: { effortRaw = $0.rawValue }
                ))
                FloatingModeChip(title: "联网搜索", icon: "globe.asia.australia", isOn: $search)
                SkillPickerChip(skills: skills) { skill in
                    toggleSkill(skill)
                }
                Spacer(minLength: 0)

                if !isRegular {
                    BalancePill(store: balance) {
                        showBalanceSheet = true
                    }
                }
            }
            .frame(maxWidth: composerWidth)

            if !pendingDocuments.isEmpty {
                pendingDocumentArea
                    .frame(maxWidth: composerWidth)
            }

            if let progress = imageProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text(progress.done == progress.total
                         ? "正在处理最后一张…"
                         : "正在处理 \(progress.done)/\(progress.total) 张")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: composerWidth)
            }

            if !pendingImages.isEmpty {
                pendingImageStrip
                    .frame(maxWidth: composerWidth)
            }

            FloatingComposer(
                text: $draft,
                isStreaming: chat.isStreaming,
                hasImages: !pendingImages.isEmpty,
                hasDocuments: !pendingDocuments.isEmpty,
                isUploadingDocuments: isUploadingDocuments,
                hasFailedDocuments: pendingDocuments.contains(where: { $0.errorText != nil }),
                focus: $composerFocused,
                onSend: send,
                onStop: chat.stop,
                onPickImage: { showPhotoPicker = true },
                onPickFile: { showFilePicker = true }
            )
            .frame(maxWidth: composerWidth)

            SessionMetricsBar(
                metrics: chat.metrics,
                liveTokensPerSecond: chat.liveTokensPerSecond
            ) {
                showSessionStats = true
            }
            .frame(maxWidth: composerWidth)
            .padding(.top, -3)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, isRegular ? 32 : 16)
        .padding(.top, 6)
        .padding(.bottom, isRegular ? 22 : 10)
    }

    // MARK: - 历史浮层

    @ViewBuilder
    private var historyDrawer: some View {
        ZStack(alignment: .leading) {
            if isRegular {
                Color.black
                    .opacity(showHistory ? 0.26 : 0)
                    .ignoresSafeArea()
                    .allowsHitTesting(showHistory)
                    .onTapGesture { closeHistory() }

                HistoryPanel(
                    items: historyItems,
                    searchText: $historySearch,
                    balance: balance,
                    onSelect: { select($0) },
                    onDelete: { delete($0) },
                    onRename: { startRename($0) },
                    onNew: { startNew() },
                    onClose: { closeHistory() },
                    onSettings: {
                        closeHistory()
                        showSettings = true
                    }
                )
                .frame(width: 320)
                .frame(maxHeight: .infinity)
                .background(
                    Color(uiColor: .systemBackground)
                        .ignoresSafeArea()
                        .shadow(color: .black.opacity(0.16), radius: 30, x: 10)
                )
                .offset(x: showHistory ? 0 : -360)
                .allowsHitTesting(showHistory)
            }
        }
        .animation(drawerAnimation, value: showHistory)
    }

    /// 有文档正在上传/解析，发送要等它们就绪。
    private var isUploadingDocuments: Bool {
        pendingDocuments.contains(where: \.isUploading)
    }

    /// 待发文件区：横向文件卡 + 解析方式开关 + 错误行。
    private var pendingDocumentArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(pendingDocuments) { item in
                        PendingDocumentChip(
                            item: item,
                            onRemove: { removeDocument(item.id) },
                            onRetry: { retryDocument(item.id) }
                        )
                    }
                }
                .padding(.vertical, 6)
            }

            if let progress = documentProgress, progress.total > 0 {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(progress.done == progress.total
                         ? "正在等最后一个文件解析完…"
                         : "正在上传 \(progress.done)/\(progress.total) 个文件…")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
            }

            if pendingDocuments.contains(where: { $0.kind == .parsed }) {
                Button {
                    toggleDocumentLayout()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: keepDocumentLayout ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 11, weight: .medium))
                        Text("保留文档里的图")
                            .font(.system(size: 11.5))
                        Text("图表会裁出来交给模型，按页计费更高")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                    .foregroundStyle(keepDocumentLayout ? Theme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
            }

            if let failure = pendingDocuments.compactMap(\.errorText).first {
                Text("\(failure) · 点文件卡重试")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let documentError {
                Text(documentError)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.orange)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 待发送图片的预览条。
    private var pendingImageStrip: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ForEach(pendingImages) { image in
                    ZStack(alignment: .topTrailing) {
                        if let ui = image.uiImage {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 62, height: 62)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }

                        Button {
                            pendingImages.removeAll { $0.id == image.id }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 18, height: 18)
                                .background(Circle().fill(Color.black.opacity(0.55)))
                        }
                        .buttonStyle(.plain)
                        .offset(x: 6, y: -6)
                    }
                    .onDrag {
                        draggingImageID = image.id
                        return NSItemProvider(object: image.id.uuidString as NSString)
                    }
                    .onDrop(
                        of: [.text],
                        delegate: ImageCellDropDelegate(
                            target: image,
                            items: $pendingImages,
                            draggingID: $draggingImageID
                        )
                    )
                    .opacity(draggingImageID == image.id ? 0.45 : 1)
                }

                if pendingImages.count < ImagePipeline.maxCount {
                    Button {
                        showPhotoPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 62, height: 62)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color.primary.opacity(0.045))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 0)
            }

            if model == "deepseek-v4-pro" {
                Label("deepseek-v4-pro 不读取图片，发送前请切到 flash", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func loadPickedImages() {
        guard !photoItems.isEmpty else { return }
        let items = photoItems
        photoItems = []
        Task {
            imageProgress = (0, items.count)
            var loaded: [MessageImage] = []
            for (offset, item) in items.enumerated() {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    // 解码 + 缩放 + 编码放到后台，10MB 的 HEIC 在主线程会卡一秒
                    let image = await Task.detached(priority: .userInitiated) {
                        ImagePipeline.make(from: data)
                    }.value
                    if let image {
                        loaded.append(image)
                    }
                }
                imageProgress = (offset + 1, items.count)
            }
            let room = max(0, ImagePipeline.maxCount - pendingImages.count)
            pendingImages.append(contentsOf: loaded.prefix(room))
            imageProgress = nil
        }
    }

    /// 抽屉进出的曲线。用 spring 是为了开头有加速段，位移不会像 easeOut 那样一上来就满速。
    /// `DS_SLOW_ANIM=1` 时整体放慢到约 4 秒，方便逐帧截图核对。
    private var drawerAnimation: Animation {
        let base = Animation.spring(response: 0.30, dampingFraction: 0.86)
        let slow = ProcessInfo.processInfo.environment["DS_SLOW_ANIM"] == "1"
        return slow ? base.speed(0.075) : base
    }

    private var phoneHistoryBinding: Binding<Bool> {
        Binding(
            get: { !isRegular && showHistory },
            set: { showHistory = $0 }
        )
    }

    private var phoneHistorySheet: some View {
        HistoryPanel(
            items: historyItems,
            searchText: $historySearch,
            balance: balance,
            onSelect: { select($0) },
            onDelete: { delete($0) },
            onRename: { startRename($0) },
            onNew: { startNew() },
            onClose: { showHistory = false },
            onSettings: {
                showHistory = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                    showSettings = true
                }
            }
        )
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 动作

    private func bootstrap() {
        let environment = ProcessInfo.processInfo.environment

        if environment["DS_SELFTEST"] == "1" {
            SelfTest.writeReport()
        }

        if let query = environment["DS_HISTORY_SEARCH"], !query.isEmpty {
            // 截图钩子：预填搜索词
            historySearch = query
        }

        // 截图钩子：直接弹出第一条的重命名弹窗
        if environment["DS_RENAME_ALERT"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                if let first = historyItems.first {
                    startRename(first)
                }
            }
        }

        // 端到端验证改名：给最近一条会话改名（不经过弹窗）
        if let newName = environment["DS_RENAME_TO"], !newName.isEmpty {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if let conversation = conversations.first {
                    ConversationStore.shared.rename(conversation, to: newName)
                    if chat.currentConversation?.id == conversation.id {
                        chat.applyManualTitle(newName)
                    }
                }
            }
        }

        if environment["DS_SHOW_HISTORY"] == "1" {
            // 延迟一下再打开，录像/连续截图才有机会抓到抽屉进入的过程
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                openHistory()
                if let query = environment["DS_HISTORY_SEARCH"], !query.isEmpty {
                    historySearch = query
                }
            }
        }

        SkillInstaller.installMissing()

        if environment["DS_ENABLE_SKILLS"] == "1" {
            let context = ConversationStore.shared.context
            let stored = (try? context.fetch(FetchDescriptor<StoredSkill>())) ?? []
            stored.forEach { $0.isEnabled = true }
            try? context.save()
        }

        if environment["DS_PRINT_SYSTEM"] == "1" {
            let stored = (try? ConversationStore.shared.context.fetch(FetchDescriptor<StoredSkill>())) ?? []
            let assembled = PromptComposer.system(defaultPrompt: systemPrompt, skills: stored) ?? "<nil>"
            // headless 模拟器拿不到 stdout，写到沙盒里方便脚本读
            let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("system-prompt.txt")
            try? assembled.write(to: url, atomically: true, encoding: .utf8)
        }

        if environment["DS_BALANCE_DEMO"] == "1" {
            balance.applyDemoSnapshot()
        } else {
            // 周期刷新 + 网络恢复监听交给 store，视图只把两个时机（启动、回前台）递过去
            balance.start()
            balance.refreshIfStale(within: 5)
        }

        if environment["DS_IMAGE_PROGRESS"] == "1" {
            imageProgress = (1, 3)
        }

        if environment["DS_PENDING_IMAGE"] == "1",
           let image = SelfTest.makeDemoImage() {
            pendingImages = [image]
        }

        // 截图钩子：待发文件条的各状态
        switch environment["DS_PENDING_DOCUMENT"] {
        case "1":
            pendingDocuments = [Self.demoPendingDocument(filename: "2026Q3-财报.pdf", phase: nil)]
        case "failed":
            pendingDocuments = [Self.demoPendingDocument(filename: "2026Q3-财报.pdf",
                                                        phase: .failed("解析结果不完整，重试一次"))]
        case "uploading":
            pendingDocuments = [Self.demoPendingDocument(filename: "2026Q3-财报.pdf",
                                                        phase: .uploading)]
        case "multi":
            pendingDocuments = [
                Self.demoPendingDocument(filename: "2026Q3-财报.pdf", phase: nil),
                Self.demoPendingDocument(filename: "合同扫描件.pdf", phase: .uploading)
            ]
        default:
            break
        }

        if environment["DS_DEMO_THREAD"] == "1" {
            chat.loadDemoThread(includeDocument: environment["DS_DEMO_DOCUMENT"] == "1")
            return
        }
        if environment["DS_START_EMPTY"] != "1",
           let first = conversations.first,
           chat.currentConversation == nil {
            selectedID = first.id
            chat.load(first)
        }

        // 调试钩子：启动即发一条，用来验端到端链路（配合 DS_API_BASE 指到本地 mock）
        if environment["DS_SHOW_GALLERY"] == "1" {
            let titles = ["ONE", "TWO", "THREE"]
            let images = titles.enumerated().compactMap { offset, title in
                SelfTest.makeDemoImage(text: "PICTURE \(title)", hue: CGFloat(offset) * 0.33)
            }
            if !images.isEmpty {
                gallery = GalleryPresentation(images: images, index: 0)
            }
        }

        if let name = environment["DS_UPLOAD_FILE"], !name.isEmpty {
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            if name == "demo", let demo = SelfTest.makeDemoPDF() {
                let url = directory.appendingPathComponent(demo.filename)
                try? demo.data.write(to: url)
                ingestDocuments([url])
            } else {
                ingestDocuments([directory.appendingPathComponent(name)])
            }
        }

        if let prompt = environment["DS_AUTO_PROMPT"],
           !prompt.isEmpty,
           chat.messages.isEmpty,
           environment["DS_SEND_AFTER_UPLOAD"] != "1" {
            var images: [MessageImage] = []
            if environment["DS_DEMO_IMAGE"] == "1",
               let image = SelfTest.makeDemoImage() {
                images = [image]
            }
            sendText(prompt, images: images)
        }

        // 验证「中断后重试」：流式中途自动停一次
        if let raw = environment["DS_AUTO_STOP_MS"], let delay = Int(raw), delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay)) {
                chat.stop()
            }
        }

        // 验证「流式中切会话」：旧任务收尾不能把用量或消息写进新会话
        if environment["DS_SWITCH_DURING_STREAM"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                startNew()
            }
        }
    }

    private static func demoPendingDocument(filename: String,
                                            phase: PendingDocument.Phase?) -> PendingDocument {
        let document = MessageDocument(fileID: "file-api-demo",
                                       filename: filename,
                                       byteCount: 2_480_000,
                                       purpose: .textRecognition)
        return PendingDocument(filename: document.filename,
                               byteCount: document.byteCount,
                               kind: .parsed,
                               purpose: document.purpose,
                               data: Data(),
                               phase: phase ?? .ready(document))
    }

    // MARK: - 文件

    private func handlePickedFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            documentError = "选择文件失败：\(error.localizedDescription)"
        case .success(let urls):
            ingestDocuments(urls)
        }
    }

    private func ingestDocuments(_ urls: [URL]) {
        documentError = nil
        let remaining = DocumentKind.maxPerMessage - pendingDocuments.count
        guard remaining > 0 else {
            documentError = "一轮最多 \(DocumentKind.maxPerMessage) 个文件"
            return
        }

        var accepted: [PendingDocument] = []
        for url in urls.prefix(remaining) {
            let name = url.lastPathComponent
            if DocumentKind.isImage(url) {
                documentError = "图片请用左侧照片按钮"
                continue
            }
            guard let kind = DocumentKind.kind(for: url) else {
                documentError = DocumentError.unsupported(name).errorDescription
                continue
            }

            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            guard let data = try? Data(contentsOf: url) else {
                documentError = DocumentError.unreadable(name).errorDescription
                continue
            }
            let limit = DocumentKind.maxBytes(for: kind)
            guard data.count <= limit else {
                documentError = DocumentError.tooLarge(name, limit).errorDescription
                continue
            }

            accepted.append(PendingDocument(
                filename: name,
                byteCount: data.count,
                kind: kind,
                purpose: DocumentKind.purpose(for: kind, keepLayout: keepDocumentLayout),
                data: data
            ))
        }

        guard !accepted.isEmpty else { return }
        pendingDocuments.append(contentsOf: accepted)
        uploadDocuments(accepted.map(\.id))
    }

    /// 串行上传：进度好读，也避免同账号并发解析排队。
    private func uploadDocuments(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        documentError = nil
        documentProgress = (0, ids.count)
        Task {
            var done = 0
            for id in ids {
                await uploadOne(id)
                done += 1
                documentProgress = (done, ids.count)
            }
            documentProgress = nil

            // 验证钩子：文件就绪后自动带附件发一条
            if ProcessInfo.processInfo.environment["DS_SEND_AFTER_UPLOAD"] == "1",
               let prompt = ProcessInfo.processInfo.environment["DS_AUTO_PROMPT"],
               !prompt.isEmpty,
               draft.isEmpty {
                draft = prompt
                send()
            }
        }
    }

    @MainActor
    private func uploadOne(_ id: UUID) async {
        guard let index = pendingDocuments.firstIndex(where: { $0.id == id }) else { return }
        let item = pendingDocuments[index]
        guard let key = KeychainStore.read(), !key.isEmpty else {
            pendingDocuments[index].phase = .failed("还没填 API Key")
            return
        }

        do {
            let document = try await FileUploader.shared.upload(
                data: item.data,
                filename: item.filename,
                purpose: item.purpose,
                apiKey: key
            )
            if let current = pendingDocuments.firstIndex(where: { $0.id == id }) {
                pendingDocuments[current].phase = .ready(document)
            }
        } catch {
            if let current = pendingDocuments.firstIndex(where: { $0.id == id }) {
                pendingDocuments[current].phase = .failed(error.localizedDescription)
            }
        }
    }

    private func removeDocument(_ id: UUID) {
        pendingDocuments.removeAll { $0.id == id }
        if pendingDocuments.isEmpty {
            documentProgress = nil
        }
    }

    private func retryDocument(_ id: UUID) {
        guard let index = pendingDocuments.firstIndex(where: { $0.id == id }) else { return }
        pendingDocuments[index].phase = .uploading
        uploadDocuments([id])
    }

    /// 切换「保留文档里的图」。purpose 在上传时定死，已经传过的 PDF / Word 要重传。
    private func toggleDocumentLayout() {
        keepDocumentLayout.toggle()
        let newPurpose = DocumentKind.purpose(for: .parsed, keepLayout: keepDocumentLayout)
        var reupload: [UUID] = []
        for index in pendingDocuments.indices where pendingDocuments[index].kind == .parsed {
            pendingDocuments[index].purpose = newPurpose
            pendingDocuments[index].phase = .uploading
            reupload.append(pendingDocuments[index].id)
        }
        uploadDocuments(reupload)
    }

    private func send() {
        guard !isUploadingDocuments else {
            documentError = "文件还在上传，等一下就绪"
            return
        }
        guard !pendingDocuments.contains(where: { $0.errorText != nil }) else {
            documentError = "有文件没传成功，点文件重试或删掉再发"
            return
        }

        let documents = pendingDocuments.compactMap(\.document)
        let text = draft
        let images = pendingImages
        draft = ""
        pendingImages = []
        pendingDocuments = []
        documentProgress = nil
        documentError = nil
        composerFocused = false
        sendText(text, images: images, documents: documents)
    }

    private var currentOptions: ChatClient.Options {
        ChatClient.Options(
            model: model,
            thinking: effort.isEnabled,
            thinkingEffort: effort.apiValue,
            webSearch: search,
            generateTitle: true,
            systemPrompt: PromptComposer.system(defaultPrompt: systemPrompt, skills: skills)
        )
    }

    private func sendText(_ text: String,
                          images: [MessageImage] = [],
                          documents: [MessageDocument] = []) {
        chat.send(text,
                  images: images,
                  documents: documents,
                  apiKey: KeychainStore.read() ?? "",
                  options: currentOptions)
    }

    /// 重试最后一轮：失败的请求、被中断的回复都走这里。
    private func retryLastRound() {
        chat.retryLastRound(apiKey: KeychainStore.read() ?? "", options: currentOptions)
    }

    private func select(_ item: HistoryItem) {
        guard let conversation = conversations.first(where: { $0.id == item.id }) else { return }
        chat.load(conversation)
        selectedID = conversation.id
        closeHistory()
        composerFocused = false
    }

    private func startNew() {
        chat.startNew()
        selectedID = nil
        draft = ""
        closeHistory()
        composerFocused = true
    }

    private func toggleSkill(_ skill: StoredSkill) {
        skill.isEnabled.toggle()
        skill.updatedAt = Date()
        try? ConversationStore.shared.context.save()
    }

    private func openHistory() {
        historySearch = ""
        withAnimation(drawerAnimation) {
            showHistory = true
        }
    }

    private func closeHistory() {
        historySearch = ""
        withAnimation(drawerAnimation) {
            showHistory = false
        }
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renamingID != nil },
            set: { if !$0 { renamingID = nil } }
        )
    }

    private func startRename(_ item: HistoryItem) {
        renameDraft = item.title
        renamingID = item.id
    }

    private func commitRename() {
        guard let id = renamingID else { return }
        let title = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        defer { renamingID = nil }
        guard !title.isEmpty,
              let conversation = conversations.first(where: { $0.id == id }) else { return }
        ConversationStore.shared.rename(conversation, to: title)
        if chat.currentConversation?.id == id {
            chat.applyManualTitle(title)
        }
    }

    private func delete(_ item: HistoryItem) {
        guard let conversation = conversations.first(where: { $0.id == item.id }) else { return }
        if chat.currentConversation?.id == conversation.id {
            chat.startNew()
            selectedID = nil
        }
        ConversationStore.shared.delete(conversation)
    }
}
