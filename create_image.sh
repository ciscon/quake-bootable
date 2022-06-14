#!/bin/bash

clean=1
currentdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/" >/dev/null 2>&1 && pwd)"
workdir="$currentdir/workdir"
quakedir="quake-base"
imagename="quake_bootable-$(date +"%Y-%m-%d").img"
mediahostname="quakeboot"

distro="debian" #devuan or debian
release="unstable"

ezquakegitrepo="https://github.com/ezQuake/ezquake-source.git"

rclocal="$currentdir/resources/rc.local"
rclocalservice="$currentdir/resources/rc-local.service"
nodm="$currentdir/resources/nodm"
xinitrc="$currentdir/resources/xinitrc"
quakedesktop="$currentdir/resources/quake.desktop"
bashrc="$currentdir/resources/bashrc"
hwclock="$currentdir/resources/hwclock"
nouveauconf="$currentdir/resources/nouveau.conf"
compositeconf="$currentdir/resources/01-composite.conf"
sudoers="$currentdir/resources/sudoers"
limitsconf="$currentdir/resources/limits.conf"
background="$currentdir/resources/background.png"

PATH=$PATH:/sbin:/usr/sbin
required="debootstrap sudo chroot debootstick truncate pigz"
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

if [ "$distro" = "devuan" ];then
	sudo debootstrap --include="devuan-keyring" --exclude="debian-keyring" --no-check-gpg --variant=minbase $release "$workdir" http://deb.devuan.org/merged/
else
	sudo debootstrap --include="debian-keyring" --exclude="devuan-keyring" --no-check-gpg --variant=minbase $release "$workdir" https://deb.debian.org/debian/
fi
export distro

sudo mkdir -p "$workdir/etc/modprobe.d"
sudo cp -f "$nouveauconf" "$workdir/etc/modprobe.d/nouveau.conf"
sudo cp -f "$rclocal" "$workdir/etc/rc.local"
sudo mkdir -p "$workdir/etc/systemd/system"
sudo cp -f "$rclocalservice" "$workdir/etc/systemd/system/rc-local.service"
if [ -d "$workdir/root/quake" ];then
	sudo rm -rf "$workdir/root/quake"
fi
sudo mkdir -p "$workdir/root"
sudo cp -fR "$quakedir" "$workdir/quake"

sudo chroot "$workdir" bash -e -c '

#configure hostname
echo "127.0.1.1 '$mediahostname'" >> /etc/hosts

chown -f root:root /
chmod -f 755 /

useradd -m -p quake -s /bin/bash quakeuser
mv -f /quake /home/quakeuser/.

#configure package manager and install packages
export DEBIAN_FRONTEND=noninteractive
mkdir -p /etc/apt/apt.conf.d
echo "APT::Install-Suggests \"0\";APT::Install-Recommends \"false\";APT::AutoRemove::RecommendsImportant \"false\";" > /etc/apt/apt.conf.d/01lean
echo "path-exclude=/usr/share/doc/*" > /etc/dpkg/dpkg.cfg.d/01_nodoc
rm -rf /usr/share/doc
sed -i "s/main$/main contrib non-free/g" /etc/apt/sources.list
apt-get -qqy update
(mount -t devpts devpts /dev/pts||true)
(mount proc /proc -t proc||true)
apt-get -qqy install gnupg ca-certificates wget file git sudo build-essential \
xserver-xorg-core xserver-xorg-input-all xinit libgl1-mesa-dri terminfo \
linux-image-amd64 \
intel-microcode amd64-microcode \
firmware-linux firmware-linux-nonfree firmware-realtek firmware-iwlwifi \
connman connman-gtk iproute2 \
procps vim \
unzip zstd \
feh xterm obconf openbox tint2 fbautostart menu \
nodm \
xdg-utils \
lxrandr dex \
alsa-utils \
chromium \
grub2

#log2ram on debian, devuan does not have systemd so the installation will fail
if [ "$distro" = "debian" ];then
	echo "deb http://packages.azlux.fr/debian/ stable main" > /etc/apt/sources.list.d/azlux.list
	wget -qO - https://azlux.fr/repo.gpg.key | apt-key add -
	apt-get -qqy update
	apt-get -qqy install log2ram
fi

#configure rc.local
chmod +x /etc/rc.local
(systemctl enable rc-local||true)
(update-rc.d rc.local enable||true)

#nodm
(systemctl enable nodm||true)
(update-rc.d nodm enable||true)

#add our user to some groups
usermod -a -G tty,video,audio,games,messagebus,input,sudo,adm quakeuser

