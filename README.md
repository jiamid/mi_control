# MiControlApp

macOS 菜单栏应用：连接 **小米蓝牙遥控器 2 Pro（RC003）**，支持：

- 系统听写（按住麦克风 → 转文字并粘贴）
- 自定义按键映射与短宏
- 拦截遥控器麦克风 F5，避免误触快捷键

仅支持 macOS 11+，仅支持 RC003。

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
