#!/usr/bin/env bash
set -euo pipefail
features="flutter,hwcodec"
if [[ -n "${SOFT_CONNECT_ROLE_FEATURE:-}" ]]; then
  features="${features},${SOFT_CONNECT_ROLE_FEATURE}"
fi
cargo ndk --platform 21 --target armv7-linux-androideabi build --locked --release --features "${features}"
