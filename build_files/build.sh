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
dnf5 install -y tmux kitty krita keepassxc libreoffice libreoffice-langpack-en audacious gamemode

# dnf5 install -y --enablerepo=terra --allowerasing something

# terra packages (terra enabled for this command only)
dnf5 install -y --enablerepo=terra discord prismlauncher peazip-qt6 lact

# this installs fonts from fedora and terra repos
dnf5 install -y --enablerepo=terra rsms-inter-fonts meslo-nerd-fonts adobe-source-code-pro-fonts adobe-source-code-vf-fonts adobe-source-sans-pro-fonts adobe-source-serif-pro-fonts


# enable services
systemctl enable tuned tuned-ppd earlyoom lactd

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

# enable terra repo permanently
dnf5 config-manager setopt terra.enabled=1

# Wrapper scripts
cat > /usr/bin/zink-run <<'EOF'
#!/usr/bin/env bash
export __GLX_VENDOR_LIBRARY_NAME=mesa
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink
exec "$@"
EOF
chmod 755 /usr/bin/zink-run

cat > /usr/bin/prime-run <<'EOF'
#!/usr/bin/env bash
export __NV_PRIME_RENDER_OFFLOAD=1
export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
export __GLX_VENDOR_LIBRARY_NAME=nvidia
export __VK_LAYER_NV_optimus=NVIDIA_only
exec "$@"
EOF
chmod 755 /usr/bin/prime-run

cat > /usr/bin/zink-nvidia-run <<'EOF'
#!/usr/bin/env bash
export __GLX_VENDOR_LIBRARY_NAME=mesa
export MESA_LOADER_DRIVER_OVERRIDE=zink
export GALLIUM_DRIVER=zink
export __NV_PRIME_RENDER_OFFLOAD=1
export __VK_LAYER_NV_optimus=NVIDIA_only
export MESA_VK_DEVICE_SELECT=10de:25ad
export MESA_VK_DEVICE_SELECT_FORCE_DEFAULT_DEVICE=1
exec "$@"
EOF
chmod 755 /usr/bin/zink-nvidia-run

# gamemode user things
# replace your username in between these groups
#m $USER plugdev
#m $USER gamemode
cat > /usr/lib/sysusers.d/50-groups.conf <<'EOF'
m clyde plugdev
m clyde gamemode
EOF
