#!/bin/bash

clean=1
currentdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/" >/dev/null 2>&1 && pwd)"
workdir="$currentdir/workdir"
release="testing"
ezquakegitrepo="https://github.com/ezQuake/ezquake-source.git"
rclocal="$currentdir/resources/rc.local"
rclocalservice="$currentdir/resources/rc-local.service"
xinitrc="$currentdir/resources/xinitrc"
quakedesktop="$currentdir/resources/quake.desktop"
bashrc="$currentdir/resources/bashrc"
hwclock="$currentdir/resources/hwclock"
compositeconf="$currentdir/resources/01-composite.conf"
quakedir="quake-base"
imagename="quake_bootable-$(date +"%Y-%m-%d").img"


required="debootstrap sudo chroot debootstick truncate"
for require in $required;do
	if ! hash $require >/dev/null 2>&1;then
		echo "required program $require not found, bailing out."
		exit 1
	fi
done


#clean up previous build
if [ -e "$workdir/dev/pts" ];then
	sudo umount -lf "$workdir/dev/pts" >/dev/null 2>&1
	sudo umount -lf "$workdir/proc" >/dev/null 2>&1
fi
if [ $clean -eq 1 ] && [ ! -z "$workdir" ];then
	sudo rm -rf "$workdir"
fi
mkdir -p "$workdir"

sudo debootstrap --include="debian-keyring" --exclude="devuan-keyring" --no-check-gpg --variant=minbase $release "$workdir" https://deb.debian.org/debian/ && \

sudo cp -f "$rclocal" "$workdir/etc/rc.local"
mkdir -p "$workdir/etc/systemd/system"
sudo cp -f "$rclocalservice" "$workdir/etc/systemd/system/rc-local.service"
if [ -d "$workdir/root/quake" ];then
	sudo rm -rf "$workdir/root/quake"
fi
sudo mkdir -p "$workdir/root"
sudo cp -fR "$quakedir" "$workdir/root/quake"

sudo chroot "$workdir" bash -e -c '

chown -f root:root /
chmod -f 755 /

#configure package manager and install packages
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/apt/apt.conf.d
echo "APT::Install-Recommends \"0\";APT::AutoRemove::RecommendsImportant \"false\";" >> /etc/apt/apt.conf.d/01lean
sed -i "s/main$/main contrib non-free/g" /etc/apt/sources.list
apt-get -qqy update
(mount -t devpts devpts /dev/pts||true)
(mount proc /proc -t proc||true)
apt-get -qqy install gnupg wget file git sudo build-essential nvidia-driver nvidia-settings xorg terminfo \
linux-image-amd64 linux-headers-amd64 \
firmware-linux firmware-linux-nonfree firmware-realtek firmware-iwlwifi \
connman connman-gtk cmst iproute2 \
procps vim-tiny \
feh xterm fluxbox menu \
xdg-utils \
lxrandr dex \
alsa-utils \
chromium 

#log2ram
echo "deb http://packages.azlux.fr/debian/ stable main" > /etc/apt/sources.list.d/azlux.list
wget -qO - https://azlux.fr/repo.gpg.key | apt-key add -
apt-get -qqy update
apt-get -qqy install log2ram

`#configure rc.local`
chmod +x /etc/rc.local
(systemctl enable rc-local||true)
(rc-update add rc.local default||true)


`#build ezquake`
export CFLAGS="-march=nehalem -flto=$(nproc) -fwhole-program"
export LDFLAGS="$CFLAGS"
rm -rf /root/build
mkdir /root/build
git clone '$ezquakegitrepo' /root/build/ezquake-source-official
cd /root/build/ezquake-source-official
./build-linux.sh
strip ezquake-linux-x86_64
cp -f /root/build/ezquake-source-official/ezquake-linux-x86_64 /root/quake/.
git clean -qfdx

#remove build
#cd /tmp
#rm -rf /root/build

#remove some dev packages
#apt-get -qqy purge build-essential git

apt-get -qqy autopurge
apt-get -qqy clean 

`#configure /tmp as tmpfs`
sed -i "s/#RAMTMP=.*/RAMTMP=yes/g" /etc/default/tmpfs
'
if [ $? -ne 0 ];then
	echo "something failed, bailing out."
	exit 1
fi
echo "configured chroot"

sudo cp -f "$hwclock" "$workdir/etc/default/hwclock"
sudo cp -f "$xinitrc" "$workdir/root/.xinitrc"
sudo chmod -f +x "$workdir/root/.xinitrc"
sudo mkdir -p "$workdir/root/.local/share/applications"
sudo cp -f "$quakedesktop" "$workdir/root/.local/share/applications/ezQuake.desktop"
sudo mkdir -p "$workdir/root/Desktop"
sudo cp -f "$quakedesktop" "$workdir/root/Desktop/ezQuake.desktop"
sudo xdg-mime default ezQuake.desktop x-scheme-handler/qw

sudo mkdir -p "$workdir/etc/X11/xorg.conf.d"
sudo cp -f "$compositeconf" "$workdir/etc/X11/xorg.conf.d/01-composite.conf"

sudo cp -f "$bashrc" "$workdir/root/.bashrc"

echo "added xinitrc"

sudo umount -lf "$workdir/dev/pts" >/dev/null 2>&1
sudo umount -lf "$workdir/proc" >/dev/null 2>&1

sudo debootstick --config-root-password-none --config-hostname quakeboot "$workdir" "$imagename"

echo "complete."
