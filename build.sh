#!/bin/bash

cd `dirname $0`

ROOT_DIR="$PWD"
PREBUILT="$ROOT_DIR/.prebuilt"

usage_help() {
	echo "usage: $0
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
-h <help>"

	exit $1
}

do_run() {
	local exit_code=0

	if [ "$SILENT" = "0" ]; then
		$*
		exit_code=$?
	else
		$* > /dev/null
		exit_code=$?
	fi

	if [ "$exit_code" != "0" ]; then
		echo "ERROR: failed to execute $*"
		exit "$exit_code"
	fi

	return 0
}

prepare_git_repo() {
	local repo_dir=$1
	local git_url=$2
	local git_ref=$3

	[ -z "$git_url" ] && return 1
	[ ! -d "$repo_dir/.git" ] && git clone "$git_url" "$repo_dir"
	[ ! -d "$repo_dir/.git" ] && return 1

	git -C "$repo_dir" fetch --all --tags
	[ -n "$git_ref" ] && git -C "$repo_dir" checkout "$git_ref"

	return 0
}

apply_patches() {
	[ -z "$PATCH_DIR" ] && return 0
	[ ! -d "$PATCH_DIR" ] && return 0

	[ "$APPLY_PATCH" != "1" ] && return

	[ -z "$OPENWRT_DIR" ] && return 1

	cd "$OPENWRT_DIR"

	for file in $(find "$PATCH_DIR" -name '*.patch' -type f | sort); do
		echo "Applying patch: $file"
		if patch -p1 -f --dry-run < $file; then
			patch -p1 -f < $file || return 1
		else
			echo "ERROR: $file"
			return 1
		fi
	done
	cd "$ROOT_DIR"
}

update_oem_feed() {
	[ -z "$OPENWRT_DIR" ] && return 1

	local action=${1:-add}
	local feed_name="${OEM}_packages"
	local kernel_feed_name=${KERNEL_PACKAGES_FEED_NAME:-omega4_kernel_packages}
	local feeds_file="$OPENWRT_DIR/feeds.conf.default"
	local packages_path kernel_packages_path

	if [ "$action" == "add" ]; then
		if [ -n "$PACKAGES_DIR" ] && [ -d "$PACKAGES_DIR" ]; then
			packages_path=$(cd "$PACKAGES_DIR" && pwd)
			sed -i -e "/[[:space:]]$feed_name[[:space:]]/d" "$feeds_file"
			echo "src-cpy ${OEM}_packages $packages_path" >> "$feeds_file"
		fi
		if [ -n "$KERNEL_PACKAGES_DIR" ] && [ -d "$KERNEL_PACKAGES_DIR" ]; then
			kernel_packages_path=$(cd "$KERNEL_PACKAGES_DIR" && pwd)
			sed -i -e "/[[:space:]]$kernel_feed_name[[:space:]]/d" "$feeds_file"
			echo "src-link $kernel_feed_name $kernel_packages_path" >> "$feeds_file"
		fi
	else
		[ -x $OPENWRT_DIR/scripts/feeds ] && $OPENWRT_DIR/scripts/feeds clean
	fi

	return 0
}

clean_patch_junk() {
	[ -z "$OPENWRT_DIR" ] && return 0
	[ ! -d "$OPENWRT_DIR" ] && return 0

	find "$OPENWRT_DIR" \( -name '*.orig' -o -name '*.rej' \) -exec rm -f {} \;
}

revert_patches() {
	[ ! -d "$OPENWRT_DIR" ] && return

	git -C "$OPENWRT_DIR" reset HEAD --hard
	git -C "$OPENWRT_DIR" clean -fd

	if [ -d "$OPENWRT_DIR/feeds" ]; then
		for feeds_dir in $(find "$OPENWRT_DIR/feeds" -type d -name .git); do
			git -C "${feeds_dir%/*}" reset HEAD --hard
			git -C "${feeds_dir%/*}" clean -fd
		done
	fi

	clean_patch_junk
}

clean_up() {
	[ "$DEV_PREPARE" == "1" ] && return 0
	[ "$DEV_CLEAN_SKIP" == "1" ] && return 0

	revert_patches

	[ -d "$OPENWRT_DIR/files" ] && rm -rf "$OPENWRT_DIR/files"
	update_oem_feed del
}

openwrt_version_mismatch() {
	[ -z $GIT_OPENWRT ] && GIT_OPENWRT="https://github.com/openwrt/openwrt"
	[ ! -d "$OPENWRT_DIR/.git" ] && git clone "$GIT_OPENWRT" "$OPENWRT_DIR"
	[ ! -d "$OPENWRT_DIR" ] && return 1

	git -C "$OPENWRT_DIR" fetch --all --tags
	C_TAG=$(git -C "$OPENWRT_DIR" rev-parse HEAD)
	T_TAG=$(git -C "$OPENWRT_DIR" rev-parse "$OPENWRT_TAG^{commit}" 2>/dev/null)

	[[ "$C_TAG" != "$T_TAG" ]]
}

