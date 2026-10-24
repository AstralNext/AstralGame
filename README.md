# Astral Game

Astral Game 是一款面向玩家的跨平台游戏联机工具。创建房间并邀请好友，即可像在同一个局域网内一样一起游玩，无需繁琐的网络设置。

支持 Windows、Linux 与 Android。

## 主要功能

- **快速组网**：创建房间、邀请好友，几步之内开始游戏。
- **跨平台互通**：不同系统的玩家可以在同一房间内一起游玩。
- **游戏适配**：针对常见局域网联机游戏做了适配，减少手动配置。
- **房间分享**：通过分享码或邀请链接，好友可一键加入。
- **游戏库**：查看游戏封面与信息，收藏常玩的游戏。
- **网络状态**：实时查看延迟与连接质量，并支持测速。
- **界面主题**：提供多种主题，可按喜好自由切换。
- **版本更新**：新版本发布后可直接在客户端内完成更新。

## 下载

请前往 [Releases](https://github.com/AstralNext/AstralGame/releases) 页面下载最新版本。

| 平台 | 下载文件 | 说明 |
| --- | --- | --- |
| Windows | `astral-game-<版本>-windows-x64-setup.exe` | 安装版，推荐使用 |
| Windows | `astral-game-<版本>-windows-x64.zip` | 免安装版，解压即用 |
| Linux | `astral-game-<版本>-linux-x64.tar.gz` | 通用版本 |
| Arch Linux | `astral-game-bin-<版本>-1-x86_64.pkg.tar.zst` | Arch 软件包 |
| Android | `astral-game-<版本>-android-arm64.apk` | 安装包 |

## 安装与启动

### Windows

下载安装包后双击，按提示完成安装即可。免安装版解压到任意目录后运行主程序。

### Linux

Arch 用户可直接安装 Release 中的软件包（将 `<版本>` 替换为实际版本号）：

```bash
sudo pacman -U https://github.com/AstralNext/AstralGame/releases/latest/download/astral-game-bin-<版本>-1-x86_64.pkg.tar.zst
```

其他发行版下载 `tar.gz` 压缩包，解压后直接运行。首次启动时客户端会提示授予网络权限，按提示完成操作即可正常使用。

### Android

下载 APK 安装，首次启动时按提示授予必要权限。

## 快速开始

1. 打开客户端，完善昵称与头像等个人信息。
2. 创建房间，并选择本次要游玩的游戏。
3. 将邀请链接或分享码发送给好友。
4. 好友加入房间后，启动游戏即可开始联机。

## 反馈与支持

- 使用中遇到问题或有功能建议，欢迎通过 [Issues](https://github.com/AstralNext/AstralGame/issues) 反馈。
- 如需适配新的游戏，可选择「游戏适配」模板提交申请。

更多信息请访问官方网站：[astral.fan](https://astral.fan)

## 开源致谢

本项目的联机核心基于 [EasyTier](https://github.com/EasyTier/EasyTier) 构建。EasyTier 采用 LGPL-3.0 许可证发布，本项目使用其修改分支 `main-astral`（[ldoubil/EasyTier](https://github.com/ldoubil/EasyTier/tree/main-astral)），相关修改同样遵循 LGPL-3.0。

其他第三方组件的版权与许可信息见 [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md)。

## 许可证

本项目基于 [GNU General Public License v3.0](LICENSE) 发布。

依据 GPL-3.0 第 7 条，本项目附加以下条款：任何修改版本或衍生作品在分发时，必须在显著位置保留原项目名称「Astral Game」及项目地址 <https://github.com/AstralNext/AstralGame>，不得移除、隐藏或替换；修改版本还应以合理方式标明其与原版的区别。完整说明见 [ADDITIONAL-TERMS.md](ADDITIONAL-TERMS.md)。
