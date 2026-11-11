# Build environment for the YY3588 firmware and image scripts.
#   podman build -t yy3588-build -f Containerfile .
#   podman run --rm --userns=keep-id --security-opt label=disable \
#     -v "$PWD":/w -w /w yy3588-build make yy3588-rkbin-ddr
FROM registry.fedoraproject.org/fedora:44

RUN dnf -y install --setopt=install_weak_deps=False \
        make git patch gcc gcc-c++ libuuid-devel python3 python3-pyelftools \
        gcc-aarch64-linux-gnu binutils-aarch64-linux-gnu \
        acpica-tools dtc uboot-tools openssl gettext which findutils diffutils xz \
        gdisk dosfstools mtools e2fsprogs android-tools \
    && dnf clean all

# Rust 1.99.0 (bt0 and the host tools; `cargo +1.99.0` in the Makefile).
ENV RUSTUP_HOME=/opt/rustup CARGO_HOME=/opt/cargo PATH=/opt/cargo/bin:$PATH HOME=/tmp
RUN curl -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path --profile minimal \
        --default-toolchain 1.99.0 --target aarch64-unknown-none-softfloat \
    && chmod -R a+rwX /opt/rustup /opt/cargo
