#!/bin/bash

# Usage: 
# arch-install.sh /dev/disk/by-id/nvme-<device> username

set -e

DEVICE="$1"
PARTITION="$DEVICE-part1"
POOL=rpool
CHROOT="/mnt"
DEFAULTUSER="${2:-anon}"

install() {
 check_prerequisites
 prepare_disk
 create_zpool
 create_zfs_datasets
 export_zfs_pool
 import_zfs_pool
 prepare_chroot
 configure_system
 create_user
 initialize_keyring
 import_zfs_gpg_key
 install_base_packages
 enable_zfs_mount
 install_desktop_packages
 enable_services
 configure_gnome
}

run_chroot() {
  echo "Running $CHROOT this: $@"
  arch-chroot "$CHROOT" "$@"
  local status=$?
  echo "Result: $status"
}

rr_snapshot() {
#rollback & remove
  local step=$1
  local snapexists=$(zfs list -H -t snapshot | grep "installer_$step" | wc -l)

  if [[ $snapexists -eq 0 ]]; then
    return 0
  fi

  zfs rollback -R "$POOL/root@installer_$step"
  zfs rollback -R "$POOL/home@installer_$step"
  zfs destroy -R "$POOL/root@installer_$step"
  zfs destroy -R "$POOL/home@installer_$step"
}

do_snapshot() {
  local step=${FUNCNAME[1]}
  rr_snapshot $step
  zfs snapshot -r "$POOL/root@installer_$step"
  zfs snapshot -r "$POOL/home@installer_$step"
}

stepinfo() {
  local caller=${FUNCNAME[1]}
  echo "Step $caller"
}

create_user() {
  stepinfo
  do_snapshot
  run_chroot useradd -m -G users,wheel,audio,video,lp,scanner $DEFAULTUSER  
  run_chroot passwd -d $DEFAULTUSER
}

enable_zfs_mount() {
  stepinfo
  do_snapshot
  run_chroot systemctl enable zfs-mount.service
  run_chroot systemctl enable zfs.target
}

enable_services() {
  stepinfo
  do_snapshot
  run_chroot systemctl enable avahi-daemon.service
  run_chroot systemctl enable avahi-daemon.socket
  run_chroot systemctl enable bluetooth.service
  run_chroot systemctl enable containerd.service
  run_chroot systemctl enable cups.service
  run_chroot systemctl enable cups.path
  run_chroot systemctl enable docker.service
  run_chroot systemctl enable gdm.service
  run_chroot systemctl enable NetworkManager.service
  run_chroot systemctl enable zfs-zed.service
}

configure_gnome() {
  stepinfo
  do_snapshot
  echo -e "[org.gnome.desktop.input-sources]\nsources=[('xkb', 'de+nodeadkeys')]" > \
  $CHROOT/usr/share/glib-2.0/schemas/10_org.gnome.desktop.input-sources.gschema.override
  run_chroot glib-compile-schemas /usr/share/glib-2.0/schemas/
}

initialize_keyring() {
  stepinfo
  do_snapshot
  run_chroot pacman-key --init
  run_chroot pacman-key --refresh-keys 
  run_chroot pacman-key --populate archlinux
}

import_zfs_gpg_key() {
  stepinfo
  do_snapshot
  run_chroot curl --fail-early --fail -L -o /var/tmp/archzfs.gpg https://archzfs.com/archzfs.gpg
  run_chroot pacman-key -a /var/tmp/archzfs.gpg
  run_chroot pacman-key --lsign-key DDF7DB817396A49B2A2723F7403BD972F75D9D76 
}

configure_system() {
  stepinfo
  do_snapshot
  sed -i 's/#\(de_DE.UTF-8\)/\1/' $CHROOT/etc/locale.gen
  sed -i 's/#\(en_US.UTF-8\)/\1/' $CHROOT/etc/locale.gen
  echo 'LANG=de_DE.UTF-8' >> $CHROOT/etc/locale.conf
  echo 'KEYMAP=de-latin1-nodeadkeys' >> $CHROOT/etc/vconsole.conf
  echo 'FONT=eurlatgr' >> $CHROOT/etc/vconsole.conf
  echo 'arch' >> $CHROOT/etc/hostname
  echo '[archzfs]' >> $CHROOT/etc/pacman.conf
  echo 'Server = http://archzfs.com/archzfs/x86_64' >> $CHROOT/etc/pacman.conf
  echo 'Server = http://mirror.sum7.eu/archlinux/archzfs/archzfs/x86_64' >> $CHROOT/etc/pacman.conf
  echo 'Server = https://mirror.biocrafting.net/archlinux/archzfs/archzfs/x86_64' >> $CHROOT/etc/pacman.conf

  sed -i 's/^MODULES=(\(.*\))/MODULES=(\1zfs)/' $CHROOT/etc/mkinitcpio.conf
  sed -i 's/^\(HOOKS=(.*\)\(filesystems.*)\)/\1zfs \2/' $CHROOT/etc/mkinitcpio.conf

  echo "export USER_ID=\$(id -u)" > $CHROOT/etc/profile.d/envs.sh
  echo "export GROUP_ID=\$(id -g)" >> $CHROOT/etc/profile.d/envs.sh

  run_chroot ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime
  run_chroot locale-gen

  # enable wheel group for sudoers
  echo "%wheel ALL=(ALL:ALL) ALL" >  $CHROOT/etc/sudoers.d/wheel
  chmod 040 $CHROOT/etc/sudoers.d/wheel
}

