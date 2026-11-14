#!/usr/bin/env bash
set -euo pipefail
# Official Lightpanda 1.0.4 Linux x86_64 artifact, digest published by GitHub.
if [[ "$(uname -s):$(uname -m)" != "Linux:x86_64" ]]; then
  echo 'This pinned artifact is Linux x86_64 only. See README for other platforms.' >&2
  exit 1
fi
mix spectre.lens.install \
  --url https://github.com/lightpanda-io/browser/releases/download/1.0.4/lightpanda-x86_64-linux \
  --sha256 7d22651129901203abdb95c64f49069c49e88f5211f4d8c4c6828c123c4adab4 \
  --out "${LIGHTPANDA_INSTALL_DIR:-$HOME/.local/bin}"
