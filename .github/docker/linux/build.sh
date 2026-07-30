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

case "$(uname -m)" in
  x86_64)
    artifact_arch="x64"
    vcpkg_triplet="x64-linux"
    deb_arch="amd64"
    flutter_arch="x64"
    flutter_sdk_root="/opt/flutter"
    appimage_recipe="AppImageBuilder-x86_64.yml"
    ;;
  aarch64|arm64)
    artifact_arch="aarch64"
    vcpkg_triplet="arm64-linux"
    deb_arch="arm64"
    flutter_arch="arm64"
    flutter_sdk_root="/opt/flutter-elinux/flutter"
    appimage_recipe="AppImageBuilder-aarch64.yml"
    ;;
  *)
    echo "Unsupported Linux architecture: $(uname -m)" >&2
    exit 2
    ;;
esac

mkdir -p \
  "${build_root}/vcpkg-installed" \
  "${build_root}/vcpkg-buildtrees" \
  "${build_root}/vcpkg-packages" \
  "${build_root}/downloads" \
  "${build_root}/cargo-target" \
  "${build_root}/pub-cache" \
  "${output_root}"

rm -rf /opt/vcpkg/installed
ln -s "${build_root}/vcpkg-installed" /opt/vcpkg/installed

cd "${source_root}"
/opt/vcpkg/vcpkg install \
  --triplet="${vcpkg_triplet}" \
  --host-triplet="${vcpkg_triplet}" \
  --x-install-root="${build_root}/vcpkg-installed" \
  --x-buildtrees-root="${build_root}/vcpkg-buildtrees" \
  --x-packages-root="${build_root}/vcpkg-packages" \
  --downloads-root="${build_root}/downloads"

git config --global --add safe.directory "${source_root}"
export CARGO_TARGET_DIR="${build_root}/cargo-target"
export CARGO_INCREMENTAL=0
export DEB_ARCH="${deb_arch}"
export PUB_CACHE="${build_root}/pub-cache"

flutter_patch="${source_root}/.github/patches/flutter_3.24.4_dropdown_menu_enableFilter.diff"
if git -C "${flutter_sdk_root}" apply --check "${flutter_patch}" 2>/dev/null; then
  git -C "${flutter_sdk_root}" apply "${flutter_patch}"
fi

cargo +1.81.0 build \
  --locked \
  --lib \
  --release \
  --features "hwcodec,flutter,unix-file-copy-paste,${role_feature}"

mkdir -p "${source_root}/target/release"
cp "${CARGO_TARGET_DIR}/release/liblibrustdesk.so" \
  "${source_root}/target/release/liblibrustdesk.so"

"${flutter_sdk_root}/bin/flutter" pub get --directory "${source_root}/flutter"

sed -i \
  's/ffi.NativeFunction<ffi.Bool Function(DartPort/ffi.NativeFunction<ffi.Uint8 Function(DartPort/g' \
  flutter/lib/generated_bridge.dart

if [[ "${artifact_arch}" == "aarch64" ]]; then
  sed -i \
    -e 's/flutter build linux --release/flutter-elinux build linux --verbose/g' \
    -e 's#build/linux/x64/release#build/linux/arm64/release#g' \
    build.py
  sed -i 's#linux/x64#linux/arm64#g' \
    res/rpm-flutter.spec \
    res/rpm-flutter-suse.spec
fi

python3 ./build.py --flutter --skip-cargo

deb_source="$(find "${source_root}" -maxdepth 1 -type f -name 'soft-connect-desk-*.deb' | head -n 1)"
if [[ -z "${deb_source}" ]]; then
  echo "Linux DEB was not produced" >&2
  exit 1
fi

deb_output="${output_root}/SOFT.Connect.Desk-${role_name}-linux-${artifact_arch}.deb"
cp "${deb_source}" "${deb_output}"

cp "${deb_output}" "${source_root}/appimage/soft-connect-desk.deb"
(
  cd "${source_root}/appimage"
  rm -rf AppDir ./*.AppImage
  appimage-builder --skip-tests --recipe "./${appimage_recipe}"
)

appimage_source="$(find "${source_root}/appimage" -maxdepth 1 -type f -name '*.AppImage' | head -n 1)"
if [[ -z "${appimage_source}" ]]; then
  echo "Linux AppImage was not produced" >&2
  exit 1
fi

appimage_output="${output_root}/SOFT.Connect.Desk-${role_name}-linux-${artifact_arch}.AppImage"
cp "${appimage_source}" "${appimage_output}"

rm -rf /root/rpmbuild
HBB="${source_root}" rpmbuild "${source_root}/res/rpm-flutter.spec" -bb
rpm_source="$(find /root/rpmbuild/RPMS -type f -name 'soft-connect-desk-*.rpm' | head -n 1)"
if [[ -z "${rpm_source}" ]]; then
  echo "Fedora RPM was not produced" >&2
  exit 1
fi
rpm_output="${output_root}/SOFT.Connect.Desk-${role_name}-linux-${artifact_arch}.rpm"
cp "${rpm_source}" "${rpm_output}"

rm -rf /root/rpmbuild
HBB="${source_root}" rpmbuild "${source_root}/res/rpm-flutter-suse.spec" -bb
suse_source="$(find /root/rpmbuild/RPMS -type f -name 'soft-connect-desk-*.rpm' | head -n 1)"
if [[ -z "${suse_source}" ]]; then
  echo "SUSE RPM was not produced" >&2
  exit 1
fi
suse_output="${output_root}/SOFT.Connect.Desk-${role_name}-linux-${artifact_arch}-suse.rpm"
cp "${suse_source}" "${suse_output}"

bundle_output="${output_root}/SOFT.Connect.Desk-${role_name}-linux-${artifact_arch}-bundle.tar.gz"
tar -C "${source_root}/flutter/build/linux/${flutter_arch}/release" -czf "${bundle_output}" bundle

(
  cd "${output_root}"
  sha256sum \
    "$(basename "${deb_output}")" \
    "$(basename "${appimage_output}")" \
    "$(basename "${rpm_output}")" \
    "$(basename "${suse_output}")" \
    "$(basename "${bundle_output}")" \
    > "SHA256SUMS-${role_name}.txt"
)

echo "Linux artifacts: ${output_root}"
