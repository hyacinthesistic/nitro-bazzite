# nitro-bazzite

> **Warning:** This is hardware-specific and unofficial. Use at your own risk.
> Upstream Linuwu-Sense only lists one model as fully supported, and this
> image is built for the Acer Nitro ANV15-51-519K only.

**Status:** working and verified on the Acer Nitro ANV15-51-519K with Secure
Boot enabled (signed module loads, temperature-based fan control works).

## What this is?

Bazzite KDE (`nvidia-open`, stable) with a signed
[Linuwu-Sense](https://github.com/0x7375646F/Linuwu-Sense) kernel module and
a temperature-based fan service, built for my own laptop. It might not work
on sibling models. Check upstream's supported-model list and open issues,
and test carefully.

## What's in the image?

- Base: `ghcr.io/ublue-os/bazzite-nvidia-open:stable`
- Linuwu-Sense, built from a pinned upstream commit against the kernel inside
  the image and signed at build time
- `linuwu-fan-control`, a temperature-based fan control service
- The public signing certificate at
  `/usr/share/linuwu/linuwu-signing.der`
- The image is rebuilt on a schedule, so it follows upstream Bazzite. The
  build fails (and nothing is published) if the module can't be built and
  signed against the new kernel.

## Not meant for you to rebase onto!

Using the signed module under Secure Boot means enrolling my signing
certificate, which gives my key the ability to sign code that loads into
your kernel. Don't do that. Instead fork this repo (or the ublue image-template),
generate your own keys, and build your own image.

This repository is provided as-is, with no warranty.

## Building your own

1. Fork this repo and change `IMAGE_NAME` and `REPO_ORGANIZATION` in
   `image-template.env`.
2. Generate your own signing key and certificate, and keep the private key
   safe (GitHub secrets can't be read back, so keep an encrypted backup):

   ```
   openssl req -new -x509 -newkey rsa:2048 -nodes -days 36500 -sha256 \
     -subj "/CN=Linuwu module signing/" \
     -keyout linuwu.key -outform DER -out linuwu-signing.der
   ```

3. Replace `system_files/usr/share/linuwu/linuwu-signing.der` with your
   certificate from your repo
4. Add the private key as a GitHub repository secret (the Justfile reads it
   from `LINUWU_SIGNING_KEY`; check the workflow for the exact name)
5. Push, wait for the build to go green, and make sure the ghcr package is
   set to **public**
6. Rebase from an existing Bazzite install, then enroll your own certificate:

   ```
   rpm-ostree rebase ostree-unverified-registry:ghcr.io/<you>/<image>:latest
   systemctl reboot
   sudo mokutil --import /usr/share/linuwu/linuwu-signing.der # make a password for the MOK screen
   systemctl reboot   # then Enroll MOK > Continue > yes in the blue screen
   ```

## Verify

```
mokutil --sb-state                       # secure boot should be enabled
lsmod | grep linuwu                      # module loaded
modinfo linuwu_sense | grep -i signer    # signed by your certificate
systemctl status linuwu-fan-control      # fan service running
```

If the module doesn't load, `dmesg | grep -i linuwu` usually says why.
