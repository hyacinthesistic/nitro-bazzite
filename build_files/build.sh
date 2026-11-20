#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs packages from fedora repos
dnf5 install -y --allowerasing tuned-gui tuned-ppd earlyoom
dnf5 install -y tmux kitty krita keepassxc libreoffice libreoffice-langpack-en audacious gamemode java-latest-openjdk kdenlive irqbalance cava cheat cowsay opendoas kdotool

# installs packages from terra repos
dnf5 install -y --enablerepo=terra discord prismlauncher peazip-qt6 superfile

# this installs fonts from fedora or terra repos
dnf5 install -y --enablerepo=terra rsms-inter-fonts meslo-nerd-fonts adobe-source-code-pro-fonts adobe-source-code-vf-fonts adobe-source-sans-pro-fonts adobe-source-serif-pro-fonts inconsolata-nerd-fonts inconsolatago-nerd-fonts inconsolatalgc-nerd-fonts

# enable services
systemctl enable tuned tuned-ppd earlyoom irqbalance sched-cgroup-mode

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable podman.socket

### Linuwu-Sense driver built and signed against the kernel inside this image
LINUWU_COMMIT="4483b6c38b9bb963ac9ada9ca476578e0c63cc08"

KVER="$(ls -1 /usr/lib/modules)"
if [[ "$(wc -l <<< "${KVER}")" -ne 1 ]]; then
    echo "Expected exactly one kernel in /usr/lib/modules, found: ${KVER}"
    exit 1
fi
if [[ ! -d "/usr/src/kernels/${KVER}" ]]; then
    echo "kernel-devel for ${KVER} not found"
    exit 1
fi

SIGN_KEY=/run/secrets/linuwu_key
SIGN_CERT=/usr/share/linuwu/linuwu-signing.der
[[ -f "${SIGN_KEY}" ]] || { echo "linuwu_key secret is missing"; exit 1; }
[[ -f "${SIGN_CERT}" ]] || { echo "public cert is missing from the image"; exit 1; }

mkdir -p /tmp/linuwu
curl -fsSL "https://github.com/0x7375646F/Linuwu-Sense/archive/${LINUWU_COMMIT}.tar.gz" \
    | tar -xz -C /tmp/linuwu --strip-components=1

(cd /tmp/linuwu && make KVER="${KVER}" KDIR="/usr/src/kernels/${KVER}")

"/usr/src/kernels/${KVER}/scripts/sign-file" sha256 "${SIGN_KEY}" "${SIGN_CERT}" /tmp/linuwu/src/linuwu_sense.ko
SIGNER="$(modinfo -F signer /tmp/linuwu/src/linuwu_sense.ko)"
echo "Module signer: ${SIGNER}"
[[ -n "${SIGNER}" ]] || { echo "module is not signed"; exit 1; }

install -Dm0644 /tmp/linuwu/src/linuwu_sense.ko "/usr/lib/modules/${KVER}/extra/linuwu_sense.ko"
depmod -a "${KVER}"
modinfo -k "${KVER}" -F vermagic linuwu_sense
rm -rf /tmp/linuwu

### Temperature-based fan control service
chmod 0755 /usr/libexec/linuwu-fan-control
bash -n /usr/libexec/linuwu-fan-control
systemctl enable linuwu-fan-control.service

### llama.cpp prebuilt (CUDA 13.5 backend, needs a driver reporting CUDA >= 13.5)
#LLAMA_VER="b12503"
#LLAMA_BASE="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_VER}"
#LLAMA_DIR="/usr/lib/llama.cpp"

#mkdir -p "${LLAMA_DIR}"
#curl -fsSL "${LLAMA_BASE}/llama-${LLAMA_VER}-bin-ubuntu-cuda-13.5-x64.tar.gz" \
#    | tar -xz -C "${LLAMA_DIR}" --strip-components=1
#curl -fsSL "${LLAMA_BASE}/cudart-llama-${LLAMA_VER}-bin-ubuntu-cuda-13.5-x64.tar.gz" \
#    | tar -xz -C "${LLAMA_DIR}" --strip-components=1

# fail the build instead of shipping a broken image
#[[ -x "${LLAMA_DIR}/llama-cli" ]]       || { echo "llama-cli missing"; exit 1; }
#[[ -f "${LLAMA_DIR}/libggml-cuda.so" ]] || { echo "CUDA backend missing"; exit 1; }
#[[ -f "${LLAMA_DIR}/libcudart.so.13" ]] || { echo "cudart missing"; exit 1; }

#for f in "${LLAMA_DIR}"/llama*; do
#    if [[ -f "${f}" && -x "${f}" ]]; then
#        ln -sf "${f}" "/usr/bin/$(basename "${f}")"
#    fi
#done

### Ollama
OLLAMA_VER="v0.40.16"
OLLAMA_URL="https://github.com/ollama/ollama/releases/download/${OLLAMA_VER}/ollama-linux-amd64.tar.zst"

curl -fsSL "${OLLAMA_URL}" | tar --zstd -x -C /usr

[[ -x /usr/bin/ollama ]] || { echo "ollama missing"; exit 1; }
[[ -d /usr/lib/ollama ]] || { echo "ollama libs missing"; exit 1; }

# enable terra repo permanently
dnf5 config-manager setopt terra.enabled=1

# Wrapper scripts (moved)
chmod 0755 /usr/bin/prime-run
chmod 0755 /usr/bin/zink-nvidia-run
chmod 0755 /usr/bin/zink-run

# update flatpak packages daily
systemctl enable flatpak-update.timer

# gamemode user things (not uncommenting one of these, its just for the next user `systemctl reboot`)
# grep -E '^plugdev:' /usr/lib/group | sudo tee -a /etc/group
# grep -E '^gamemode:' /usr/lib/group | sudo tee -a /etc/group
# sudo usermod -aG plugdev,gamemode $USER

# dont use greenboost yet (no reason)
#GB_COMMIT="6dc3c5988c5e0842ee426638feb2fb7abdf5e7e0"
#mkdir -p /tmp/greenboost
#curl -fsSL "https://gitlab.com/IsolatedOctopi/greenboost/-/archive/${GB_COMMIT}/greenboost-${GB_COMMIT}.tar.gz" | tar -xz -C /tmp/#greenboost --strip-components=1
#cd /tmp/greenboost
#sed -i 's/-march=native -mtune=native/-march=x86-64-v3 -mtune=generic/g' Makefile
#grep -q 'march=x86-64-v3' Makefile || { echo "march sed did not apply"; exit 1; }
#! grep -qE '^[^#]*march=native' Makefile || { echo "march=native still present"; exit 1; }
#
#make KVER="${KVER}" module
#[[ "$(modinfo -F vermagic greenboost.ko)" == "${KVER} "* ]] || { echo "greenboost.ko built for the wrong kernel"; exit 1; }
#make -k KVER="${KVER}" SHIM_INSTALL_PATH=/usr/lib64/libgreenboost_cuda.so shim audit
#
#"/usr/src/kernels/${KVER}/scripts/sign-file" sha256 "${SIGN_KEY}" "${SIGN_CERT}" greenboost.ko
#install -Dm0644 greenboost.ko "/usr/lib/modules/${KVER}/extra/greenboost.ko"
#[[ -n "$(modinfo -F signer greenboost.ko)" ]] || { echo "greenboost.ko is not signed"; exit 1; }
#install -Dm0755 libgreenboost_cuda.so  /usr/lib64/libgreenboost_cuda.so
#install -Dm0755 libgreenboost_audit.so /usr/lib64/libgreenboost_audit.so
#depmod -a "${KVER}"
#cd / && rm -rf /tmp/greenboost
