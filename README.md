
# OpenWrt Firmware Build Wrapper
Easily build OpenWrt firmware without forking the upstream repo, instead maintain patches and build script which would be applied and clean up when the build starts and stops.

## System Requirements

We recommend using **Ubuntu 22.04** Linux to build this repo with:
* At least 8GB RAM
* A modern, powerful CPU - the more cores on the processor, the faster the build system compilation

See the [OpenWRT Build System Setup instructions](https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem#debianubuntu) for details on what packages are required.

# Directory Structure
This build system wrapper expects directories and files to be maintained in specific structure

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
-V <verbose>
-s <silent output>
-c <version code>
-p <skip custom patch>
-o <dist name>
-d <only prepare dev env>
-D <avoid fresh build instead use patches from the last build>
-X <skip post build cleanup to reuse build env in next build>
-C <only cleanup build env>
-A <build all packages>
-K <build all kernel modules>
-
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
VERBOSE=1            # Same as -V
SILENT=1             # Same as -s
OPENWRT_TAG=v22.03.3 # It would check out and use the openwrt tag before the build
GIT_OPENWRT="https://github.com/openwrt/openwrt" # It would use this URL to clone openwrt
INCLUDE_PACKAGES_M=""  # add packages in build config to be compiled as module package i.e i2c-tools libi2c
INCLUDE_PACKAGES_Y=""  # add packages in build config to be compiled as built-in package i.e i2c-tools libi2c
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

---

# Continuous Deployment

Summary:

|         | Development Builds                                                  | Release Builds                                             |
|:-------:|---------------------------------------------------------------------|------------------------------------------------------------|
| Purpose | Internal use, may not be 100% stable but useful for testing         | Meant for use by general users                             |
| Trigger | Commit to branch                                                    | Github Release created from branch                         |
| Output  | `http://downloads.onioniot.com/builds/$RELEASE_VERSION/$BUILD_DATE` | `http://downloads.onioniot.com/releases/$RELEASE_VERSION/` |

Where:
* `$RELEASE_VERSION` is the `VERSION` from the `profile` config file
* `$BUILD_DATE` is the current date, in the format `%Y%m%d-%H%M%S`

## Development Builds in Branches

When a new branch is created from the default branch in the BuildSystem repository, following the regular expression pattern `openwrt-2\d.\d\d`, an action is automatically triggered in GitHub Actions. This action then creates a new pipeline in AWS CodePipeline using Terraform.

The new pipeline, following the pattern corresponding to the regex openwrt-2\d.\d\d, employs the development buildspec and will be triggered whenever a new commit is made to the branch that generated the creation of this pipeline. The build generated by this pipeline is stored in S3 at s3://$OUTPUT_BUCKET/builds/$RELEASE_VERSION/

When a branch following the regex pattern `openwrt-2\d.\d\d` is deleted, the corresponding pipeline in AWS CodePipeline will be automatically removed through Terraform.

## Newly Created Releases

When a new release is created on GitHub from development branches, it is automatically merged into the `release` branch, triggering the production AWS CodePipeline. The resulting files are stored in the Release S3, overwriting the contents in the bucket s3://$OUTPUT_BUCKET/releases/$RELEASE_VERSION/

## Process: Creating a Release

* Commit update to `profile` that increments the `VCODE` number
* Create a new release:
  * Name the release `<OPENWRT_RELEASE>_<DATE>_<NUMBER>` where `<NUMBER>` is `00` and increments by 1 if there are multiple releases needed in a single day
  * Create a tag that's named same as the release, based on the branch in question
  * Populate the Release description with bullet points outlining what's been Added, Changed, Removed, and/or Fixed
  * Also use generate release notes feature
* Publish the release

