# nitro-bazzite

> **Warning:** This is hardware-specific and unofficial. Use at your own risk.
> Upstream Linuwu-Sense only lists one model as fully supported, and this
> image is built for the Acer Nitro ANV15-51-519K only.

**Status:** work in progress, not yet verified on real hardware. 

## What this is?

Bazzite KDE (`nvidia-open`, stable) with a signed
[Linuwu-Sense](https://github.com/0x7375646F/Linuwu-Sense) kernel module and
a temperature-based fan service, built for my own laptop. It might not work
on sibling models. Check upstream's supported-model list and open issues,
and test carefully.

## Not meant for you to rebase onto!

Using the signed module under Secure Boot means enrolling my signing
certificate, which gives my key the ability to sign code that loads into
your kernel. Don't do that. Instead fork this repo (or the ublue image-template),
generate your own keys, and build your own image.

This repository is provided as-is, with no warranty.