#!/usr/bin/env bash
set -euo pipefail

role="${ROLE:-support}"
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
    echo "Unsupported ROLE: ${role}" >&2
    exit 2
    ;;
esac

source_root=/workspace
build_root=/build
output_root=/out

mkdir -p \
  "${build_root}/vcpkg-installed" \
  "${build_root}/vcpkg-buildtrees" \
  "${build_root}/vcpkg-packages" \
  "${build_root}/downloads" \
  "${build_root}/cargo-target" \
  "${output_root}"

rm -rf /opt/vcpkg/installed
ln -s "${build_root}/vcpkg-installed" /opt/vcpkg/installed

cd "${source_root}"
/opt/vcpkg/vcpkg install \
  --triplet=x64-linux \
  --host-triplet=x64-linux \
  --x-install-root="${build_root}/vcpkg-installed" \
  --x-buildtrees-root="${build_root}/vcpkg-buildtrees" \
  --x-packages-root="${build_root}/vcpkg-packages" \
  --downloads-root="${build_root}/downloads"

git config --global --add safe.directory "${source_root}"
export CARGO_TARGET_DIR="${build_root}/cargo-target"
export CARGO_INCREMENTAL=0
export DEB_ARCH=amd64

cargo +1.75.0 build \
  --locked \
  --lib \
  --release \
  --features "hwcodec,flutter,unix-file-copy-paste,${role_feature}"

mkdir -p "${source_root}/target/release"
cp "${CARGO_TARGET_DIR}/release/librustdesk.so" \
  "${source_root}/target/release/librustdesk.so"

sed -i \
  's/ffi.NativeFunction<ffi.Bool Function(DartPort/ffi.NativeFunction<ffi.Uint8 Function(DartPort/g' \
  flutter/lib/generated_bridge.dart

python3 ./build.py --flutter --skip-cargo

deb_source="$(find "${source_root}" -maxdepth 1 -type f -name 'soft-connect-desk-*.deb' | head -n 1)"
if [[ -z "${deb_source}" ]]; then
  echo "Linux DEB was not produced" >&2
  exit 1
fi

deb_output="${output_root}/SOFT.Connect.Desk-${role_name}-linux-x64.deb"
cp "${deb_source}" "${deb_output}"

cp "${deb_output}" "${source_root}/appimage/soft-connect-desk.deb"
(
  cd "${source_root}/appimage"
  rm -rf AppDir ./*.AppImage
  appimage-builder --skip-tests --recipe ./AppImageBuilder-x86_64.yml
)

appimage_source="$(find "${source_root}/appimage" -maxdepth 1 -type f -name '*.AppImage' | head -n 1)"
if [[ -z "${appimage_source}" ]]; then
  echo "Linux AppImage was not produced" >&2
  exit 1
fi

appimage_output="${output_root}/SOFT.Connect.Desk-${role_name}-linux-x64.AppImage"
cp "${appimage_source}" "${appimage_output}"

(
  cd "${output_root}"
  sha256sum \
    "$(basename "${deb_output}")" \
    "$(basename "${appimage_output}")" \
    > "SHA256SUMS-${role_name}.txt"
)

echo "Linux artifacts: ${output_root}"
