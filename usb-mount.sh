#!/usr/bin/env bash
# If you are executing this script in cron with a restricted environment,
# modify the shebang to specify appropriate path; /bin/bash in most distros.
# And, also if you aren't comfortable using(abuse?) env command.

# This script is based on https://serverfault.com/a/767079 posted
# by Mike Blackwell, modified to our needs. Credits to the author.

# This script is called from systemd unit file to mount or unmount
# a USB drive.

# Global mount options
OPTS="rw,noatime,group,fmask=0117,dmask=0007"
MOUNT_DIR="/media"
GROUP_NAME="storage"

###########################################################################

PATH="$PATH:/usr/bin:/usr/local/bin:/usr/sbin:/usr/local/sbin:/bin:/sbin"
log="logger -t usb-mount.sh -s "


usage()
{
    ${log} "Usage: $0 {add|remove} device_name (e.g. sdb1)"
    exit 1
}

if [[ $# -ne 2 ]]; then
    usage
fi

ACTION=$1
DEVBASE=$2
DEVICE="/dev/${DEVBASE}"

# See if this drive is already mounted, and if so where
MOUNT_POINT=$(mount | grep ${DEVICE} | awk '{ print $3 }')

DEV_LABEL=""

do_mount()
{
    # Get group id for mount option
    if [ "${GROUP_NAME}" ]; then
        GROUP_ID=$(getent group storage | awk -F: '{printf "%d", $3}')
        if [ "${GROUP_ID}" ]; then
            OPTS+=",gid=${GROUP_ID}"
        else
            ${log} "Warning: Invalid group name ${GROUP_NAME}"
            exit 1
        fi
    fi
    
    # Exit if already mounted
    if [[ -n ${MOUNT_POINT} ]]; then
        ${log} "Warning: ${DEVICE} is already mounted at ${MOUNT_POINT}"
        exit 1
    fi
    
    # adapted/copied from https://github.com/Ferk/udev-media-automount/blob/master/media-automount
    fstab=$(grep /etc/fstab -e "^[ \t]*${DEVICE}[ \t]")
    # Don't manage devices that are already in fstab
    if [ "$fstab" ]; then
       ${log} "${DEVICE} already in /etc/fstab, skipping: ${fstab/[ \t][ \t]/ }"
       exit 1
    fi

    # Get info for this drive: $ID_FS_LABEL and $ID_FS_TYPE
    eval $(blkid -o udev ${DEVICE} | grep -i -e "ID_FS_LABEL" -e "ID_FS_TYPE")

    # Figure out a mount point to use
    LABEL=${ID_FS_LABEL}
    if grep -q " /media/${LABEL} " /etc/mtab; then
        # Already in use, make a unique one
        LABEL+="-${DEVBASE}"
    fi
    DEV_LABEL="${LABEL}"

    # Use the device name in case the drive doesn't have label
    if [ -z ${DEV_LABEL} ]; then
        DEV_LABEL="${DEVBASE}"
    fi

    MOUNT_POINT="${MOUNT_DIR}/${DEV_LABEL}"

    ${log} "Mount point: ${MOUNT_POINT}"

    mkdir -p ${MOUNT_POINT}

    # File system type specific mount options
    if [[ ${ID_FS_TYPE} == "vfat" ]]; then
        OPTS+=",users,shortname=mixed,utf8=1,flush"
    fi

    if ! mount -o ${OPTS} ${DEVICE} ${MOUNT_POINT}; then
        ${log} "Error mounting ${DEVICE} (status = $?)"
        rmdir "${MOUNT_POINT}"
        exit 1
    else
        # Track the mounted drives
        echo "${MOUNT_POINT}:${DEVBASE}" | cat >> "/var/log/usb-mount.track" 
    fi

    ${log} "Mounted ${DEVICE} at ${MOUNT_POINT}"
}

do_unmount()
{
    if [[ -z ${MOUNT_POINT} ]]; then
        ${log} "Warning: ${DEVICE} is not mounted"
    else
        umount -l ${DEVICE}
	${log} "Unmounted ${DEVICE} from ${MOUNT_POINT}"
        /bin/rmdir "${MOUNT_POINT}"
        sed -i.bak "\@${MOUNT_POINT}@d" /var/log/usb-mount.track
    fi


}

case "${ACTION}" in
    add)
        do_mount
        ;;
    remove)
        do_unmount
        ;;
    *)
        usage
        ;;
esac
