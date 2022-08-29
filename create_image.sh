#!/bin/bash

minimal_kmsdrm=0 #do not install x11 or nvidia driver
onlybuild=0 #use existing workdir and only build image

distro="debian" #devuan or debian
release="unstable"
mediahostname="quakeboot"

ezquakegitrepo="https://github.com/ezQuake/ezquake-source.git" #repository to use for ezquake build

currentdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/" >/dev/null 2>&1 && pwd)"
workdir="$currentdir/workdir"
quakedir="quake-base"
clean=1 #clean up previous environment

imagebase="quake_bootable-"
if [ "$minimal_kmsdrm" = "1" ];then
	imageminimal="min_kmsdrm-"
fi
imagename="${imagebase}${imageminimal}$(date +"%Y-%m-%d").img"

lvmdir="$currentdir/lvm"
rclocal="$currentdir/resources/rc.local"
rclocalservice="$currentdir/resources/rc-local.service"
nodm="$currentdir/resources/nodm"
xinitrc="$currentdir/resources/xinitrc"
quakedesktop="$currentdir/resources/quake.desktop"
bashrc="$currentdir/resources/bashrc"
hwclock="$currentdir/resources/hwclock"
compositeconf="$currentdir/resources/01-composite.conf"
sudoers="$currentdir/resources/sudoers"
limitsconf="$currentdir/resources/limits.conf"
background="$currentdir/resources/background.png"
tintrc="$currentdir/resources/tint2rc"
modprobe="$currentdir/resources/modprobe.d"

packages="gnupg ca-certificates wget file git sudo build-essential libgl1-mesa-dri libpcre3-dev terminfo linux-image-amd64 intel-microcode amd64-microcode firmware-linux firmware-linux-nonfree firmware-realtek firmware-iwlwifi iproute2 procps vim-nox unzip zstd alsa-utils grub2 pipewire pipewire-pulse wireplumber"
packages_x11="xserver-xorg-core xserver-xorg-input-all xinit connman connman-gtk feh xterm obconf openbox tint2 fbautostart menu nodm xdg-utils lxrandr dex chromium pasystray pavucontrol"

if [ "$minimal_kmsdrm" != "1" ];then
	packages+=$packages_x11
else
	export minimal_kmsdrm
fi
export packages
export ezquakegitrepo

PATH=$PATH:/sbin:/usr/sbin
required="debootstrap sudo chroot truncate pigz fdisk git"
for require in $required;do
	if ! hash $require >/dev/null 2>&1;then
		echo "required program $require not found, bailing out."
		exit 1
	fi
done

if [ -z "$workdir" ] || [ -z "$currentdir" ];then
	echo "workdir or currentdir not set, bailing out."
	exit 1
fi

#init debootstick submodule
git submodule update --init --recursive >/dev/null 2>&1
git submodule update --recursive --remote >/dev/null 2>&1

if [ ! -e /dev/loop0 ];then
    sudo mknod /dev/loop0 b 7 0
fi

