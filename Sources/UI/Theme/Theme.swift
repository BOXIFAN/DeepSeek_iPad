import SwiftUI

enum Theme {
    /// DeepSeek 品牌蓝，取 #4D6BFE。
    static let accent = Color(red: 77.0 / 255.0, green: 107.0 / 255.0, blue: 254.0 / 255.0)

    /// 对话正文最大宽度。iPad 13 寸横屏有 1376pt，不限宽会让行太长、读起来累。
    static let contentMaxWidth: CGFloat = 720

    static let cardCorner: CGFloat = 12

    /// 块间距。贴近官方后收紧到 12，比初版 14 更紧凑。
    static let blockSpacing: CGFloat = 12

    /// 用户气泡底色。官方的灰比 secondarySystemBackground 更淡一点。
    static let userBubble = Color(uiColor: .secondarySystemBackground).opacity(0.7)
}
