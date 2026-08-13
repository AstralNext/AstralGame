#!/usr/bin/env bash
# 把 Release 安装包上传到夸克网盘并创建公开分享。
# 在 GitHub Actions 里用 Secrets 注入登录态，不要把 token 写进仓库。
#
# 必填环境变量（二选一）：
#   QUARK_DRIVE_CONFIG_JSON   完整 config.json 文本
#   或 QUARK_USER_ID + QUARK_DEVICE_ID + QUARK_ACCESS_TOKEN + QUARK_REFRESH_TOKEN
# 选填：
#   QUARK_PARENT_FID          网盘父目录 FID（不填则在根目录建 AstralGame）
#   QUARK_SHARE               默认 1，上传后创建永久公开分享
#   ASTRAL_SITE_TOKEN         有 next.astral.github.io 写权限的 PAT，用来更新 downloads.json
#   SITE_REPO                 默认 AstralNext/next.astral.github.io
#   SITE_DOWNLOADS_PATH       默认 public/downloads.json
set -euo pipefail

VERSION="${1:-}"
RELEASE_DIR="${2:-release}"
if [ -z "$VERSION" ]; then
  echo "usage: upload.sh <version> [release-dir]" >&2
  exit 2
fi
VERSION="${VERSION#v}"
TAG="v${VERSION}"

if [ ! -d "$RELEASE_DIR" ]; then
  echo "release dir missing: $RELEASE_DIR" >&2
  exit 2
fi
mapfile -t FILES < <(find "$RELEASE_DIR" -maxdepth 1 -type f | sort)
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "no files in $RELEASE_DIR" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
WORK="${RUNNER_TEMP:-/tmp}/quarkdrive"
mkdir -p "$WORK" "$HOME/.quarkclouddrive"
export OPENCLAW_RUNTIME_DIR="$HOME"
export HOME

write_config() {
  local dest="$1"
  mkdir -p "$(dirname "$dest")"
  if [ -n "${QUARK_DRIVE_CONFIG_JSON:-}" ]; then
    printf '%s\n' "$QUARK_DRIVE_CONFIG_JSON" > "$dest"
    return 0
  fi
  if [ -n "${QUARK_USER_ID:-}" ] && [ -n "${QUARK_ACCESS_TOKEN:-}" ] && [ -n "${QUARK_REFRESH_TOKEN:-}" ]; then
    python3 - "$dest" <<'PY'
import json, os, sys
path = sys.argv[1]
uid = os.environ["QUARK_USER_ID"]
cfg = {
    "deviceId": os.environ.get("QUARK_DEVICE_ID") or "github-actions-astral-game",
    "platform": "Linux",
    "currentUserId": uid,
    uid: {
        "accessToken": os.environ["QUARK_ACCESS_TOKEN"],
        "refreshToken": os.environ["QUARK_REFRESH_TOKEN"],
        "clientToken": os.environ.get("QUARK_CLIENT_TOKEN", ""),
        "userId": uid,
    },
}
with open(path, "w", encoding="utf-8") as f:
    json.dump(cfg, f, ensure_ascii=False, indent=2)
PY
    return 0
  fi
  echo "missing Quark secrets: set QUARK_DRIVE_CONFIG_JSON or token fields" >&2
  exit 2
}

write_config "$HOME/.quarkclouddrive/config.json"
write_config "$WORK/openclaw/config.json"

echo "==> bootstrap quark CLI"
CLI="$(python3 - "$WORK" <<'PY'
import json, os, sys, urllib.request, zipfile
from pathlib import Path
work = Path(sys.argv[1])
host = os.environ.get("SKILL_OPEN_API_HOST", "https://open-api-drive.quark.cn").rstrip("/")
url = f"{host}/agent/v1/skill_config?req_id={os.getpid()}"
with urllib.request.urlopen(url, timeout=60) as r:
    payload = json.loads(r.read().decode("utf-8"))
cfg = (payload.get("data") or {}).get("config") or payload.get("config") or payload.get("data") or payload
zip_url = str(cfg.get("qkPan") or "").strip()
if not zip_url.startswith("http"):
    raise SystemExit("skill_config has no zip url")
zip_path = work / "skill.zip"
urllib.request.urlretrieve(zip_url, zip_path)
with zipfile.ZipFile(zip_path) as zf:
    zf.extractall(work / "skill")
print(next(p for p in (work / "skill").rglob("quark-drive.cjs")))
PY
)"
chmod +x "$CLI" || true

quark() {
  node "$CLI" "$@" --session-input "Astral Game release upload $TAG" --session-id "gha-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
}

ndjson_last() {
  python3 -c '
import json,sys
last=None
for line in sys.stdin.read().splitlines():
    line=line.strip()
    if not line: continue
    try: last=json.loads(line)
    except Exception: pass
if not last: raise SystemExit("empty quark output")
print(json.dumps(last, ensure_ascii=False))
'
}

echo "==> ensure parent folder"
PARENT_FID="${QUARK_PARENT_FID:-}"
if [ -z "$PARENT_FID" ]; then
  out="$(quark create-folder --dir-path "AstralGame" --parent-fid "0" | ndjson_last)"
  echo "$out"
  PARENT_FID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("data",{}).get("fid",""))' "$out")"
  if [ -z "$PARENT_FID" ]; then
    echo "failed to create AstralGame folder" >&2
    exit 1
  fi
fi

echo "==> ensure version folder $TAG"
out="$(quark create-folder --dir-path "$TAG" --parent-fid "$PARENT_FID" | ndjson_last)"
echo "$out"
VER_FID="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("data",{}).get("fid",""))' "$out")"
if [ -z "$VER_FID" ]; then
  echo "failed to create version folder" >&2
  exit 1
fi

echo "==> upload ${#FILES[@]} files"
quark upload "${FILES[@]}" --parent-fid "$VER_FID"

SHARE_URL=""
if [ "${QUARK_SHARE:-1}" != "0" ]; then
  echo "==> create public share"
  out="$(quark share "$VER_FID" --title "Astral Game $TAG" --url-type 1 --expired-type 1 | ndjson_last)"
  echo "$out"
  SHARE_URL="$(python3 -c 'import json,sys; print((json.loads(sys.argv[1]).get("data") or {}).get("share_url",""))' "$out")"
fi

if [ -n "$SHARE_URL" ]; then
  echo "QUARK_SHARE_URL=$SHARE_URL"
  if [ -n "${GITHUB_OUTPUT:-}" ]; then
    echo "share_url=$SHARE_URL" >> "$GITHUB_OUTPUT"
  fi
  if [ -n "${ASTRAL_SITE_TOKEN:-}" ]; then
    echo "==> update site downloads.json"
    python3 "$ROOT/tools/quark_release/update_downloads_json.py" \
      --token "$ASTRAL_SITE_TOKEN" \
      --repo "${SITE_REPO:-AstralNext/next.astral.github.io}" \
      --path "${SITE_DOWNLOADS_PATH:-public/downloads.json}" \
      --version "$TAG" \
      --url "$SHARE_URL"
  else
    echo "ASTRAL_SITE_TOKEN not set; skip website downloads.json"
  fi
else
  echo "share url empty; skip site update"
fi
