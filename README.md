
# OpenWrt Firmware Build Wrapper
- Easily build OpenWrt firmware without cloning the upstream repo, instead maintain patches and build script which would be applied and clean up when the build starts and stops.

# Directory Structure
- This build system wrapper expects directories and files to be maintained in specific structure

## `build.sh`
It's a main script that does all the jobs to clone and prepare openwrt, apply patches, trigger the build, and then clean up everything.

### Execution flow
- Validate command line arguments
- Check for the `profile` file, If exists, set variables from `profile`
- Validate supported models to build before starting firmware build (`supported_models`)
- Prepare build directory
  - Clone openwrt
  - Checkout openwrt tag
  - link dl directory, If the `dl` location has to be reused
  - If the `OpenWrt` was already cloned before, then clean up previous patches or unstaged files
  - Update feeds
  - Apply dist patches
  - Copy config from the diffconfig (`onion/configs/onion.config`)
  - Set version number and version code
  - Update `.config`, If  all kernel modules/packages has to be enabled (can be defined in profile or from the argument)
- Build Firmware
  - Generate defconfig
  - Start Firmware build
- Copy Firmware
  - Copy firmware into `<dist>/bin/images/openwrt-<version>-<version_code>-<target>.bin`
  - `onion_omega2` firmware location `onion/bin/images/openwrt-v22.02.3-b1-onion_omega2.bin`
  - `onion_omega2p` firmware location `onion/bin/images/openwrt-v22.02.3-b1-onion_omega2p.bin`
- Clean up patches

`build.sh` can take arguments as well as it can read predefined values from the `profile` file.

### Supported arguments
```bash
usage: ./build.sh
-m <build model>
-v <version number>
-c <version code>
-p <skip custom patch>
-o <dist name>
-d <only prepare dev env>
-D <avoid fresh build instead use patches from the last build>
-X <skip post build cleanup to reuse build env in next build>
-C <only cleanup build env>
-A <build all packages>
-K <build all kernel modules>
-h <help>
```

## `profile` 
We can define predefined values in the `profile` file instead of passing them in arguments. Example of default `profile` file

```
VERSION="v22.03.3"   # Same as -v
VCODE="b1"           # Same as -c  
MODELS="onion"       # Same as -m
ALL_KMODS=1          # Same as -K
OEM=onion            # Same as -o
OPENWRT_TAG=v22.03.3 # It would check out and use the openwrt tag before the build
GIT_OPENWRT="https://github.com/openwrt/openwrt" # It would use this URL to clone openwrt
```

## All files specific to custom dist are placed under dir `onion`
In this case, the custom openwrt dist would be onion, so all files specific to onion would be kept under the directory `onion`

### configs
OpenWrt build config, either it can be full `.config` or `diffconfig` generated through `./scripts/diffconfig`, can be kept under this directory. The config file name has to be in format like `<model_name>.config`

In our case, we are creating firmware for all the targets from a single config, we maintain a single config file for model `onion`, So its config file would be `onion.config`
### patches

Instead of directly editing files in the openwrt repor, maintain changes in patches, and all patches must be kept in the `patches` directory, maintain patches with numbering order prefix so they can be applied sequentially.

### `Supported Models`
All supported models have to be maintained in the `supported_models` file.  Models passed in `build.sh` argument or set from `profile` file would be validated against models defined `supported_models` file.

# Create Firmware
Change `profile` file as needed, In most cases it only needs change for version number and version code.

To build firmware,
```./build.sh```

