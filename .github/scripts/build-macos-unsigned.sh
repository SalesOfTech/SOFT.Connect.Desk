#!/usr/bin/env bash
set -euo pipefail

role="${1:-support}"
case "${role}" in
  support)
    role_feature="soft-connect-support"
    role_name="Support"
    ;;
  operator)
    role_feature="soft-connect-operator"
    role_name="Operator"
    ;;
  *)
    echo "Usage: $0 [support|operator]" >&2
    exit 2
    ;;
esac

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
output_root="${source_root}/dist/macos"
mkdir -p "${output_root}"
cd "${source_root}"

export MACOSX_DEPLOYMENT_TARGET="${MACOSX_DEPLOYMENT_TARGET:-10.14}"
export CARGO_INCREMENTAL=0

cargo +1.81.0 build \
  --locked \
  --lib \
  --bin service \
  --release \
  --features "flutter,hwcodec,unix-file-copy-paste,${role_feature}"

python3 ./build.py --flutter --skip-cargo

app_path="${source_root}/flutter/build/macos/Build/Products/Release/SOFT.Connect.Desk.app"
if [[ ! -d "${app_path}" ]]; then
  echo "macOS app bundle was not produced: ${app_path}" >&2
  exit 1
fi

# Free ad-hoc signature. This is deliberately not Developer ID/notarization.
codesign --force --deep --sign - "${app_path}"

arch="$(uname -m)"
dmg_path="${output_root}/SOFT.Connect.Desk-${role_name}-macos-${arch}-unsigned.dmg"
rm -f "${dmg_path}"
hdiutil create \
  -volname "SOFT.Connect.Desk" \
  -srcfolder "${app_path}" \
  -format UDZO \
  -ov \
  "${dmg_path}"

shasum -a 256 "${dmg_path}" > "${dmg_path}.sha256"
echo "macOS artifact: ${dmg_path}"
