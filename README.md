# Astral Game

Flutter 游戏联机客户端（Windows / Linux / Android）。

## 构建

```bash
flutter pub get
flutter run -d windows
```

CI：`.github/workflows/build.yml`（含 Windows 安装包）。

## 游戏规则 / 封面

运行时从 `https://astral.fan/gamerules.json` 拉取完整目录与封面 URL。  
本地 `assets/games/rules.json` 只有通用「其他」作离线回退。

可选：用 `tool/fetch_steamgriddb_covers.dart` 拉封面后上传到 CDN，并在线上 JSON 里写网络路径。