prepare_openwrt() {
	[ -z $GIT_OPENWRT ] && GIT_OPENWRT="https://github.com/openwrt/openwrt"
	prepare_git_repo "$OPENWRT_DIR" "$GIT_OPENWRT" "$OPENWRT_TAG" || return 1

	if [ -n "$GIT_KERNEL" ]; then
		prepare_git_repo "$KERNEL_DIR" "$GIT_KERNEL" "$KERNEL_TAG" || return 1
	fi

	if [ -n "$GIT_KERNEL_PACKAGES" ]; then
		prepare_git_repo "$KERNEL_PACKAGES_DIR" "$GIT_KERNEL_PACKAGES" "$KERNEL_PACKAGES_TAG" || return 1
	fi

	if [ -d /dl ] && [ ! -e "$OPENWRT_DIR/dl" ]; then
		ln -s /dl $OPENWRT_DIR/dl
	elif [ -L /dl ] && [ ! -e "$OPENWRT_DIR/dl" ]; then
		ln -s $(readlink /dl) $OPENWRT_DIR/dl
	fi

	[ -d $ROOT_DIR/keys ] && cp -a $ROOT_DIR/keys/key-* $OPENWRT_DIR/

	return 0
}

prepare_build() {
	[ "$DEV_PREPARE_SKIP" == "1" ] && return 0

	prepare_openwrt || exit 1
	revert_patches
	clean_patch_junk

	update_oem_feed

	[ -d "$FILES_DIR" ] && cp -af "$FILES_DIR" "$OPENWRT_DIR"

	"$OPENWRT_DIR"/scripts/feeds clean
	"$OPENWRT_DIR"/scripts/feeds update -a -f
	"$OPENWRT_DIR"/scripts/feeds install -a -f

	if ! apply_patches; then
		echo "ERROR: applying patches"
		exit 1
	fi

	[ "$DEV_PREPARE" == "1" ] && exit 0
}

prepare_model_config() {
	local model=$1
	local dconfig="$CONFIG_DIR/$model.config"
	local bconfig="$OPENWRT_DIR/.config"

	if [ ! -f "$dconfig" ]; then
		echo "$dconfig not found"
		return 1
	fi

	cp "$dconfig" "$bconfig"

	sed -i -e 's/CONFIG_VERSION_NUMBER=.*/CONFIG_VERSION_NUMBER="'"$VERSION"'"/g' "$bconfig"
	sed -i -e 's/CONFIG_VERSION_CODE=.*/CONFIG_VERSION_CODE="'"$VCODE"'"/g' "$bconfig"
	if [ -n "$KERNEL_DIR" ]; then
		sed -i -e 's|CONFIG_EXTERNAL_KERNEL_TREE=.*|CONFIG_EXTERNAL_KERNEL_TREE="'"$KERNEL_DIR"'"|g' "$bconfig"
	fi
	[ "$ALL_KMODS" == "1" ] && echo "CONFIG_ALL_KMODS=y" >> "$bconfig"
	[ "$ALL_PACKAGES" == "1" ] && echo "CONFIG_ALL=y" >> "$bconfig"

	return 0
}

build_model_firmware() {
	[ -z "$OPENWRT_DIR" ] && return 1
	[ ! -d "$OPENWRT_DIR" ] && return 1

	if [ "$ALL_PACKAGES" == "1" ] || [ "$ALL_KMODS" == "1" ]; then
		export IGNORE_ERRORS="n m"
	fi

	"$OPENWRT_DIR"/scripts/feeds update -a -f
	"$OPENWRT_DIR"/scripts/feeds install -a -f

	for pkg in $INCLUDE_PACKAGES_M; do
		echo "CONFIG_PACKAGE_${pkg}=m" >> $OPENWRT_DIR/.config
	done

	for pkg in $INCLUDE_PACKAGES_Y; do
		echo "CONFIG_PACKAGE_${pkg}=y" >> $OPENWRT_DIR/.config
	done

	do_run make -C "$OPENWRT_DIR" defconfig

	if [ "$VERBOSE" == "1" ]; then
		do_run make -C "$OPENWRT_DIR" -j8 V=99
	else
		do_run make -C "$OPENWRT_DIR" -j8
	fi
}

