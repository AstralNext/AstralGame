# 夸克网盘自动上传（Release）

`发布` 工作流在 GitHub Release 创建后，用**夸克官方 CLI**（skill zip 里的 `quark-drive.cjs`）上传安装包并公开分享。

关键：`OPENCLAW_CLI=1`（通过 Agent 检测）→ 写入 `openclaw/config.json` → `upload` / `share`。

## Secrets

| Secret | 说明 |
|---|---|
| `QUARK_DRIVE_CONFIG_JSON` | 官方 CLI 的 `config.json` |
| `QUARK_PARENT_FID` | `AstralGame` 目录 FID |
| `ASTRAL_SITE_TOKEN` | 有 `AstralGame` + `next.astral.github.io` 写权限的 token |

## 本地

```powershell
$env:OPENCLAW_CLI = "1"
$env:QUARK_PARENT_FID = "..."
bash tools/quark_release/upload.sh 1.0.24 release
```
