# iPad-DS

Swift 原生 iPhone / iPad 通用 DeepSeek 客户端，自用。

**接手先读 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)** —— 项目目标、当前进度、开发日志、下一步都在这份文件里，读完就能知道从哪里继续。

其余文档：

| 文件 | 什么时候看 |
|---|---|
| [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) | 第一次接手，或想知道现在做到哪了 |
| [docs/TECH_PLAN.md](docs/TECH_PLAN.md) | 要改架构、加功能、查协议字段映射 |
| [docs/BUILD_NOTES.md](docs/BUILD_NOTES.md) | 编译报奇怪的错、截图失败、环境问题 |

快速跑起来：

```bash
./Scripts/build.sh
./Scripts/shot.sh 9C061938-493B-4BB4-BF5D-56EA001E774D shots/out.png
```

模拟器 UDID：iPad Pro 13 M4 = `9C061938-493B-4BB4-BF5D-56EA001E774D`，iPhone 16 Pro = `F07ADD5C-2F69-4851-A64E-0A8358CA3F0D`。
