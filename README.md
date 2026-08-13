# Astral Game

Flutter 游戏联机客户端（Windows / Linux / Android）。

## 构建

```bash
flutter pub upgrade astral_rust_core vpn_service_plugin
flutter run -d windows
```

CI：`.github/workflows/build.yml`（含 Windows 安装包）。

## 游戏规则 / 封面

运行时从 `https://astral.fan/gamerules.json` 拉取完整目录与封面 URL。  
本地 `assets/games/rules.json` 作离线回退（含尚未上 CDN 的游戏）。

可选：用 `tool/fetch_steamgriddb_covers.dart` 拉封面后上传到 CDN，并在线上 JSON 里写网络路径。

