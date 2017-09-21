#!/bin/bash

set -e

DISK=$1

if [ -z "$DISK" ]; then
  echo "Usage: install.sh /dev/sdX"
  exit 1
fi

if [ ! -b "$DISK" ]; then
  echo "Unknown partition device: $DISK"
  exit 1
fi

echo "Writing image to $DISK..."
gunzip -c output/sd.img.gz | sudo dd of=$DISK bs=1M status=progress

SECTORS=$( sudo fdisk -l $DISK | grep "Disk $DISK" | awk '{ print $7 }' )
SECTORS=$(( SECTORS - 1 ))
P1_SECTORS=$( sudo fdisk -l $DISK | grep "FAT32" | awk '{ print $4 }' )
P2_SECTORS=$(( SECTORS - P1_SECTORS ))

echo "Extending root partition to end at $SECTORS sectors"
sudo parted $DISK 'unit s resizepart 2 '"$SECTORS"
echo "Correcting filesystem metadata"
sudo e2fsck -f ${DISK}2
echo "Extending root filesystem"
sudo resize2fs ${DISK}2

ROOT=output/root
function mount() {
  echo "Mounting filesystem"
  sudo mount ${DISK}2 $ROOT
  function unmount() {
    sudo umount $ROOT
    trap - EXIT
  }
  trap unmount EXIT
}
mount

SETUP_FILE=setup.sh
cat <<EOF > $SETUP_FILE
#!/bin/bash

set -e

read -p "Enter hostname: " HOSTNAME
echo "\$HOSTNAME" > /etc/hostname

read -p "Enter root password: " -s PASSWORD
chpasswd <<< "root:\$PASSWORD"

EOF
sudo chmod +x $SETUP_FILE
sudo mv $SETUP_FILE $ROOT

sudo cp /usr/bin/qemu-arm-static $ROOT/usr/bin
sudo arch-chroot $ROOT /$SETUP_FILE
sudo rm $ROOT/usr/bin/qemu-arm-static $ROOT/$SETUP_FILE
