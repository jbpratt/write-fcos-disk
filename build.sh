#!/usr/bin/env bash

set -eo pipefail

DISK=$1
BU=$2
ARCH=${3:-x86_64}
RPI=$4

FCOS_BUILD=34.20210821.3.0
IMAGE=fedora-coreos-${FCOS_BUILD}-metal.${ARCH}.raw.xz
IMAGE_URL=https://builds.coreos.fedoraproject.org/prod/streams/stable/builds/${FCOS_BUILD}/${ARCH}/${IMAGE}

MOUNT_DIR=/mnt/fcos
TMP_DIR=/tmp/fcos

if [[ -n "${RPI}" ]]; then
	echo "imaging for RPi"
	FIRMWARE_VERSION=1.29
	FIRMWARE=RPi4_UEFI_Firmware_v${FIRMWARE_VERSION}.zip
	FIRMWARE_URL=https://github.com/pftf/RPi4/releases/download/v${FIRMWARE_VERSION}/${FIRMWARE}
fi

if [[ -z ${DISK} ]] || [[ -z ${BU} ]] || [[ ! ${ARCH} == @(x86_64|aarch64) ]]; then
	echo "error: supply disk to image, path to butane config file and optionally the arch"
	echo "usage: $(basename $(readlink -nf "$0")) /dev/sda /tmp/fc.yaml aarch64 rpi"
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

echo "Executing butane on ${BU}"
podman run \
	--rm -v "${BU}":/config.bu:z \
	quay.io/coreos/butane:release --pretty --strict /config.bu >"${IGN}"

echo "Downloading FCOS ${FCOS_BUILD} and writing it to ${DISK}"
podman run \
	--privileged --rm \
	-v /dev:/dev -v /run/udev:/run/udev \
	-v .:/data -w /data \
	quay.io/coreos/coreos-installer:release install "${DISK}" -i "${IGN}" -u ${IMAGE_URL}

if [[ -n ${RPI} ]]; then
	echo "Downloading RPi firmware (${FIRMWARE_VERSION}) and writing to ${DISK}2"
	wget ${FIRMWARE_URL}
	mount "${DISK}"2 ${MOUNT_DIR}
	unzip ${FIRMWARE} -d ${MOUNT_DIR}
	umount ${MOUNT_DIR}
fi
