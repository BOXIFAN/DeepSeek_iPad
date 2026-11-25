import SwiftUI

@main
struct DSApp: App {

    init() {
        // 调试钩子：headless 模拟器点不了界面，用环境变量注入 Key 做端到端验证
        if let injected = ProcessInfo.processInfo.environment["DS_API_KEY"], !injected.isEmpty {
            KeychainStore.save(injected)
        }
    }

    var body: some Scene {
        WindowGroup {
            ExploreRoot()
        }
        .modelContainer(ConversationStore.shared.container)
    }
}
