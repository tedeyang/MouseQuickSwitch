# MouseQuickSwitch 使用教程

<img src="Assets/AppIcon.png" alt="MouseQuickSwitch 图标" width="128">

MouseQuickSwitch 是 macOS 菜单栏工具，可把罗技 M585 的一个侧键设为 **切换最近使用的应用（⌘Tab）** 或 **打开指定应用**。适用于 macOS 13 及更新版本的 Apple silicon 和 Intel Mac。

## 1. 安装并启动

目前提供[未公证的预览版 DMG](https://github.com/tedeyang/MouseQuickSwitch/releases/tag/v0.3.1-preview.1)。打开 DMG，把 MouseQuickSwitch.app 拖到“应用程序”，再从“应用程序”启动。它只显示在菜单栏，不显示在 Dock。

如果 macOS 阻止预览版启动，在“系统设置 → 隐私与安全性”找到被阻止的应用并选择允许，然后重新打开。预览版供测试使用；当前没有经过 Developer ID 签名和 Apple 公证的正式安装包。

首次启动后，点击菜单栏中的鼠标图标。按菜单提示授予 **辅助功能** 权限；如果仍提示无法监听鼠标，再到“系统设置 → 隐私与安全性 → 输入监控”允许 MouseQuickSwitch，并退出、重新打开应用。重新构建预览版后，macOS 可能要求再次授权。

## 2. 录制侧键

1. 点击菜单栏鼠标图标，选择 **Record Side Button**。
2. 按一下要使用的 M585 侧键。菜单中的 **Recorded button** 会显示录制结果。
3. 如果录错，重新选择 **Record Side Button** 再按一次；要放弃录制，选择 **Cancel Recording**。

## 3. 选择按键动作

**切换应用：** 在 **On Button Press** 下选择 **Switch Between Apps (⌘Tab)**。连续按侧键，可在最近两个应用之间切换。

**打开固定应用：** 选择 **Open Selected Application**，再点 **Select Application…** 选取一个 `.app`。菜单中的 **Target** 会显示所选应用。每次按侧键，程序会启动或切到该应用。

确认 **Mapping Enabled** 前有勾选。此时被映射的侧键原本的前进或后退动作会被拦截。

## 4. 暂停、恢复与退出

- 再次点击 **Mapping Enabled** 可暂停或恢复映射；暂停期间侧键执行原本的动作。
- 选择 **Quit MouseQuickSwitch** 可退出，侧键恢复原本的动作。
- 按键、动作和目标应用会保存在本机，下次启动继续使用。

## 遇到问题

| 现象 | 处理方法 |
| --- | --- |
| 菜单显示权限不足，或按键没有反应 | 在“系统设置 → 隐私与安全性”检查辅助功能和输入监控权限，重新启动应用，再尝试录制。 |
| 按键已录制，但没有打开应用 | 检查 **Mapping Enabled** 是否勾选、是否选了 **Open Selected Application**，以及 **Target** 是否为所需应用。 |
| 其他鼠标的侧键也触发了映射 | 程序只能识别鼠标按钮编号，不能区分鼠标型号；同编号的按键也会触发。 |
| M585 的设备切换键无法录制 | Easy-Switch 设备切换键和只发送厂商专有 HID 事件的按键不受支持。 |

从旧版 mouseQuick 或 MousePlus 升级时，首次启动会迁移已保存的设置；仍需为 MouseQuickSwitch 单独授予权限。

## 从源码构建

安装 Xcode 或 Xcode Command Line Tools 后，在仓库目录运行：

```sh
./scripts/build-app.sh
open build/MouseQuickSwitch.app
```

要生成本地测试 DMG，运行 `./scripts/package-dmg.sh`。需要发布正式 DMG 时，先配置 Developer ID Application 证书和 `notarytool` 钥匙串凭据，再运行：

```sh
CODESIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' \
NOTARY_PROFILE='mousequickswitch' ./scripts/package-dmg.sh
```

脚本只在 Apple 接受公证并成功附加票据后生成正式文件。
