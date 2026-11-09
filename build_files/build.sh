#!/bin/bash

set -ouex pipefail

# Copy the contents of system_files/ of the git repo to /
cp -avf "/ctx/system_files"/. /

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/43/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y tmux

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