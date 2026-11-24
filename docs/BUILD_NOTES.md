# 构建与环境笔记

记录本机踩过的坑，避免重复排查。

## 实测环境

| 项 | 值 |
|---|---|
| macOS | 27.2.1 / arm64 |
| Xcode | 27.2 (27B52) |
| iOS SDK | 27.2（真机 + 模拟器） |
| 模拟器 runtime | iOS 27.2 (24B8117) 与 (24B91016s) 两份 |
| 工程格式 | objectVersion 77，手写 pbxproj |

## 三个必须绕过的沙盒限制

DSH 的 workspace-write 沙盒和 Xcode 工具链有三处冲突，都已解决并固化在工程或脚本里。

| 现象 | 根因 | 解法 |
|---|---|---|
| `Unable to create log store directory ... You don't have permission` | xcodebuild 默认把 DerivedData 写到 `~/Library/Developer`，在工作区外 | 命令加 `-derivedDataPath .build/DerivedData` |
| `Operation not permitted` 写 `/var/folders/.../C/clang/ModuleCache` | 沙盒不让写系统临时目录 | 导出 `TMPDIR` 与 `CLANG_MODULE_CACHE_PATH` 到 `.build/` |
| `external macro implementation type 'SwiftUIMacros.StateMacro' could not be found ... produced malformed response` 伴随 `sandbox-exec: sandbox_apply: Operation not permitted` | Swift 编译器用 `sandbox-exec` 隔离宏插件进程，沙盒里不能再套沙盒 | `OTHER_SWIFT_FLAGS = -disable-sandbox`（已写入 pbxproj 的 Debug/Release） |

这三条常一起出现。宏展开失败后错误会伪装成语法错误，例如 `cannot use mutating member on immutable value: 'self' is immutable`——真实原因是 `@State` 没展开。看到 `swift-plugin-server produced malformed response` 就直接查上面三条，别去改业务代码。

## 构建与截图

```bash
./Scripts/build.sh                      # 编译到 iPad 模拟器
./Scripts/shot.sh <udid> <输出路径>      # 安装、启动、截图
```

两个模拟器 UDID：

| 设备 | UDID |
|---|---|
| iPhone 16 Pro | `F07ADD5C-2F69-4851-A64E-0A8358CA3F0D` |
| iPad Pro 13 M4 | `9C061938-493B-4BB4-BF5D-56EA001E774D` |

## 截图钩子

`simctl` 不能模拟点击，用启动环境变量控制初始界面状态。变量名必须带 `SIMCTL_CHILD_` 前缀，否则传不进被测 App。

| 变量 | 作用 |
|---|---|
| `DS_START_IN_CHAT=1` | 窄屏直接进对话页，跳过会话列表 |
| `DS_EXPAND_THINKING=1` | 所有思考块默认展开 |

```bash
env SIMCTL_CHILD_DS_START_IN_CHAT=1 xcrun simctl launch <udid> com.ruakiu.ipadds
xcrun simctl ui <udid> appearance dark      # 切深色
xcrun simctl io <udid> screenshot out.png
```

## Xcode 27 没有 Simulator.app GUI

`/Applications/Xcode.app/Contents/Developer/Applications/` 目录不存在，`mdfind com.apple.iphonesimulator` 也无结果。模拟器只能 headless 运行，`simctl io screenshot` 取 framebuffer。

后果：**命令行无法旋转模拟器屏幕**。横屏截图需要真机，或以后找到新的 GUI 入口。

## 工程文件说明

pbxproj 手写，用 `PBXFileSystemSynchronizedRootGroup` 指向 `Sources` 目录。在 `Sources/` 下新增 `.swift` 文件会被自动纳入编译，不需要改工程文件。

根目录的 `project.yml` 是 XcodeGen 配置，当前**没有使用**：brew 安装因 `/opt/homebrew/Cellar` 权限失败，GitHub 直连下载 release 超时。保留它作为工程结构的声明，等网络条件允许时可用 `xcodegen generate` 重建工程。

## 横屏截图：headless 模拟器做不到

Xcode 27 把 `Simulator.app` 从 `Contents/Developer/Applications/` 移除了，替代品是 `Contents/Applications/DeviceHub.app`（bundle id `com.apple.dt.Devices`），它只做设备管理，没有模拟器画面和旋转功能。结果是模拟器只能 headless 跑，`simctl io screenshot` 拿到的永远是物理竖屏的 framebuffer（2064×2752）。

验证过的四条路，全部走不通：

| 尝试 | 结果 |
|---|---|
| `simctl ui` | 只支持 appearance / increase_contrast / content_size，没有方向 |
| `simctl io screenConfig geometry 2752x2064` | `No mode found that supports size 2752x2064`，iPad 屏幕只有竖屏一个 mode |
| UI 测试里 `XCUIDevice.shared.orientation = .landscapeLeft` | framebuffer 确实变成 2752×2064，但 UIKit 不重排；把图转正后和竖屏截图一模一样，说明只旋转了像素 |
| `Info.plist` 只声明横屏方向 | App 依然按竖屏渲染，framebuffer 仍是 2064×2752 |

另外，UI 测试本身需要提权才能跑：`xcodebuild test` 要创建伪终端与模拟器通信，默认沙盒下报 `Pseudo Terminal Setup Error / Operation not permitted`。用 `danger-full-access` 重试可以跑通，但跑通了也拿不到横屏布局（见上表第三条）。

**结论**：横屏布局只能在 Xcode GUI 里跑模拟器手动旋转，或者上真机看。App 本身支持横屏（Info.plist 声明了四个方向，`RootView` 用 `horizontalSizeClass` 分支），横竖屏在 iPad 上都命中 `regular`，走同一套双栏布局，差别只是正文区可用宽度：竖屏 1032−300=732pt，横屏 1376−300=1076pt，而正文最大宽度固定 720pt，所以横屏的实际变化是两侧留白从 6pt 变成 178pt。
