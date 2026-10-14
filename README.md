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

## 游戏规则 / 封面

规则 JSON 写法见 [docs/gamerules.md](docs/gamerules.md)。

运行时先读本地 `assets/games/rules.json`，再读旁边的 `gamerules/`（仅本机测试，不入库；有 JSON 则不拉线上），否则拉 `https://astral.fan/gamerules.json`。

可选：用 `tool/fetch_steamgriddb_covers.dart` 拉封面后上传到 CDN，并在线上 JSON 里写网络路径。