if [ $onlybuild -eq 0 ] || [ ! -d "$workdir/usr" ];then

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
	
	sudo rm -rf "$workdir/etc/modprobe.d"
	sudo cp -rf "$modprobe" "$workdir/etc/"
	sudo cp -f "$rclocal" "$workdir/etc/rc.local"
	sudo mkdir -p "$workdir/etc/systemd/system"
	sudo cp -f "$rclocalservice" "$workdir/etc/systemd/system/rc-local.service"
	if [ -d "$workdir/root/quake" ];then
		sudo rm -rf "$workdir/root/quake"
	fi
	sudo mkdir -p "$workdir/root"
	sudo cp -fR "$quakedir" "$workdir/quake"
	
	sudo --preserve-env=ezquakegitrepo,packages,distro,minimal_kmsdrm chroot "$workdir" bash -e -c '
	
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
	apt-get -qqy install $packages
	
	#log2ram on debian, devuan does not have systemd so the installation will fail
	if [ "$distro" = "debian" ];then
		echo "configuring log2ram..."
		echo "deb http://packages.azlux.fr/debian/ stable main" > /etc/apt/sources.list.d/azlux.list
		wget -qO - https://azlux.fr/repo.gpg.key | apt-key add -
		apt-get -qqy update
		apt-get -qqy install log2ram
	fi

	#configure rc.local
	echo "configuring rc.local"
	chmod +x /etc/rc.local
	(systemctl enable rc-local||true)
	(update-rc.d rc.local enable||true)
	
	#nodm
	if [ "$minimal_kmsdrm" != "1" ];then
		echo "configuring nodm"
		(systemctl enable nodm||true)
		(update-rc.d nodm enable||true)
	fi
	
	#add our user to some groups
	if grep messagebus /etc/group >/dev/null 2>&1;then messagebus="messagebus,";fi
	usermod -a -G ${messagebus}tty,video,audio,games,input,sudo,adm quakeuser
	
	if [ "$minimal_kmsdrm" != "1" ];then
		#configure evte path for openbox running terminal applications
		update-alternatives --install /usr/bin/evte evte /usr/bin/xterm 0
	fi
	
	#configure vim symlink for vim
	update-alternatives --install /usr/bin/vim vim /usr/bin/vi 0
	
	#build ezquake
	echo "building ezquake"
	export CFLAGS="-march=nehalem -flto=$(nproc) -fwhole-program -O3"
	export LDFLAGS="$CFLAGS"
	rm -rf /home/quakeuser/build
	mkdir /home/quakeuser/build
	git clone --depth=1 $ezquakegitrepo /home/quakeuser/build/ezquake-source-official
	cd /home/quakeuser/build/ezquake-source-official
	eval $(grep --color=never PKGS_DEB build-linux.sh|head -n1)
	apt-get -qqy install $PKGS_DEB
	make -j$(nproc)
	strip ezquake-linux-x86_64
	cp -f /home/quakeuser/build/ezquake-source-official/ezquake-linux-x86_64 /home/quakeuser/quake/.
	git clean -qfdx
	
	echo "cleaning up packages"
	#clean up dev packages
	apt-get -qqy purge "*-dev"
	#clean up packages
	apt-get -qqy autopurge
	
	#reinstall ezquake deps
	echo "reinstalling ezquake deps"
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

	if [ "$minimal_kmsdrm" != "1" ];then
		#install nvidia driver
		apt-get -qqy install nvidia-driver nvidia-settings linux-headers-amd64
	fi
	
	#remove package cache
	apt-get -qqy clean 
	
	#clean up lists
	rm -rf /var/lib/apt/lists/*
	
	#configure /tmp as tmpfs
	if [ -f /etc/default/tmpfs ];then
		sed -i "s/#RAMTMP=.*/RAMTMP=yes/g" /etc/default/tmpfs
	fi
	
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

	echo "finished commands within chroot"

	sudo cp -f "$nodm" "$workdir/etc/default/nodm"
	sudo cp -f "$hwclock" "$workdir/etc/default/hwclock"
	sudo cp -f "$xinitrc" "$workdir/home/quakeuser/.xinitrc"
	sudo chmod -f +x "$workdir/home/quakeuser/.xinitrc"
	sudo mkdir -p "$workdir/home/quakeuser/.local/share/applications"
	sudo cp -f "$quakedesktop" "$workdir/home/quakeuser/.local/share/applications/ezQuake.desktop"
	sudo ln -sf "/home/quakeuser/.local/share/applications/ezQuake.desktop" "$workdir/usr/share/applications/ezQuake.desktop"
	sudo mkdir -p "$workdir/home/quakeuser/.config/tint2"
	sudo cp -f "$tintrc" "$workdir/home/quakeuser/.config/tint2/tint2rc"
	
	sudo mkdir -p "$workdir/etc/X11/xorg.conf.d"
	sudo cp -f "$compositeconf" "$workdir/etc/X11/xorg.conf.d/01-composite.conf"
	
	sudo cp -f "$sudoers" "$workdir/etc/sudoers"
	
	sudo cp -f "$limitsconf" "$workdir/etc/security/limits.conf"
	
	sudo cp -f "$bashrc" "$workdir/home/quakeuser/.bashrc"
	sudo cp -f "$background" "$workdir/home/quakeuser/background.png"
	
	#fix ownership for quakeuser
	sudo chroot "$workdir" chown quakeuser:quakeuser -Rf /home/quakeuser
	
	echo "configured chroot"

fi

sudo umount -lf "$workdir/dev/pts" >/dev/null 2>&1
sudo umount -lf "$workdir/proc" >/dev/null 2>&1

export LVM_SYSTEM_DIR=$lvmdir

sudo -E ./debootstick/debootstick --config-kernel-bootargs "+pcie_aspm=off +processor.max_cstate=1 +audit=0 +apparmor=0 +preempt=full +mitigations=off +tsc=reliable -quiet +nosplash" --config-root-password-none --config-hostname $mediahostname "$workdir" "$imagename" 2>/tmp/quake_bootable.err 

if [ $? -eq 0 ];then
	echo "compressing..." && \
	pigz --zip -9 "$imagename" -c > "${imagename}.zip" && \
	ln -sf "${imagename}.zip" quake_bootable-latest.zip
else
	echo "errors in process:"
	cat /tmp/quake_bootable.err
fi

echo "complete."
