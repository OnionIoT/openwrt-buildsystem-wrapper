# Onion OpenWrt Build Wrapper

This branch builds Onion firmware through the wrapper project. The default profile builds the Omega4 model with `OEM=onion`.

## Requirements

- Ubuntu 22.04 or compatible Linux build host
- At least 8 GB RAM
- OpenWrt build dependencies installed

See the OpenWrt build system setup guide for the dependency list:
https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem#debianubuntu

## Source Repositories

This branch's checked-in `profile` uses OnionIoT forks for OpenWrt, the Linux kernel, and Omega4 kernel packages:

| Component | Repository | Ref |
| --- | --- | --- |
| OpenWrt | `git@github.com:OnionIoT/openwrt-omega4.git` | `v0.0.11` |
| Linux kernel | `git@github.com:OnionIoT/linux-stable.git` | `openwrt-6.6.93` |
| Kernel packages | `git@github.com:OnionIoT/omega4-kernel-packages.git` | `master` |

The wrapper clones these under the repo root:

```sh
openwrt/
linux-stable/
omega4-kernel-packages/
```

These directories are generated build state and are ignored by Git.

## Build

Run the wrapper from this repository:

```sh
./build.sh
```

The wrapper fallback default is `OEM=onion` when `OEM` is not set by `profile` or `-o`.

This branch's checked-in `profile` overrides the fallback to select Omega4:

```sh
OEM=onion
MODELS=omega4
VERSION=0.0.11
VCODE=r1
```

Useful build commands:

```sh
./build.sh        # prepare repos, build firmware, copy artifacts
./build.sh -m onion  # build the legacy Onion/Omega2 multi-profile image set
./build.sh -d     # prepare the OpenWrt tree and feeds only
./build.sh -D     # reuse the prepared tree and build again
./build.sh -V     # verbose OpenWrt build
```

## Outputs

OpenWrt writes build outputs to:

```sh
openwrt/bin/targets/rockchip/cortexa7
openwrt/bin/packages/arm_cortex-a7_neon-vfpv4
```

The wrapper copies flashable artifacts to:

```sh
bin/images
```

For the default `OEM=onion`, `MODELS=omega4` profile, expected files include:

```sh
openwrt-0.0.11-r1-onion_omega4-evb-boot.img
openwrt-0.0.11-r1-onion_omega4-evb-env.img
openwrt-0.0.11-r1-onion_omega4-evb-rootfs.img
openwrt-0.0.11-r1-onion_omega4-evb-sysupgrade.tar
```

## OEM Files

OEM-specific and model-specific wrapper data lives in:

```sh
onion/supported_models
onion/configs/onion.config
onion/patches/

omega4/supported_models
omega4/configs/omega4.config
omega4/patches/
```

The Omega4 config enables the Rockchip Cortex-A7 target, external kernel tree, AIC8800D SDIO WiFi packages, HPMCU packages, and the Omega4 video/PHY packages.

## Build Notes

- `OEM` names the vendor/output directory. The model config can be resolved from a matching model directory such as `omega4/`.
- The legacy `onion` model config builds the Omega2 and Omega2+ image set.
- The wrapper registers `omega4-kernel-packages` as an OpenWrt feed using an absolute `src-link` path when that feed is present.
- The wrapper sets `CONFIG_EXTERNAL_KERNEL_TREE` to the local `linux-stable` checkout before running `make defconfig`.
- Omega4 produces split flash images (`boot`, `env`, `rootfs`) plus a `sysupgrade.tar`; it does not use the older Omega2 single `.bin` artifact layout.
- Generated repos and artifacts are ignored: `openwrt/`, `linux-stable/`, `omega4-kernel-packages/`, `.prebuilt`, and `bin/`.

## Validation

A successful wrapper build should produce a manifest containing at least:

```sh
aic8800d-firmware
aicrf-test
kmod-aic8800d-sdio
kmod-cfg80211
kmod-mac80211
wpad
```

Basic hardware validation on Omega4 should confirm:

```sh
uname -a
cat /etc/openwrt_release
opkg list-installed | grep -E 'aic|kmod-cfg80211|kmod-mac80211|wpad|iwinfo'
lsmod | grep -E 'aic|cfg80211|mac80211'
iw dev
iwinfo wlan0 scan
```
