#!/bin/bash

set -x
set -e

# create an rpi image from arch linux
ARCH_URL=http://os.archlinuxarm.org/os/ArchLinuxARM-rpi-2-latest.tar.gz
INSTALL_FILE=output/arch.tar.gz
if [ ! -f "$INSTALL_FILE" ]; then
  curl -L -o $INSTALL_FILE $ARCH_URL
fi

IMG_FILE=output/sd.raw.img
rm -f $IMG_FILE
mkdir -p output

# create a raw image file with enough space to do a base install
dd if=/dev/zero of=$IMG_FILE count=3906250 # 2GB

# to create the partitions programatically (rather than manually)
# we're going to simulate the manual input to fdisk
# The sed script strips off all the comments so that we can 
# document what we're doing in-line with the actual commands
# Note that a blank line (commented as "defualt" will send a empty
# line terminated with a newline to take the fdisk default.
sed -e 's/\s*\([\+0-9a-zA-Z]*\).*/\1/' << EOF | fdisk $IMG_FILE
  o # clear the in memory partition table
  n # new partition
  p # primary partition
  1 # partition number 1
    # default - start at beginning of disk 
  +100M # 100 MB boot parttion
  t # set partition type
  c # FAT32 partition 
  n # new partition
  p # primary partition
  2 # partion number 2
    # default, start immediately after preceding partition
    # default, extend partition to end of disk
  w # write the partition table
EOF

# create virtual device files for the partitions through /dev/loop
LOOP=$(sudo losetup --show -f -P $IMG_FILE)
function unloop() {
  sudo losetup -d $LOOP
}
trap unloop EXIT

# setup the filesystems
BOOT=output/boot
ROOT=output/root
mkdir -p $BOOT
mkdir -p $ROOT
sudo mkfs.vfat ${LOOP}p1
sudo mkfs.ext4 ${LOOP}p2
sudo mount ${LOOP}p1 $BOOT
sudo mount ${LOOP}p2 $ROOT
function unmount() {
  set +e
  sudo umount $BOOT $ROOT
  unloop
  set -e
}
trap unmount EXIT

sudo bsdtar -xpf $INSTALL_FILE -C $ROOT
sudo sync
sudo mv $ROOT/boot/* $BOOT
