# iPad-DS

Swift 原生 iPhone / iPad 通用 DeepSeek 客户端，自用。

**接手先读 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** —— 目标、进度、开发日志、下一步都在那份文件里。

## 现在能做什么

- **对话**：SSE 流式、深度思考（关闭 / 低 / 标准 / 高四档）、联网搜索
- **图片**：选图提问、全屏查看（缩放 / 翻页 / 下拉关闭 / 长按保存或复制）
- **文件**：PDF / Word / PPT 解析（可选保留文档里的图）、文本 / 代码 / 表格 / 电子书直接读取，上传失败可重试
- **提示词**：全局 system 提示词、本地技能库、两个内置技能、Markdown 导入
- **管理**：会话持久化与历史浮层、API 余额（卡片 / 胶囊 / 明细，失败自动重试）
- **用量**：输入条下方一行显示剩余上下文、缓存命中、tok/s，点开看本轮明细

## 文档

| 文件 | 什么时候看 |
|---|---|
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | 第一次接手，或想知道现在做到哪了 |
| [docs/DESIGN.md](docs/DESIGN.md) | 改界面前看：骨架、颜色、字号、圆角、间距 |
| [docs/DEVICE.md](docs/DEVICE.md) | 上真机：签名、信任设备、7 天续签、常见报错 |
| [docs/TECH_PLAN.md](docs/TECH_PLAN.md) | 要改架构、加功能、查协议字段映射 |
| [docs/BUILD_NOTES.md](docs/BUILD_NOTES.md) | 编译报奇怪的错、截图失败、环境问题 |

## 跑起来

模拟器：

```bash
./Scripts/build.sh                  # 编译到 iPad 模拟器
./Scripts/preview-shots.sh          # 全套验收截图（21 张，双端）
./Scripts/shot.sh <UDID> shots/out.png
```

真机（先按 DEVICE.md 配好签名）：

```bash
./Scripts/install-device.sh         # 构建 + 安装 + 启动
```

依赖 `DEVELOPMENT_TEAM`，工程里已写入。免费 Apple ID 签名 7 天有效，到期重跑一次即可。

## 验证

- **离线自检**：`DS_SELFTEST=1` 启动，结果在沙盒 `Documents/selftest.txt`，当前 49 条
- **本地 mock**：`python3 Scripts/mock-server.py`，再带 `DS_API_BASE=http://127.0.0.1:8710` 启动，可离线跑通请求 → 流式 → 渲染 → 落库
- **验收截图**：`shots/redesign/`，双端 × 空态 / 对话 / 历史 / 余额 / 用量 / 文件 / 文档 / 设置 / 技能 / 深色

模拟器 UDID：iPad Pro 13 M4 = `9C061938-493B-4BB4-BF5D-56EA001E774D`，iPhone 16 Pro = `F07ADD5C-2F69-4851-A64E-0A8358CA3F0D`。
