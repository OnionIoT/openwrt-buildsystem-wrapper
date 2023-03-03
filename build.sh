#!/bin/bash

cd `dirname $0`

ROOT_DIR="$PWD"

usage_help() {
	echo "usage: $0
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
-h <help>"

	exit $1
}

apply_patches() {
	[ -z "$PATCH_DIR" ] && return 0
	[ ! -d "$PATCH_DIR" ] && return 0

	[ "$APPLY_PATCH" != "1" ] && return

	[ -z "$OPENWRT_DIR" ] && return 1

	cd "$OPENWRT_DIR"

	for file in $(find $PATCH_DIR -type f -name '*.patch'); do
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
	local feeds_file="$OPENWRT_DIR/feeds.conf.default"

	if [ "$action" == "add" ]; then
		[ -z "$PACKAGES_DIR" ] || [ ! -d "$PACKAGES_DIR" ] && return
		grep -q "$feed_name" "$feeds_file" || echo "src-cpy ${OEM}_packages $PACKAGES_DIR" >> "$feeds_file"
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

prepare_openwrt() {
	[ -z $GIT_OPENWRT ] && GIT_OPENWRT="https://github.com/openwrt/openwrt"

	[ ! -d "$OPENWRT_DIR/.git" ] && git clone "$GIT_OPENWRT" "$OPENWRT_DIR"
	[ ! -d "$OPENWRT_DIR" ] && return 1

	C_TAG=$(git -C "$OPENWRT_DIR" describe --tags)
	if [ "$C_TAG" != "$OPENWRT_TAG" ]; then
		git -C "$OPENWRT_DIR" reset HEAD --hard
		git -C "$OPENWRT_DIR" fetch --all
		git -C "$OPENWRT_DIR" checkout "$OPENWRT_TAG"
	fi

	if [ -d /dl ]; then
		ln -s /dl $OPENWRT_DIR/dl
	elif [ -l /dl ]; then
		ln -s $(readlink /dl) $OPENWRT_DIR/dl
	fi

	return 0
}

prepare_build() {
	[ "$DEV_PREPARE_SKIP" == "1" ] && return 0

	prepare_openwrt
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

	make -C "$OPENWRT_DIR" defconfig
	make -C "$OPENWRT_DIR" V=99
}

copy_model_firmware() {
	local bconfig="$OPENWRT_DIR/.config"
	local target targets

	TARGET_BOARD=$(cat $bconfig | awk -F= '/CONFIG_TARGET_BOARD=/{print $2}' | tr -d '"')
	VERSION_DIST=$(cat $bconfig | awk -F= '/CONFIG_VERSION_DIST=/{print $2}' | tr -d '"' | tr '[A-Z]' '[a-z]')
	VERSION_NUMBER=$(cat $bconfig | awk -F= '/CONFIG_VERSION_NUMBER=/{print $2}' | tr -d '"')
	VERSION_CODE=$(cat $bconfig | awk -F= '/CONFIG_VERSION_CODE=/{print $2}' | tr -d '"' | tr '[A-Z]' '[a-z]')

	[ ! -d "$FW_DIR" ] && mkdir -p "$FW_DIR"

	build_target=$(cat $bconfig | grep "_${build_model}_.*=y" | sed -e "s/CONFIG_TARGET_DEVICE_//g" -e "s/_DEVICE_${build_model}.*//g" | head -1)
	build_board=$(echo $build_target | awk -F_ '{print $2}')
	build_target=$(echo $build_target | awk -F_ '{print $1}')
	targets=$(cat $bconfig | grep "_${build_model}_.*=y" | sed -e "s/CONFIG_TARGET_DEVICE_${build_target}_${build_board}_DEVICE_//g" -e 's/=y//g')

	image_path="$OPENWRT_DIR/bin/targets/${build_target}/${build_board}"

	for target in $targets; do
		image_file="${image_path}/${VERSION_DIST}-${VERSION_NUMBER}-${build_target}-${build_board}-${target}-squashfs-sysupgrade.bin"
		image_prefix=${VERSION_DIST}-${VERSION_NUMBER}-${VERSION_CODE:+${VERSION_CODE}-}${target}

		if [ ! -f "$image_file" ]; then
			echo "ERROR: Image not found"
			exit 1
		else
			cp "$image_file" ${FW_DIR}/${image_prefix}.bin
		fi
	done

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

while getopts m:v:c:o:AKdpCDXh OPT; do
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
		h) usage_help 0 ;;
		*) usage_help 1 ;;
	esac
done

if [ -f "$ROOT_DIR/profile"  ]; then
	. $ROOT_DIR/profile
fi

[ -z "$APPLY_PATCH" ] && APPLY_PATCH=1
[ -z "$DEV_PREPARE" ] && DEV_PREPARE=0
[ -z "$DEV_PREPARE_SKIP" ] && DEV_PREPARE_SKIP=0
[ -z "$DEV_CLEAN_SKIP" ] && DEV_CLEAN_SKIP=0
[ -z "$CLEAN_UP" ] && CLEAN_UP=0
[ -z "$ALL_PACKAGES" ] && ALL_PACKAGES=0
[ -z "$ALL_KMODS" ] && ALL_KMODS=0
[ -z "$OPENWRT_DIR" ] && OPENWRT_DIR="$ROOT_DIR/openwrt"
[ -z "$OPENWRT_TAG" ] && OPENWRT_TAG="v22.03.3"
OEM_DIR="$ROOT_DIR/$OEM"

# validate OEM dir path
if [ ! -d "$OEM_DIR" ]; then
	echo "Vendor data not found"
	exit 1
fi

# validate version arguments
if [ -z "$VERSION" ] || [ -z "$VCODE" ]; then
	echo "VERSON and VCODE is not set"
	usage_help 1
fi

if [ "$APPLY_PATCH" == "1" ]; then
	PATCH_DIR="${OEM_DIR}/patches"
	CONFIG_DIR="${OEM_DIR}/configs"
	MODELS_FILE="${OEM_DIR}/supported_models"
	FILES_DIR="${OEM_DIR}/files"
	PACKAGES_DIR="${OEM_DIR}/packages"
	FW_DIR="${OEM_DIR}/bin/images"
	[ -f "$MODELS_FILE" ] && supported_models="$(cat $MODELS_FILE)"
fi

# validate hardware model
if [ -n "$MODELS" ]; then
	for model in $MODELS; do
		echo "$supported_models" | grep -q -w "$model"
		if [ $? -ne 0 ]; then
			usage_help 1
		fi
	done
else
	MODELS="$supported_models"
fi

trap clean_up INT EXIT TERM
[ "$CLEAN_UP" == "1" ] && exit 1

prepare_build

for build_model in $MODELS; do
	build_firmware "$build_model"
done

exit 0
