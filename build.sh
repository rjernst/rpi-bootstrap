#!/bin/bash

set -x
set -e

IMG_FILE=output/sd.img
rm -f $IMG_FILE
cp output/sd.raw.img $IMG_FILE
# create virtual device files for the partitions through /dev/loop
function loop() {
  LOOP=$(sudo losetup --show -f -P $IMG_FILE)
  function unloop() {
    sudo losetup -d $LOOP
    trap - EXIT
  }
  trap unloop EXIT
}
loop

ROOT=output/root
mkdir -p $ROOT
sudo mount ${LOOP}p2 $ROOT
sudo mount ${LOOP}p1 $ROOT/boot

function unmount() {
  set +e
  sudo umount $ROOT/boot $ROOT
  unloop
  set -e
  trap - EXIT
}
trap unmount EXIT

SETUP_FILE=setup.sh
cat <<EOF > $SETUP_FILE
#!/bin/bash

set -x
set -e

# set timezone
ln -sf /usr/share/zoneinfo/America/Los_Angeles /etc/localtime
# set dummy hostname (changed when installing image)
echo "CHANGEME" > /etc/hostname

# update and install packages
pacman --noconfirm -Syu
pacman --noconfirm -S docker
systemctl enable docker
pacman --noconfirm -S sudo
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# manage users
useradd -m -G wheel,docker rjernst
userdel alarm
su -c "mkdir ~/.ssh && curl https://rjernst.keybase.pub/work_laptop.pubkey >> ~/.ssh/authorized_keys" rjernst
echo "PermitRootLogin no" >> /etc/ssh/sshd_config

EOF
sudo chmod +x $SETUP_FILE
sudo mv $SETUP_FILE $ROOT

sudo cp /usr/bin/qemu-arm-static $ROOT/usr/bin
sudo arch-chroot $ROOT /$SETUP_FILE
sudo rm $ROOT/usr/bin/qemu-arm-static $ROOT/$SETUP_FILE

unmount
loop

sudo zerofree ${LOOP}p2
unloop
gzip $IMG_FILE
