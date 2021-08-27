#!/bin/bash

clean=1
currentdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/" >/dev/null 2>&1 && pwd)"
workdir="$currentdir/workdir"
release="testing"
ezquakegitrepo="https://github.com/ezQuake/ezquake-source.git"
rclocal="$currentdir/resources/rc.local"
xinitrc="$currentdir/resources/xinitrc"
quakedesktop="$currentdir/resources/quake.desktop"
bashrc="$currentdir/resources/bashrc"
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
if [ -d "$workdir/quake" ];then
	sudo rm -rf "$workdir/quake"
fi
sudo cp -fR "$quakedir" "$workdir/quake"

sudo chroot "$workdir" bash -e -c '

chown -f root:root /
chmod -f 755 /

`#configure package manager`
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/apt/apt.conf.d
echo "APT::Install-Recommends \"0\";APT::AutoRemove::RecommendsImportant \"false\";" >> /etc/apt/apt.conf.d/01lean
sed -i "s/main$/main contrib non-free/g" /etc/apt/sources.list
apt-get -qqy update
(mount -t devpts devpts /dev/pts||true)
(mount proc /proc -t proc||true)
apt-get -qqy install file git sudo build-essential nvidia-driver nvidia-settings xorg terminfo \
grub2 linux-image-amd64 linux-headers-amd64 \
firmware-linux firmware-linux-nonfree firmware-realtek firmware-iwlwifi \
connman connman-gtk cmst iproute2 \
procps vim-tiny \
feh xterm fluxbox menu \
xdg-utils \
alsa-utils


`#configure rc.local`
if [ -d /etc/systemd/system ];then

echo "[Unit]
Description=/etc/rc.local
ConditionPathExists=/etc/rc.local
 
[Service]
Type=forking
ExecStart=/etc/rc.local start
TimeoutSec=0
StandardOutput=tty
RemainAfterExit=yes
SysVStartPriority=99
 
[Install]
WantedBy=multi-user.target" > /etc/systemd/system/rc-local.service
(systemctl enable rc-local)
fi

chmod +x /etc/rc.local

if hash rc-update >/dev/null 2>&1;then
(rc-update add rc.local default)
fi


`#build ezquake`
rm -rf /build
mkdir /build
git clone '$ezquakegitrepo' /build/ezquake
cd /build/ezquake
./build-linux.sh
eval $(grep --color=never ^PKGS_DEB build-linux.sh)
cd /tmp
cp -f /build/ezquake/ezquake-linux-x86_64 /quake/.
rm -rf /build

#remove some dev packages
apt-get -qqy purge build-essential git
apt-get -qqy autopurge
apt-get -qqy clean 
'
if [ $? -ne 0 ];then
	echo "something failed, bailing out."
	exit 1
fi
echo "configured chroot"

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
