# 夸克网盘自动上传（Release）

打 `v*` 标签并完成 GitHub Release 后，Actions 用夸克官方 CLI（skill zip 里的 `quark-drive.cjs`）上传 `release/` 安装包，创建永久公开分享，并（可选）更新官网 `downloads.json`。

CLI 会检测 Agent 环境。本仓库通过 `OPENCLAW_CLI=1` 识别为 openclaw，读取 `openclaw/config.json`。

## 仓库 Secrets

| Secret | 必填 | 说明 |
|---|---|---|
| `QUARK_DRIVE_CONFIG_JSON` | 二选一 | 夸克 CLI 的完整 `config.json` |
| `QUARK_USER_ID` / `QUARK_DEVICE_ID` / `QUARK_ACCESS_TOKEN` / `QUARK_REFRESH_TOKEN` | 二选一 | 拆开写 token |
| `QUARK_PARENT_FID` | 建议 | 「AstralGame」目录 FID |
| `ASTRAL_SITE_TOKEN` | 可选 | 写 `next.astral.github.io`，并用于创建 GitHub Release |

## 本地试跑

```powershell
$env:OPENCLAW_CLI = "1"
node "$env:USERPROFILE\.cursor\skills\quarkclouddrive\scripts\quark-drive.cjs" get-user-info --session-input "whoami" --session-id "local"
bash tools/quark_release/upload.sh 1.0.22 release
```
