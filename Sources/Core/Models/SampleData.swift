import Foundation

/// 预览用样例数据。
///
/// 刻意按真实 API 的块顺序构造：思考 → 搜索 → 结果 → 再思考 → 打开网页 →
/// 带引用的正文 → 代码块 → 表格。这样截图才能反映真实回复的排版压力。
/// 其中引用的价格与规格数字取自 DeepSeek 定价页，不是编的。
enum SampleData {

    static let userQuestion = "总结一下 DeepSeek 现在的模型能力和价格，顺便给个请求示例。"

    static let toolUseID = "srvtoolu_s_00_b2baebaf"

    static let assistantBlocks: [ContentBlock] = [
        .thinking(
            id: "blk-thinking-1",
            text: "用户想了解两件事：模型规格和价格，还有一个请求示例。规格和价格最好查一下官方定价页，避免记错数字。示例可以直接给 JSON，比 curl 更好读。",
            duration: 9
        ),

        .toolCall(
            id: toolUseID,
            name: "deepseek_web_search",
            kind: .search,
            action: .search(queries: ["DeepSeek 模型价格", "deepseek-flash 上下文长度"])
        ),

        .searchResults(
            id: "blk-search-1",
            toolUseID: toolUseID,
            kind: .search,
            results: [
                SearchResult(
                    title: "模型 & 价格 | DeepSeek API Docs",
                    url: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/",
                    snippet: "deepseek-flash 上下文长度 1M，输出长度最大 384K，支持图像理解。缓存命中输入 0.02 元/百万 tokens，未命中 1 元。",
                    siteName: "DeepSeek",
                    siteIcon: nil,
                    pageAge: "2026-11-13"
                ),
                SearchResult(
                    title: "DeepSeek 开放平台文档",
                    url: "https://api-docs.deepseek.com/zh-cn/",
                    snippet: "提供 Chat Completions、Responses、Messages 三种协议，支持 Tool Calls、JSON Output 与对话前缀续写。",
                    siteName: "DeepSeek",
                    siteIcon: nil,
                    pageAge: "2026-11-20"
                ),
                SearchResult(
                    title: "构建 Chatbot — 联网搜索与文件输入",
                    url: "https://api-docs.deepseek.com/zh-cn/guides/build_a_chatbot/",
                    snippet: "搜索与阅读链接由服务端完成，客户端只需展示返回的内容块，并在下一轮原样回传。",
                    siteName: "DeepSeek",
                    siteIcon: nil,
                    pageAge: "2026-11-18"
                )
            ],
            errorCode: nil
        ),

        .thinking(
            id: "blk-thinking-2",
            text: "官方定价页最权威，数字都在上面。打开它确认一下缓存命中价，这个概念容易混。",
            duration: 4
        ),

        .toolCall(
            id: "srvtoolu_ds_02_7e545ef1",
            name: "deepseek_web_search",
            kind: .deepSearch,
            action: .openPage(url: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/")
        ),

        .fetchedPage(
            id: "blk-fetch-1",
            toolUseID: "srvtoolu_ds_02_7e545ef1",
            kind: .deepSearch,
            page: FetchedPage(
                url: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/",
                title: "模型 & 价格",
                publishedAt: "2026-11-18",
                errorCode: nil
            )
        ),

        .text(
            id: "blk-text-1",
            text: """
            现在的主力是两个模型[1]：

            **`deepseek-flash`** 便宜、快，支持图像理解，1M 上下文配 384K 输出上限。日常对话、长文档、截图提问都够用。

            **`deepseek-v4-pro`** 更贵，强在复杂推理，不支持图像理解。

            价格按北京时间分时段，高峰是工作日 9:00–12:00 与 14:00–18:00，其余时段（含周末和法定节假日）打五折[2]。
            """,
            citations: [
                Citation(
                    url: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/",
                    title: "模型 & 价格",
                    citedText: "deepseek-flash 上下文长度 1M"
                ),
                Citation(
                    url: "https://api-docs.deepseek.com/zh-cn/quick_start/pricing/",
                    title: "模型 & 价格",
                    citedText: "空闲时段价格为高峰时段价格的一半"
                )
            ]
        ),

        .text(
            id: "blk-text-2",
            text: """
            ### 规格与价格对照

            | 项目 | deepseek-flash | deepseek-v4-pro |
            | --- | --- | --- |
            | 上下文长度 | 1M | 1M |
            | 输出长度 | 384K | 384K |
            | 图像理解 | 支持 | 不支持 |
            | 缓存命中输入 | 0.02 元 | 0.15 元 |
            | 缓存未命中输入 | 1 元 | 4.5 元 |
            | 输出 | 4 元 | 13.5 元 |

            价格为空闲时段，单位是每百万 tokens。

            ### 请求示例

            ```json
            {
              "model": "deepseek-flash",
              "stream": true,
              "thinking": { "type": "enabled" },
              "messages": [
                { "role": "user", "content": "你好" }
              ]
            }
            ```

            把这段发到 `POST /anthropic/v1/messages` 就能拿到流式响应。开启 `thinking` 后，`message_start` 之后会立刻打开一个 `thinking` 块，如果模型先去搜索，这个块可能是空的。
            """,
            citations: []
        )
    ]
}
