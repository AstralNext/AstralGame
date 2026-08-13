# 夸克网盘自动上传（Release）

打 `v*` 标签并完成 GitHub Release 后，Actions 用夸克 **Open HTTP API**（`https://open-api-drive.quark.cn`）上传 `release/` 安装包，创建永久公开分享，并（可选）更新官网 `downloads.json`。

不依赖 `quark-drive.cjs`，因此不受 CLI「无法识别当前 Agent 环境」限制。

## 仓库 Secrets

在 `AstralNext/AstralGame` → Settings → Secrets and variables → Actions：

| Secret | 必填 | 说明 |
|---|---|---|
| `QUARK_DRIVE_CONFIG_JSON` | 二选一 | 夸克 CLI 的完整 `config.json`（含 access/refresh token） |
| `QUARK_USER_ID` / `QUARK_DEVICE_ID` / `QUARK_ACCESS_TOKEN` / `QUARK_REFRESH_TOKEN` | 二选一 | 拆开写 token |
| `QUARK_PARENT_FID` | 建议 | 「AstralGame」目录 FID。不填则在根目录幂等创建 |
| `ASTRAL_SITE_TOKEN` | 可选 | 能写 `AstralNext/next.astral.github.io` 的 PAT |

```bash
gh secret set QUARK_DRIVE_CONFIG_JSON --repo AstralNext/AstralGame
# 然后把 config.json 内容贴进 stdin，或以管道传入
Get-Content -Raw config.json | gh secret set QUARK_DRIVE_CONFIG_JSON --repo AstralNext/AstralGame
```

## 接口（Open API）

签名头：`x-pan-client-id` / `x-pan-tm` / `x-pan-token`（`sha256(METHOD&PATH&ts&signKey)`）

| 用途 | 方法 | 路径 |
|---|---|---|
| 刷新 token | POST | `/agent/v1/oauth/access_token/rotate` |
| 用户信息 | GET | `/open/v1/user/info` |
| 建文件夹 | POST | `/open/v1/dir` |
| 预上传 / 秒传 | POST | `/open/v1/file/upload_pre` |
| 分片 URL | POST | `/open/v1/file/get_upload_urls` |
| 完成上传 | POST | `/open/v1/file/upload_finish` |
| 公开分享 | POST | `/agent/v1/share/create` |

## 本地试跑

```bash
$env:QUARK_DRIVE_CONFIG_JSON = Get-Content -Raw config.json
python tools/quark_release/quark_http.py whoami
python tools/quark_release/quark_http.py upload 1.0.22 release
```
