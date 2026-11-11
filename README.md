# mouseQuick

mouseQuick 是一个专为 **macOS + 罗技 M585 鼠标**制作的轻量菜单栏工具。把一个侧键设为应用切换快捷键：按一下模拟 **⌘Tab**，在最近两个应用之间来回切换；也可以选择“打开指定应用”，让侧键每次都切到同一个程序。

A small macOS menu bar utility for the Logitech M585 mouse. Map a side button to Command-Tab or to a selected application.

## 功能

- 直接点击 M585 侧键录制按键，无需手动查找按钮编号。
- 在 **切换应用（⌘Tab）** 和 **打开指定应用** 两种模式之间选择。
- 拦截被映射的侧键，避免同时触发原有的前进或后退操作；暂停或退出后恢复原行为。
- 设置保存在本机的 macOS 用户偏好中；无网络请求、遥测或鼠标驱动。

## 构建与运行

需要 macOS 13 或更新版本，以及 Xcode 或 Xcode Command Line Tools。

```sh
./scripts/build-app.sh
open .build/mouseQuick.app
```

首次运行时，在 **系统设置 → 隐私与安全性 → 设备控制和数据访问** 中允许 mouseQuick。如果菜单提示需要鼠标输入权限，再到 **输入监控** 中允许它，然后重启应用。构建脚本采用临时签名；重新构建后 macOS 可能要求重新授权。

## 使用

1. 点击菜单栏中的 **M+**，选择 **Record Side Button**，然后按一下 M585 侧键。
2. 在 **On Button Press** 中选择 **Switch Between Apps (⌘Tab)** 或 **Open Selected Application**。
3. 若选择指定应用模式，点击 **Select Application…** 选取 `.app`。
4. 确认 **Mapping Enabled** 已勾选。

从旧版 MousePlus 升级时，mouseQuick 会在首次启动时迁移已录制的按钮、模式和目标应用。由于应用名称和标识已变，需要为 mouseQuick 单独授权。

## 限制

标准 macOS 鼠标事件只能识别按钮编号，无法确认事件一定来自 M585；其他鼠标的同编号按键也可能触发。M585 的 Easy-Switch 设备切换按钮不在支持范围内。如果某个侧键只发送厂商专有 HID 事件，这个版本无法录制它。
