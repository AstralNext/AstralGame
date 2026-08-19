# Astral Game

Flutter 游戏联机客户端（Windows / Linux / Android）。

## 构建

```bash
flutter pub upgrade astral_rust_core vpn_service_plugin
flutter run -d windows
```

CI：`.github/workflows/build.yml`（含 Windows 安装包）。

## 游戏规则 / 封面

规则 JSON 写法见 [docs/gamerules.md](docs/gamerules.md)。

运行时先读本地 `assets/games/rules.json`，再读仓库/程序旁 `gamerules/`（有 JSON 则不拉线上），否则拉 `https://astral.fan/gamerules.json`。

可选：用 `tool/fetch_steamgriddb_covers.dart` 拉封面后上传到 CDN，并在线上 JSON 里写网络路径。

