#!/usr/bin/env bash
# 用夸克官方 CLI（skill zip 里的 quark-drive.cjs）上传 Release 包。
# 设 OPENCLAW_CLI=1 即可通过 Agent 环境检测，读取 openclaw/config.json。
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
export OPENCLAW_CLI="${OPENCLAW_CLI:-1}"

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
  echo "missing Quark secrets" >&2
  exit 2
}

SKILL_DIR="${QUARK_SKILL_DIR:-}"
if [ -z "$SKILL_DIR" ]; then
  if [ -f "$HOME/.cursor/skills/quarkclouddrive/scripts/quark-drive.cjs" ]; then
    SKILL_DIR="$HOME/.cursor/skills/quarkclouddrive"
  elif [ -f "/root/.cursor/skills/quarkclouddrive/scripts/quark-drive.cjs" ]; then
    SKILL_DIR="/root/.cursor/skills/quarkclouddrive"
  fi
fi

if [ -z "$SKILL_DIR" ] || [ ! -f "$SKILL_DIR/scripts/quark-drive.cjs" ]; then
  echo "==> bootstrap official quark CLI"
  WORK="${RUNNER_TEMP:-/tmp}/quarkclouddrive-skill"
  mkdir -p "$WORK"
  python3 - "$WORK" <<'PY'
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
extract = work / "extract"
extract.mkdir(exist_ok=True)
with zipfile.ZipFile(zip_path) as zf:
    zf.extractall(extract)
cjs = next(extract.rglob("quark-drive.cjs"))
print(str(cjs.parent.parent))
PY
  SKILL_DIR="$(python3 - "$WORK" <<'PY'
from pathlib import Path
import sys
work = Path(sys.argv[1])
print(next((work / "extract").rglob("quark-drive.cjs")).parent.parent)
PY
)"
fi

CLI="$SKILL_DIR/scripts/quark-drive.cjs"
write_config "$SKILL_DIR/openclaw/config.json"

quark() {
  node "$CLI" "$@" --session-input "Astral Game release $TAG" --session-id "gha-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
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
  PARENT_FID="$(python3 -c 'import json,sys; print((json.loads(sys.argv[1]).get("data") or {}).get("fid",""))' "$out")"
fi
out="$(quark create-folder --dir-path "$TAG" --parent-fid "$PARENT_FID" | ndjson_last)"
echo "$out"
VER_FID="$(python3 -c 'import json,sys; print((json.loads(sys.argv[1]).get("data") or {}).get("fid",""))' "$out")"
if [ -z "$VER_FID" ]; then
  echo "failed to create version folder" >&2
  exit 1
fi

echo "==> upload ${#FILES[@]} files with official CLI"
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
    python3 "$ROOT/tools/quark_release/update_downloads_json.py" \
      --token "$ASTRAL_SITE_TOKEN" \
      --repo "${SITE_REPO:-AstralNext/next.astral.github.io}" \
      --path "${SITE_DOWNLOADS_PATH:-public/downloads.json}" \
      --branch "${SITE_BRANCH:-master}" \
      --version "$TAG" \
      --url "$SHARE_URL"
  fi
fi
