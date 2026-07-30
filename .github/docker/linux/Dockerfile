FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive
ARG TARGETARCH
ARG RUST_VERSION=1.81.0
ARG FLUTTER_VERSION=3.24.5
ARG VCPKG_COMMIT=120deac3062162151622ca4860575a33844ba10b

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        autoconf automake build-essential ca-certificates clang cmake curl desktop-file-utils \
        dpkg-dev fakeroot file g++ git libarchive-tools libasound2-dev \
        libayatana-appindicator3-dev libclang-dev libdbus-1-dev libfuse2 \
        libglib2.0-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev \
        libgtk-3-dev liblzma-dev libpam0g-dev libpulse-dev libssl-dev libtool \
        libsystemd-dev libva-dev libxcb-randr0-dev libxcb-shape0-dev \
        libxcb-xfixes0-dev libxdo-dev libxfixes-dev nasm ninja-build \
        patchelf pkg-config python3 python3-pip rpm squashfs-tools unzip wget xz-utils zip zsync \
    && rm -rf /var/lib/apt/lists/*

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain "${RUST_VERSION}" --profile minimal \
    && /root/.cargo/bin/rustup component add rustfmt

RUN git clone https://github.com/microsoft/vcpkg.git /opt/vcpkg \
    && git -C /opt/vcpkg reset --hard "${VCPKG_COMMIT}" \
    && /opt/vcpkg/bootstrap-vcpkg.sh -disableMetrics

RUN wget -q \
        "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
        -O /tmp/flutter.tar.xz \
    && tar -xf /tmp/flutter.tar.xz -C /opt \
    && rm -f /tmp/flutter.tar.xz \
    && if [ "${TARGETARCH}" = "arm64" ]; then \
        git clone https://github.com/sony/flutter-elinux.git /opt/flutter-elinux \
        && git -C /opt/flutter-elinux reset --hard "${FLUTTER_VERSION}" \
        && git config --global --add safe.directory /opt/flutter-elinux/flutter \
        && /opt/flutter-elinux/bin/flutter-elinux doctor -v \
        && /opt/flutter-elinux/bin/flutter-elinux precache --linux \
        && mkdir -p /opt/flutter-elinux/flutter/bin/cache/artifacts/engine/linux-arm64 \
        && cp -R /opt/flutter/bin/cache/artifacts/engine/linux-x64/shader_lib \
          /opt/flutter-elinux/flutter/bin/cache/artifacts/engine/linux-arm64/ \
        && rm -rf /opt/flutter; \
      else \
        git config --global --add safe.directory /opt/flutter \
        && /opt/flutter/bin/flutter config --enable-linux-desktop \
        && /opt/flutter/bin/flutter precache --linux; \
      fi

RUN python3 -m pip install --no-cache-dir "setuptools_scm<10" \
    && python3 -m pip install --no-cache-dir \
        git+https://github.com/rustdesk-org/appimage-builder.git

COPY build.sh /usr/local/bin/build-soft-connect-desk-linux
RUN chmod 0755 /usr/local/bin/build-soft-connect-desk-linux

ENV PATH="/root/.cargo/bin:/opt/flutter/bin:/opt/flutter-elinux/bin:${PATH}"
ENV VCPKG_ROOT=/opt/vcpkg
ENV LIBCLANG_PATH=/usr/lib/llvm-14/lib

ENTRYPOINT ["/usr/local/bin/build-soft-connect-desk-linux"]
