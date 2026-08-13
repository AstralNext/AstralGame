#!/usr/bin/env bash
# Release 安装包走夸克 Open API 上传并创建公开分享。
# 必填：QUARK_DRIVE_CONFIG_JSON 或 token 字段。
set -euo pipefail

VERSION="${1:-}"
RELEASE_DIR="${2:-release}"
if [ -z "$VERSION" ]; then
  echo "usage: upload.sh <version> [release-dir]" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
exec python3 "$ROOT/tools/quark_release/quark_http.py" upload "$VERSION" "$RELEASE_DIR"
