# 夸克网盘自动上传（Release）

打 `v*` 标签并完成 GitHub Release 后，Actions 会把 `release/` 里的安装包上传到夸克网盘，创建永久公开分享，并（可选）更新官网 `downloads.json`。

## 仓库 Secrets

在 `AstralNext/AstralGame` → Settings → Secrets and variables → Actions 添加：

| Secret | 必填 | 说明 |
|---|---|---|
| `QUARK_DRIVE_CONFIG_JSON` | 二选一 | 夸克官方 CLI 的完整 `config.json`（含 access/refresh token） |
| `QUARK_USER_ID` / `QUARK_DEVICE_ID` / `QUARK_ACCESS_TOKEN` / `QUARK_REFRESH_TOKEN` | 二选一 | 拆开写 token，脚本会拼成 config |
| `QUARK_PARENT_FID` | 建议 | 网盘里「AstralGame」目录的 FID。不填则每次在根目录幂等创建 `AstralGame` |
| `ASTRAL_SITE_TOKEN` | 可选 | 能写 `AstralNext/next.astral.github.io` 的 PAT，用来更新 `public/downloads.json` |

本地若已绑定夸克 Skill，`config.json` 一般在用户目录下的 `.quarkclouddrive/` 或 Skill 的 `openclaw/`。把**整份 JSON**贴进 `QUARK_DRIVE_CONFIG_JSON` 即可，不要提交到 git。

```bash
gh secret set QUARK_DRIVE_CONFIG_JSON < config.json
gh secret set QUARK_PARENT_FID
gh secret set ASTRAL_SITE_TOKEN
```

`ASTRAL_SITE_TOKEN` 权限：`repo`（或至少该网站仓库 Contents: Read and write）。

## 网盘目录

```
夸克网盘/
  AstralGame/          ← QUARK_PARENT_FID
    v1.0.22/
      astral-game-1.0.22-windows-x64.zip
      astral-game-1.0.22-windows-x64-setup.exe
      astral-game-1.0.22-linux-x64.tar.gz
      astral-game-1.0.22-android-arm64.apk
```

每个版本文件夹会生成一条永久公开分享，写入 [next.astral.fan/downloads.json](https://next.astral.fan/downloads.json)。

## 本地试跑

```bash
export QUARK_DRIVE_CONFIG_JSON="$(cat /path/to/config.json)"
export QUARK_PARENT_FID="你的目录FID"
bash tools/quark_release/upload.sh 1.0.22 release
```

没有 Secrets 时，Release 工作流会跳过夸克步骤，不影响 GitHub Release。
