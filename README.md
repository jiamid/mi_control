# MiControlApp

macOS 菜单栏应用：连接 **小米蓝牙遥控器 2 Pro（RC003）**，支持：

- 系统听写（按住麦克风 → 转文字并粘贴）
- 自定义按键映射与短宏
- 拦截遥控器麦克风 F5，避免误触快捷键

仅支持 macOS 11+，仅支持 RC003。

## 下载

当前版本 **0.3.0**：[MiControlApp-0.3.0.dmg](https://github.com/jiamid/mi_control/releases/download/v0.3.0/MiControlApp-0.3.0.dmg)

全部版本见 [Releases](https://github.com/jiamid/mi_control/releases)。

这个安装包没有 Apple 开发者签名。从浏览器下载后，macOS 会拦截第一次打开：

1. 打开 DMG，把 `MiControlApp.app` 拖进「应用程序」。
2. 双击一次。若提示无法验证开发者或「已损坏」，点「完成」，不要移到废纸篓。
3. 打开「系统设置 → 隐私与安全性」，拉到最下面，点「仍要打开」，再输入开机密码。

若没有「仍要打开」，或仍然提示已损坏，在终端执行：

```bash
xattr -dr com.apple.quarantine /Applications/MiControlApp.app
open /Applications/MiControlApp.app
```

每次安装新的未签名版本后，辅助功能和输入监控通常需要重新勾选。

## 构建与安装

```bash
./scripts/build-app.sh
open /Applications/MiControlApp.app
```

## 权限

请在「系统设置 → 隐私与安全性」中为 `/Applications/MiControlApp.app` 勾选：

- 辅助功能
- 输入监控
- 语音识别
- 蓝牙

## 许可

GPL-3.0-only。详见 `LICENSE`、`COPYRIGHT`、`THIRD_PARTY_NOTICES.md`。
