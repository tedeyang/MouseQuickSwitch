# MouseQuickSwitch

<img src="Assets/AppIcon.png" alt="MouseQuickSwitch app icon" width="128">

MouseQuickSwitch 是一个专为 **macOS + 罗技 M585 鼠标**制作的轻量菜单栏工具。把一个侧键设为应用切换快捷键：按一下模拟 **⌘Tab**，在最近两个应用之间来回切换；也可以选择“打开指定应用”，让侧键每次都切到同一个程序。

A small macOS menu bar utility for the Logitech M585 mouse. Map a side button to Command-Tab or to a selected application.

## 功能

- 直接点击 M585 侧键录制按键，无需手动查找按钮编号。
- 在 **切换应用（⌘Tab）** 和 **打开指定应用** 两种模式之间选择。
- 拦截被映射的侧键，避免同时触发原有的前进或后退操作；暂停或退出后恢复原行为。
- 设置保存在本机的 macOS 用户偏好中；无网络请求、遥测或鼠标驱动。

## 安装与构建

应用支持 Apple silicon 和 Intel Mac，要求 macOS 13 或更新版本。正式面向普通用户分发时，需要提供经过 Developer ID 签名和 Apple 公证的 DMG：下载后打开镜像，将 MouseQuickSwitch.app 拖入 **Applications**，再从“应用程序”中启动。

当前仓库尚无 Developer ID 证书，因此没有可供普通用户直接安装的正式发行包。[未公证的预览版 DMG](https://github.com/tedeyang/MouseQuickSwitch/releases/tag/v0.3.1-preview.1) 可供测试，但下载后可能需要在“系统设置 → 隐私与安全性”中手动允许启动。开发者也可以使用 Xcode 或 Xcode Command Line Tools 构建本机预览：

```sh
./scripts/build-app.sh
open build/MouseQuickSwitch.app
./scripts/package-dmg.sh  # 仅生成未公证的本地预览 DMG
```

取得 Developer ID Application 证书并在本机配置 `notarytool` 钥匙串凭据后，可以用以下命令生成公证 DMG。脚本只有在 Apple 接受公证并成功附加票据后，才会产生没有 `PENDING` 字样的正式文件：

```sh
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='mousequickswitch' ./scripts/package-dmg.sh
```

首次运行时，在 **系统设置 → 隐私与安全性 → 设备控制和数据访问** 中允许 MouseQuickSwitch。如果菜单提示需要鼠标输入权限，再到 **输入监控** 中允许它，然后重启应用。开发预览采用临时签名，重新构建后 macOS 可能要求重新授权。

## 使用

1. 点击菜单栏中的鼠标图标，选择 **Record Side Button**，然后按一下 M585 侧键。
2. 在 **On Button Press** 中选择 **Switch Between Apps (⌘Tab)** 或 **Open Selected Application**。
3. 若选择指定应用模式，点击 **Select Application…** 选取 `.app`。
4. 确认 **Mapping Enabled** 已勾选。

从旧版 mouseQuick 或 MousePlus 升级时，MouseQuickSwitch 会在首次启动时迁移已录制的按钮、模式和目标应用。由于应用名称和标识已变，需要为 MouseQuickSwitch 单独授权。

## 限制

标准 macOS 鼠标事件只能识别按钮编号，无法确认事件一定来自 M585；其他鼠标的同编号按键也可能触发。M585 的 Easy-Switch 设备切换按钮不在支持范围内。如果某个侧键只发送厂商专有 HID 事件，这个版本无法录制它。
