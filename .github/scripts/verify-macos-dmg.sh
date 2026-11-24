#!/usr/bin/env bash
set -euo pipefail

dmg="$(cd "$(dirname "${1:?DMG path required}")" && pwd)/$(basename "$1")"
architecture="${2:?architecture required}"
version="${3:?version required}"
scratch="$(mktemp -d "${TMPDIR:-/tmp}/soft-desk-dmg.XXXXXXXX")"
mount_point="${scratch}/volume"
mounted=0

cleanup() {
  if (( mounted )); then
    hdiutil detach "${mount_point}" -quiet || return
  fi
  find "${scratch}" -depth -delete
}
trap cleanup EXIT
mkdir "${mount_point}"
hdiutil verify "${dmg}"
hdiutil attach "${dmg}" -readonly -nobrowse -mountpoint "${mount_point}" -quiet
mounted=1

# Test the shipped bundle after copying it off the disk image, as users do.
app="${scratch}/SOFT.Connect.Desk.app"
ditto "${mount_point}/SOFT.Connect.Desk.app" "${app}"
codesign --verify --deep --strict --verbose=2 "${app}"
plist="${app}/Contents/Info.plist"
bundle_executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "${plist}")"
test "${bundle_executable}" = "SOFT.Connect.Desk"
main="${app}/Contents/MacOS/${bundle_executable}"
for binary in "${main}" "${app}/Contents/MacOS/service" \
              "${app}/Contents/Frameworks/libsoftconnectdesk.dylib"; do
  test -f "${binary}"
  lipo -verify_arch "${architecture}" "${binary}"
done
test -x "${main}"
test -x "${app}/Contents/MacOS/service"

actual="$(/usr/bin/perl -e 'alarm shift; exec @ARGV' 30 "${main}" --version)"
if ! grep -Fxq -- "${version}" <<<"${actual}"; then
  printf 'Expected version %s; packaged app returned: %s\n' "${version}" "${actual}" >&2
  exit 1
fi
echo "Packaged app starts and reports ${version} on ${architecture}."

if ! spctl --assess --type execute --verbose=2 "${app}"; then
  echo "::warning::Gatekeeper does not trust this ad-hoc signed app for public distribution."
fi
