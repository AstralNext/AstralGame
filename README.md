# Astral Game

Flutter 游戏联机客户端（Windows / Linux / Android）。

## 构建

```bash
flutter pub get
flutter run -d windows
```

Rust 核心已用 flutter_rust_bridge 内化到本仓：
- `rust/`：Rust crate（`rust_lib_astral_game`）
- `rust_builder/`：本地构建插件（cargokit）
- `lib/src/rust/`：FRB 自动生成的绑定（业务代码直接 import 这些生成文件）

改动 Rust 后重新生成绑定：`flutter_rust_bridge_codegen generate`。

CI：`.github/workflows/build.yml`（含 Windows 安装包）。

## Linux 安装

Arch 用户最省事的方式：Release 里会附带一个 Arch 包，一条命令装（pacman 原生支持 URL，yay 也能 `yay -U <url>`）：

```bash
# 把 <版本> 换成 Release 里的实际版本号，例如 1.5.1
sudo pacman -U https://github.com/AstralNext/AstralGame/releases/latest/download/astral-game-bin-<版本>-1-x86_64.pkg.tar.zst
```

包会把程序装到 `/opt/astral-game`，并自动补上建虚拟网卡所需的 `cap_net_admin` / `cap_net_raw`；
打包与系统集成的细节见 [packaging/aur](packaging/aur)。

其它发行版 / 不想装包：下载 Release 里的 `astral-game-<版本>-linux-x64.tar.gz` 解压直接运行，
首次启动会提示一次「立即授权」来补网络权限。

## 游戏规则 / 封面

规则 JSON 写法见 [docs/gamerules.md](docs/gamerules.md)。

运行时先读本地 `assets/games/rules.json`，再读旁边的 `gamerules/`（仅本机测试，不入库；有 JSON 则不拉线上），否则拉 `https://astral.fan/gamerules.json`。

可选：用 `tool/fetch_steamgriddb_covers.dart` 拉封面后上传到 CDN，并在线上 JSON 里写网络路径。