install_base_packages() {
# dmg2img
  stepinfo
  do_snapshot
  run_chroot pacman --noconfirm -v -Sy --needed archiso autoconf automake baobab base base-devel binutils \
  bison file file-roller gcc libtool m4 make man-db mkcert zfs-dkms zfs-utils
}

install_desktop_packages() {
# dmg2img
  stepinfo
  do_snapshot
  run_chroot pacman --noconfirm -v -Sy --needed noto-fonts-emoji ttf-liberation pipewire-jack cheese cups cups-pdf docker docker-buildx docker-compose \
  eog epiphany evince fakeroot findutils firefox \
  freecad fwupd gawk gdm gedit gettext gimp git gnome-backgrounds gnome-boxes gnome-calculator gnome-calendar gnome-characters gnome-clocks gnome-color-manager gnome-contacts \
  gnome-control-center gnome-disk-utility gnome-font-viewer gnome-keyring gnome-logs gnome-maps gnome-menus gnome-music gnome-photos gnome-remote-desktop gnome-screenshot gnome-session \
  gnome-settings-daemon gnome-shell gnome-shell-extensions gnome-software gnome-system-monitor gnome-terminal gnome-tweaks gnome-user-docs gnome-video-effects gnome-weather \
  gparted grep grilo-plugins groff gst-libav gthumb gvfs gvfs-afc gvfs-goa gvfs-google gvfs-gphoto2 gvfs-mtp gvfs-nfs gvfs-smb \
  gzip htop img2pdf inetutils jq keepassxc keychain \
  libreoffice-still libreoffice-still-de \
  lshw meld mutter mysql-workbench nautilus net-tools networkmanager nmap obs-studio openbsd-netcat openshot \
  openvpn pacman pacman-contrib patch pipewire-pulse pkgconf python-pyqt6 qt6-wayland qt6-multimedia-ffmpeg rygel siege simple-scan sushi texinfo tftp-hpa thunderbird tmux \
  totem tracker3-miners tree v4l2loopback-dkms vi vim vlc vulkan-intel wimlib wireshark-qt wl-clipboard xdg-user-dirs-gtk xsane-gimp yelp zsh-completions
}

check_prerequisites() {
  stepinfo
  local prefix="/dev/disk/by-id/"
  if [ -z "$DEVICE" ]; then
    echo "Device must be passed as argument"
    exit 1
  fi

  if [[ "$DEVICE" != "$prefix"* ]]; then
    echo "Device path must contain $prefix"
    exit 1
  fi

  local type=$(lsblk -no TYPE $DEVICE)

    if [[ "$type" != "disk" ]]; then
    echo "Device must be a disk"
    exit 1
  fi

  if partx --show $DEVICE > /dev/null 2>&1; then
    echo "The device already has partitions"
    exit 1
  fi
}

create_zpool() {
  stepinfo
  zpool create \
    -o ashift=12 \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=none \
    $POOL $PARTITION
}

create_zfs_datasets() {
  # root
  stepinfo
  zfs create \
   -o canmount=noauto \
   -o mountpoint=/ \
   -o refquota=480G \
   "$POOL/root"

  zpool set bootfs="$POOL/root" $POOL
  
  zfs set org.zfsbootmenu:commandline="rw loglevel=4" $POOL/root

  # home

  zfs create \
   -o canmount=on \
   -o mountpoint=/home \
   "$POOL/home"

  # tmp

  zfs create \
   -o canmount=on \
   -o mountpoint=/tmp \
   "$POOL/tmp"

  # docker

  zfs create \
   -o canmount=on \
   -o mountpoint=/var/lib/docker \
   "$POOL/docker"
}

export_zfs_pool() {
  stepinfo
  zpool export $POOL
}

import_zfs_pool() {
  stepinfo
  zpool import -f -N -d $PARTITION -R $CHROOT $POOL
  zpool set cachefile=/etc/zfs/zpool.cache $POOL
  zfs mount "$POOL/root"
  zfs mount -a
}

prepare_chroot() {
  stepinfo
  do_snapshot
  mkdir -p "$CHROOT/etc/zfs"
  cp /etc/zfs/zpool.cache "$CHROOT/etc/zfs/zpool.cache"
  pacstrap -K $CHROOT base linux-lts linux-firmware efibootmgr \
  nano mesa xf86-video-vmware openssl-1.1 rsync sed sl sudo wget \
  which zsh linux-lts-headers
}

prepare_disk() {
  stepinfo
  parted --script $DEVICE mklabel gpt mkpart primary 0% 100%
  sgdisk --typecode=1:BF00 $DEVICE

  local partcheck=$(timeout 30s bash -c "until partprobe -d $PARTITION; do sleep 1; done")
  if [[ $partcheck -ne 0 ]]; then
    echo "Could not validate partition: $PARTITION"
    exit 1
  fi
}

install
