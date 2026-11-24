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
dnf5 install -y firefox tmux kitty krita keepassxc libreoffice libreoffice-langpack-en audacious gamemode java-latest-openjdk kdenlive irqbalance cava cheat cowsay opendoas kdotool rust cargo opencode-cli opencode-cli-bash-completion opencode-cli-fish-completion webkitgtk6.0

# installs packages from terra repos
dnf5 install -y --enablerepo=terra discord prismlauncher peazip-qt6 superfile

# this installs fonts from fedora or terra repos
dnf5 install -y --enablerepo=terra rsms-inter-fonts meslo-nerd-fonts adobe-source-code-pro-fonts adobe-source-code-vf-fonts adobe-source-sans-pro-fonts adobe-source-serif-pro-fonts inconsolata-nerd-fonts inconsolatago-nerd-fonts inconsolatalgc-nerd-fonts

# removes firefox from flatpak and self-disables the script itself next reboot
LIST=/usr/share/ublue-os/bazzite/flatpak/install
if [ -f "$LIST" ]; then
  sed -i '/org\.mozilla\.firefox/d' "$LIST"
fi

cat > /usr/bin/remove-default-flatpaks <<'EOF'
#!/usr/bin/env bash
for app in org.mozilla.firefox; do
  if flatpak list --system --app --columns=application | grep -qx "$app"; then
    flatpak uninstall --system --noninteractive "$app"
  fi
done
mkdir -p /var/lib/remove-default-flatpaks
touch /var/lib/remove-default-flatpaks/done
EOF
chmod 755 /usr/bin/remove-default-flatpaks

cat > /usr/lib/systemd/system/remove-default-flatpaks.service <<'EOF'
[Unit]
Description=Remove unwanted default flatpaks (one time)
After=bazzite-flatpak-manager.service
ConditionPathExists=!/var/lib/remove-default-flatpaks/done

[Service]
Type=oneshot
ExecStart=/usr/bin/remove-default-flatpaks

[Install]
WantedBy=multi-user.target
EOF

systemctl enable remove-default-flatpaks.service

cat > /usr/bin/remove-default-flatpaks <<'EOF'
#!/usr/bin/env bash
for app in org.mozilla.firefox; do
  if flatpak list --system --app --columns=application | grep -qx "$app"; then
    flatpak uninstall --system --noninteractive "$app"
  fi
done
mkdir -p /var/lib/remove-default-flatpaks
touch /var/lib/remove-default-flatpaks/done
systemctl disable --no-reload remove-default-flatpaks.service || true
EOF
chmod 755 /usr/bin/remove-default-flatpaks

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File
systemctl enable podman.socket tuned tuned-ppd earlyoom irqbalance sched-cgroup-mode

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

# Wrapper scripts (moved)
chmod 0755 /usr/bin/prime-run
chmod 0755 /usr/bin/zink-nvidia-run
chmod 0755 /usr/bin/zink-run

# update flatpak packages daily
systemctl enable flatpak-update.timer

# gamemode user things (not uncommenting one of these, its just a hint for the next user `systemctl reboot`)
# if installed for the first time do:
# grep -E '^plugdev:' /usr/lib/group | sudo tee -a /etc/group
# grep -E '^gamemode:' /usr/lib/group | sudo tee -a /etc/group
# sudo usermod -aG plugdev,gamemode $USER

