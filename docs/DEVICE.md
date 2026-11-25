# 上真机

模拟器验不了的东西（相册权限、键盘、手势手感、横屏）都要在真机上过一遍。这份文件记的是从零到跑起来的步骤，以及几个必踩的坑。

## 前置

| 项 | 要求 |
|---|---|
| Mac | 已装 Xcode 27（本机 `xcodebuild -version` 是 27.2） |
| 设备 | iPad / iPhone，iOS 18 以上（工程 deployment target 18.0） |
| 账号 | 免费 Apple ID 即可，不需要 $99 开发者账号 |
| 连接 | 数据线，第一次必须插线 |

免费账号的限制：签名 7 天有效，到期重签；同时最多 3 个 App。这个项目两个都不影响。

## 第一次装

1. **信任电脑**：插上设备和 Mac，设备弹「要信任此电脑吗」，点信任并输入密码。

2. **Xcode 里打开工程**

   ```bash
   open /Users/ruakiu/Desktop/iPad-DS/iPadDS.xcodeproj
   ```

3. **设置签名 Team**

   左侧选 `iPadDS` target → `Signing & Capabilities`：

   - 勾上 `Automatically manage signing`
   - Team 选你的 Apple ID（第一次需要在 Xcode → Settings → Accounts 里添加账号）
   - Bundle Identifier 保持 `com.ruakiu.ipadds`；如果提示已被占用，改成 `com.ruakiu.ipadds.dev` 之类

4. **选设备并运行**

   顶部设备下拉里选你的 iPad / iPhone，按 ⌘R。

   第一次会编译几分钟（真机架构要重新编译）。

5. **在设备上信任开发者**

   如果 App 装好了但打不开，提示「未受信任的开发者」：

   设备 → 设置 → 通用 → VPN 与设备管理 → 开发者 App → 选你的 Apple ID → 信任。

6. **填 API Key**

   Keychain 不跨设备，模拟器里那把不会跟过来。打开 App → 左上角 ☰ → 设置 → 填 Key → 保存。

## 一键安装脚本

签名配好之后，插上设备跑这一条就够：

```bash
./Scripts/install-device.sh
```

脚本依次做四件事：自动找已连接的物理设备 → 检查开发者模式 → 检查签名证书 → 构建、安装、启动。任何一步不满足会停下来提示具体怎么修，不用去 Xcode 里翻。

指定设备时传 UDID：

```bash
./Scripts/install-device.sh 00008132-000829DC1AA1801C
```

## 命令行装（手动版）

脚本不适用时（比如要把产物拷到别的机器），可以拆开跑：

```bash
cd /Users/ruakiu/Desktop/iPad-DS

# 1. 列出已连接设备，拿 identifier
xcrun devicectl list devices

# 2. 编译到真机（需要先把 Team 写进工程，见上一节）
./Scripts/build.sh "platform=iOS,id=<设备 UDID>"

# 3. 安装
xcrun devicectl device install app \
  --device <设备 UDID> \
  .build/DerivedData/Build/Products/Debug-iphoneos/iPadDS.app
```

`build.sh` 默认走模拟器；传 destination 覆盖即可。

## 到真机上要补验的

模拟器是 headless 的，下面这些只能真机看：

| 项 | 怎么验 |
|---|---|
| 相册权限 | 全屏看图 → 长按 → 保存到相册，第一次会弹权限 |
| 图片选择器 | 输入条左侧 photo 图标，选多张、看压缩进度 |
| 拖动手势 | 待发图片长按拖动换顺序 |
| 下拉关闭 | 全屏看图时往下拖，超过 140pt 松手 |
| 双击缩放 | 全屏看图双击，再双击还原 |
| 键盘 | 输入框随键盘上移，中文输入法候选栏不挡输入框 |
| 横屏 | 转屏后正文宽度变化、抽屉仍从左侧滑出 |
| 引用角标 | 点正文里的 `[1]`，看弹层 |

## 7 天后过期

免费签名到期时 App 会打不开（提示无法验证）。重新插线，Xcode ⌘R 一次就续上了。

## 常见错误

| 报错 | 原因 | 处理 |
|---|---|---|
| `No signing certificate "iOS Development" found` | 没选 Team 或账号没加 | Xcode → Settings → Accounts 加 Apple ID |
| `The operation couldn't be completed. Unable to launch...` | 设备没信任开发者 | 见上面第 5 步 |
| `Bundle identifier is not available` | 这个 id 被别人占了 | 改成 `com.ruakiu.ipadds.<你的名字>` |
| `Developer Mode disabled` | iOS 16+ 要开开发者模式 | 设备 → 设置 → 隐私与安全性 → 开发者模式 → 打开后**重启设备** |
| `SecurityAgent 要求输入密码` | 第一次签名会让钥匙串授权 | 输 Mac 登录密码，选「始终允许」 |
| 编译卡在 `Copying ...` | 设备线接触不良 | 换线或重插 |

## 与本机沙盒的关系

Xcode 里跑不受 DSH 沙盒限制。命令行构建时 `Scripts/build.sh` 已经把 `TMPDIR` 和 `CLANG_MODULE_CACHE_PATH` 指到 `.build/`，原因见 `BUILD_NOTES.md`。
