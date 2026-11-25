# 界面方向探索

四个界面方向的首屏，跑在真实模拟器里，用同一段对话内容拍下来对比。

打开 [compare.html](compare.html) 看对比页（图片在 `shots/web/`）。

## 四个方向

| 代号 | 名称 | 骨架 |
|---|---|---|
| `paper` | 墨纸 · 研究阅读台 | 顶部会话标签条 + 620 正文 + 285 边注，宋体正文 |
| `floating` | 浮岛 · 极简对话 | 无侧栏，历史是浮层，底部悬浮输入条。**这套已按原样落进正式代码**，这里的静态存档留作对比 |
| `desk` | 台面 · 工作台 | 三栏 232 / 528 / 272，右栏是本轮上下文与费用 |
| `cards` | 卡片 · 对话卡片流 | 一轮一卡，左侧问题轴 |

## 在模拟器里切方向

`DS_UI_VARIANT` 环境变量决定启动时渲染哪一套；不传时走正式的 `RootView`。

```bash
./Scripts/build.sh
env SIMCTL_CHILD_DS_UI_VARIANT=paper xcrun simctl launch \
  9C061938-493B-4BB4-BF5D-56EA001E774D com.ruakiu.ipadds
```

四套一起重拍：

```bash
./Scripts/explore-shots.sh
```

## 文件

- `Sources/Explore/` —— 分派入口、共用演示数据、四个方向的视图
- `Sources/UI/Markdown/MarkdownView.swift` —— 新增可选参数 `serif` / `bodySize` / `surface`，默认行为不变
- `Sources/App/DSApp.swift` —— 入口从 `RootView()` 换成 `ExploreRoot()`，无环境变量时行为相同

探索代码只做静态首屏演示，没有接 `ChatViewModel`。选定方向后需要把选中那套接回真实的流式数据。