#configure evte path for openbox running terminal applications
update-alternatives --install /usr/bin/evte evte /usr/bin/xterm 0

#configure vim symlink for vim
update-alternatives --install /usr/bin/vim vim /usr/bin/vi 0

#build ezquake
export CFLAGS="-march=nehalem -flto=$(nproc) -fwhole-program"
export LDFLAGS="$CFLAGS"
rm -rf /home/quakeuser/build
mkdir /home/quakeuser/build
git clone --depth=1 '$ezquakegitrepo' /home/quakeuser/build/ezquake-source-official
cd /home/quakeuser/build/ezquake-source-official
eval $(grep --color=never PKGS_DEB build-linux.sh|head -n1)
apt-get -qqy install $PKGS_DEB
make -j$(nproc)
strip ezquake-linux-x86_64
cp -f /home/quakeuser/build/ezquake-source-official/ezquake-linux-x86_64 /home/quakeuser/quake/.
git clean -qfdx

#clean up dev packages
apt-get -qqy purge "*-dev"

#clean up packages
apt-get -qqy autopurge

#reinstall ezquake deps
ezquakedeps=$(apt-get --simulate install $(echo "$PKGS_DEB"|sed "s/build-essential//g") 2>/dev/null|grep --color=never "^Inst"|awk "{print \$2}"|grep --color=never -v "\-dev$"|tr "\n" " ")
if [ ! -z "$ezquakedeps" ];then
  apt-get -qqy install $ezquakedeps
fi

#install afterquake
mkdir -p /home/quakeuser/quake-afterquake
wget -qO /tmp/aq.zip https://fte.triptohell.info/moodles/linux_amd64/afterquake.zip
unzip /tmp/aq.zip -d /home/quakeuser/quake-afterquake
rm /tmp/aq.zip
chown quakeuser:quakeuser -Rf /home/quakeuser/quake-afterquake

#install nvidia driver
apt-get -qqy install nvidia-driver nvidia-settings linux-headers-amd64

#remove package cache
apt-get -qqy clean 

#clean up lists
rm -rf /var/lib/apt/lists/*

#configure /tmp as tmpfs
sed -i "s/#RAMTMP=.*/RAMTMP=yes/g" /etc/default/tmpfs

#configure grub
sed -i "s/GRUB_TIMEOUT.*/GRUB_TIMEOUT=1/g" /etc/default/grub
sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"mitigations=off tsc=reliable nosplash\"/g" /etc/default/grub

rm -rf /tmp/*
rm -rf /var/log/*

#remove temporary resolv.conf
rm -f /etc/resolv.conf
'
if [ $? -ne 0 ];then
	echo "something failed, bailing out."
	exit 1
fi
echo "configured chroot"

sudo cp -f "$nodm" "$workdir/etc/default/nodm"
sudo cp -f "$hwclock" "$workdir/etc/default/hwclock"
sudo cp -f "$xinitrc" "$workdir/home/quakeuser/.xinitrc"
sudo chmod -f +x "$workdir/home/quakeuser/.xinitrc"
sudo mkdir -p "$workdir/home/quakeuser/.local/share/applications"
sudo cp -f "$quakedesktop" "$workdir/home/quakeuser/.local/share/applications/ezQuake.desktop"
sudo ln -sf "/home/quakeuser/.local/share/applications/ezQuake.desktop" "$workdir/usr/share/applications/ezQuake.desktop"

sudo mkdir -p "$workdir/etc/X11/xorg.conf.d"
sudo cp -f "$compositeconf" "$workdir/etc/X11/xorg.conf.d/01-composite.conf"

sudo cp -f "$sudoers" "$workdir/etc/sudoers"

sudo cp -f "$limitsconf" "$workdir/etc/security/limits.conf"

sudo cp -f "$bashrc" "$workdir/home/quakeuser/.bashrc"
sudo cp -f "$background" "$workdir/home/quakeuser/background.png"

#fix ownership for quakeuser
sudo chroot "$workdir" chown quakeuser:quakeuser -Rf /home/quakeuser

echo "added xinitrc"

sudo umount -lf "$workdir/dev/pts" >/dev/null 2>&1
sudo umount -lf "$workdir/proc" >/dev/null 2>&1

sudo debootstick --config-kernel-bootargs "+mitigations=off +tsc=reliable -quiet +nosplash" --config-root-password-none --config-hostname $mediahostname "$workdir" "$imagename" && \
	echo "compressing..." && \
	pigz --zip -9 "$imagename" -c > "${imagename}.zip" && \
	ln -sf "${imagename}.zip" quake_bootable-latest.zip

echo "complete."