copy_model_firmware() {
	local bconfig="$OPENWRT_DIR/.config"
	local artifact build_board build_target device_config image_file image_path image_prefix target target_prefix
	local copied=0

	TARGET_BOARD=$(cat $bconfig | awk -F= '/CONFIG_TARGET_BOARD=/{print $2}' | tr -d '"')
	TARGET_SUBTARGET=$(cat $bconfig | awk -F= '/CONFIG_TARGET_SUBTARGET=/{print $2}' | tr -d '"')
	TARGET_PROFILE=$(cat $bconfig | awk -F= '/CONFIG_TARGET_PROFILE=/{print $2}' | tr -d '"' | sed -e 's/^DEVICE_//')
	VERSION_DIST=$(cat $bconfig | awk -F= '/CONFIG_VERSION_DIST=/{print $2}' | tr -d '"' | tr '[A-Z]' '[a-z]')
	VERSION_NUMBER=$(cat $bconfig | awk -F= '/CONFIG_VERSION_NUMBER=/{print $2}' | tr -d '"')
	VERSION_CODE=$(cat $bconfig | awk -F= '/CONFIG_VERSION_CODE=/{print $2}' | tr -d '"' | tr '[A-Z]' '[a-z]')
	[ -z "$VERSION_CODE" ] && VERSION_CODE="$VCODE"

	[ ! -d "$FW_DIR" ] && mkdir -p "$FW_DIR"

	target_configs=$(grep "^CONFIG_TARGET_DEVICE_.*DEVICE_.*${build_model}.*=y" "$bconfig")
	if [ -z "$target_configs" ] && [ -n "$TARGET_PROFILE" ]; then
		target_configs="CONFIG_TARGET_DEVICE_${TARGET_BOARD}_${TARGET_SUBTARGET}_DEVICE_${TARGET_PROFILE}=y"
	fi

	for device_config in $target_configs; do
		target_prefix=$(echo "$device_config" | sed -e "s/^CONFIG_TARGET_DEVICE_//" -e "s/_DEVICE_.*//")
		build_target=$(echo "$target_prefix" | awk -F_ '{print $1}')
		build_board=$(echo "$target_prefix" | cut -d_ -f2-)
		target=$(echo "$device_config" | sed -e "s/^CONFIG_TARGET_DEVICE_${target_prefix}_DEVICE_//" -e "s/=y//")

		image_path="$OPENWRT_DIR/bin/targets/${build_target}/${build_board}"
		image_prefix=${VERSION_DIST}-${VERSION_NUMBER}-${VERSION_CODE:+${VERSION_CODE}-}${target}
		image_file="${image_path}/${VERSION_DIST}-${VERSION_NUMBER}-${build_target}-${build_board}-${target}-squashfs-sysupgrade.bin"
		if [ -f "$image_file" ]; then
			cp "$image_file" ${FW_DIR}/${image_prefix}.bin
			copied=1
		fi

		image_prefix=${VERSION_DIST}-${VERSION_NUMBER}-${VERSION_CODE:+${VERSION_CODE}-}${target}
		if [ -z "$VERSION_DIST" ] || [ -z "$VERSION_NUMBER" ]; then
			VERSION_DIST="openwrt"
			VERSION_NUMBER="$VERSION"
			image_prefix=${VERSION_DIST}-${VERSION_NUMBER}-${VERSION_CODE:+${VERSION_CODE}-}${target}
		fi

		image_file="${image_path}/${VERSION_DIST}-${build_target}-${build_board}-${target}-squashfs-sysupgrade.tar"
		if [ -f "$image_file" ]; then
			cp "$image_file" ${FW_DIR}/${image_prefix}-sysupgrade.tar
			copied=1
		fi

		for artifact in boot env rootfs; do
			image_file="${image_path}/${VERSION_DIST}-${build_target}-${build_board}-${target}-squashfs-${artifact}.img"
			if [ -f "$image_file" ]; then
				cp "$image_file" ${FW_DIR}/${image_prefix}-${artifact}.img
				copied=1
			fi
		done
	done

	if [ "$copied" != "1" ]; then
		echo "ERROR: Image not found"
		exit 1
	fi

	return 0
}

build_firmware() {
	local model=$1

	echo "Prepare firmware config for $build_model"
	prepare_model_config "$build_model" || exit 1

	echo "Create firmware for $build_model"
	build_model_firmware || exit 1

	echo "Copy firmware for $build_model"
	copy_model_firmware "$build_model" || exit 1
}

if [ -f "$ROOT_DIR/profile"  ]; then
	. $ROOT_DIR/profile
fi

while getopts m:v:c:o:AKdpCDXVsh OPT; do
	case $OPT in
		m) MODELS=$OPTARG ;;
		v) VERSION=$OPTARG ;;
		c) VCODE=$OPTARG ;;
		p) APPLY_PATCH=0 ;;
		d) DEV_PREPARE=1 ;;
		C) CLEAN_UP=1 ;;
		D) DEV_PREPARE_SKIP=1 ;;
		X) DEV_CLEAN_SKIP=1 ;;
		o) OEM=$OPTARG ;;
		A) ALL_PACKAGES=1 ;;
		K) ALL_KMODS=1 ;;
		V) VERBOSE=1;;
		s) SILENT=1;;
		h) usage_help 0 ;;
		*) usage_help 1 ;;
	esac
