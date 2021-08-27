#!/usr/bin/env bash

set -eo pipefail

DISK=$1
BU=$2

MOUNT_DIR=/mnt/fcos
TMP_DIR=/tmp/fcos

FCOS_BUILD=34.20210821.20.1
IMAGE=fedora-coreos-${FCOS_BUILD}-metal.aarch64.raw.xz
IMAGE_URL=https://builds.coreos.fedoraproject.org/prod/streams/testing-devel/builds/${FCOS_BUILD}/aarch64/${IMAGE}

FIRMWARE_VERSION=1.29
FIRMWARE=RPi4_UEFI_Firmware_v${FIRMWARE_VERSION}.zip
FIRMWARE_URL=https://github.com/pftf/RPi4/releases/download/v${FIRMWARE_VERSION}/${FIRMWARE}

if [[ -z ${DISK} ]] || [[ -z ${BU} ]]; then
	echo "error: supply disk to image and/or path to butane config file"
	echo "usage: $(basename $(readlink -nf "$0")) /dev/sda /tmp/fc.yaml"
	exit 1
fi

if [[ ! "$UID" -eq 0 ]]; then
	echo "This script must be run as root." && exit 1
fi

if ! command podman -h &>/dev/null; then
	echo "Podman is required to run this script." && exit 1
fi

NAME=$(basename "${BU}")
BU=$(realpath "${BU}")
IGN="${NAME%.*}.ign"

if [[ ! -f ${BU} ]]; then
	echo "${BU} does not exist on the system" && exit 1
fi

function cleanup() {
	popd && rm -rf ${MOUNT_DIR} ${TMP_DIR}
}
trap cleanup EXIT

mkdir ${MOUNT_DIR} ${TMP_DIR}
pushd ${TMP_DIR}

set -x

wget ${FIRMWARE_URL}

podman run \
	--rm -v "${BU}":/config.bu:z \
	quay.io/coreos/butane:release --pretty --strict /config.bu >"${IGN}"

podman run \
	--privileged --rm \
	-v /dev:/dev -v /run/udev:/run/udev \
	-v .:/data -w /data \
	quay.io/coreos/coreos-installer:release install "${DISK}" -i "${IGN}" -u ${IMAGE_URL}

mount "${DISK}"2 ${MOUNT_DIR}
unzip ${FIRMWARE} -d ${MOUNT_DIR}
umount ${MOUNT_DIR}

set +x

echo "Complete! Remove the disk and try booting!"
echo "After booting, a reboot is required to remove the 3GB ram limit"
