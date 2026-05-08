# Omega4 Build Support

This branch builds Omega4 firmware from OnionIoT forked repositories because Omega4 support is not upstreamed.

## Repositories

- OpenWrt: `git@github.com:OnionIoT/openwrt-omega4.git`, ref `v0.0.11`
- Kernel: `git@github.com:OnionIoT/linux-stable.git`, ref `openwrt-6.6.93`
- Kernel packages: `git@github.com:OnionIoT/omega4-kernel-packages.git`, ref `master`

The wrapper clones these into `openwrt`, `linux-stable`, and `omega4-kernel-packages` under the wrapper root unless the directories already exist.

## Build

```sh
./build.sh
```

The default `profile` selects:

- `OEM=omega4`
- `MODELS=omega4`
- `OPENWRT_TAG=v0.0.11`

## Output

The OpenWrt build artifacts are produced under:

```sh
openwrt/bin/targets/rockchip/cortexa7
openwrt/bin/packages/arm_cortex-a7_neon-vfpv4
```

The wrapper copies firmware images into:

```sh
omega4/bin/images
```

Expected Omega4 firmware artifacts include:

- `openwrt-<version>-<vcode>-onion_omega4-evb-boot.img`
- `openwrt-<version>-<vcode>-onion_omega4-evb-env.img`
- `openwrt-<version>-<vcode>-onion_omega4-evb-rootfs.img`
- `openwrt-<version>-<vcode>-onion_omega4-evb-sysupgrade.tar`