done

[ -z "$APPLY_PATCH" ] && APPLY_PATCH=1
[ -z "$DEV_PREPARE" ] && DEV_PREPARE=0
[ -z "$DEV_PREPARE_SKIP" ] && DEV_PREPARE_SKIP=0
[ -z "$DEV_CLEAN_SKIP" ] && DEV_CLEAN_SKIP=0
[ -z "$CLEAN_UP" ] && CLEAN_UP=0
[ -z "$ALL_PACKAGES" ] && ALL_PACKAGES=0
[ -z "$ALL_KMODS" ] && ALL_KMODS=0
[ -z "$OPENWRT_DIR" ] && OPENWRT_DIR="$ROOT_DIR/openwrt"
[ -z "$KERNEL_DIR" ] && KERNEL_DIR="$ROOT_DIR/linux-stable"
[ -z "$KERNEL_PACKAGES_DIR" ] && KERNEL_PACKAGES_DIR="$ROOT_DIR/omega4-kernel-packages"
[ -z "$OPENWRT_TAG" ] && OPENWRT_TAG="v23.05.3"
[ -z "$VERBOSE" ] && VERBOSE=0
[ -z "$SILENT" ] && SILENT=0
[ -z "$OEM" ] && OEM=onion
OEM_DIR="$ROOT_DIR/$OEM"
BUILD_DATA_DIR="${BUILD_DATA_DIR:-$OEM}"
MODEL_DIR="$ROOT_DIR/$BUILD_DATA_DIR"

# validate OEM output dir path
if [ ! -d "$OEM_DIR" ]; then
	echo "Vendor data not found"
	exit 1
fi

resolve_model_dir() {
	local model supported_models

	[ ! -d "$MODEL_DIR" ] && return 1
	[ -f "$MODEL_DIR/supported_models" ] && supported_models="$(cat "$MODEL_DIR/supported_models")"

	for model in $MODELS; do
		echo "$supported_models" | grep -q -w "$model" && continue

		if [ -f "$ROOT_DIR/$model/supported_models" ] && grep -q -w "$model" "$ROOT_DIR/$model/supported_models"; then
			BUILD_DATA_DIR="$model"
			MODEL_DIR="$ROOT_DIR/$BUILD_DATA_DIR"
			supported_models="$(cat "$MODEL_DIR/supported_models")"
			continue
		fi

		return 1
	done

	return 0
}

# validate version arguments
if [ -z "$VERSION" ] || [ -z "$VCODE" ]; then
	echo "VERSON and VCODE is not set"
	usage_help 1
fi

if [ -n "$MODELS" ]; then
	if ! resolve_model_dir; then
		usage_help 1
	fi
elif [ -f "$MODEL_DIR/supported_models" ]; then
	supported_models="$(cat "$MODEL_DIR/supported_models")"
	MODELS="$supported_models"
else
	usage_help 1
fi

if [ "$APPLY_PATCH" == "1" ]; then
	PATCH_DIR="${MODEL_DIR}/patches"
	CONFIG_DIR="${MODEL_DIR}/configs"
	MODELS_FILE="${MODEL_DIR}/supported_models"
	FILES_DIR="${MODEL_DIR}/files"
	PACKAGES_DIR="${MODEL_DIR}/packages"
	FW_DIR="${ROOT_DIR}/bin/images"
	[ -f "$MODELS_FILE" ] && supported_models="$(cat $MODELS_FILE)"
fi

if [ "$DEV_PREPARE" != "1" ] && [ -f "$PREBUILT" ]; then
	last_hash=$(cat $PREBUILT)
	current_hash=$(find "$PATCH_DIR" -name '*.patch' -type f -print0 | sort -z | xargs -0r cat | md5sum | awk '{print $1}')

	if [ "$last_hash" != "$current_hash" ] || openwrt_version_mismatch; then
		DEV_PREPARE_SKIP=0
	else
		DEV_PREPARE_SKIP=1
	fi
fi

trap clean_up INT EXIT TERM
[ "$CLEAN_UP" == "1" ] && exit 1

prepare_build

for build_model in $MODELS; do
	build_firmware "$build_model"
done

if [ "$DEV_CLEAN_SKIP" == "1" ]; then
	find "$PATCH_DIR" -name '*.patch' -type f -print0 | sort -z | xargs -0r cat | md5sum | awk '{print $1}' > "$PREBUILT"
fi

exit 0
