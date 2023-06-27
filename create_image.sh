#!/bin/bash -e

minimal_kmsdrm=${KMSDRM:-0} #do not install x11 or nvidia driver
onlybuild=0 #use existing workdir and only build image

distro="debian" #devuan or debian
release="unstable"
mediahostname="quakeboot"

ezquakegitrepo="https://github.com/ezQuake/ezquake-source.git" #repository to use for ezquake build

#nquake resources
nquakeresourcesurl="https://github.com/nQuake/distfiles/releases/download/snapshot"
nquakeresourcesurl_backup="https://github.com/ciscon/distfiles/releases/download/snapshot"
nquakezips="gpl.zip non-gpl.zip"


builddate=$(date +%s)
gitcommit=$(git log -n 1|head -1|awk '{print $2}'|cut -c1-6)
githubref=${GITHUB_REF_NAME:-v0}
release_ver="${githubref}-${builddate}~${gitcommit}"

currentdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/" >/dev/null 2>&1 && pwd)"
workdir="$currentdir/workdir"
quakedir="quake-base"
clean=1 #clean up previous environment

imagebase="quake_bootable"
if [ "$minimal_kmsdrm" = "1" ];then
	imagesuffix="-min_kmsdrm"
else
	imagesuffix="-full"
fi

#for releases - without a target dir this means we're doing the build on github
targetdir="/mnt/nas-quake/quake_bootable"
if [ -d "$targetdir" ];then
	imagename="${imagebase}${imagesuffix}-$(date +"%Y-%m-%d").img"
	imagelatestname="${imagebase}${imagesuffix}-latest"
else
	imagename="${imagebase}${imagesuffix}.img"
fi

lvmdir="$currentdir/lvm"
xresources="$currentdir/resources/xresources"
pipewire="$currentdir/resources/pipewire.conf"
drirc="$currentdir/resources/drirc"
rclocal="$currentdir/resources/rc.local"
rclocalservice="$currentdir/resources/rc-local.service"
xinitrc="$currentdir/resources/xinitrc"
bashrc="$currentdir/resources/bashrc"
profile="$currentdir/resources/profile"
profilemessages="$currentdir/resources/profile_messages"
hwclock="$currentdir/resources/hwclock"
compositeconf="$currentdir/resources/01-composite.conf"
sudoers="$currentdir/resources/sudoers"
limitsconf="$currentdir/resources/limits.conf"
background="$currentdir/resources/background.png"
tintrc="$currentdir/resources/tint2rc"
modprobe="$currentdir/resources/modprobe.d"
issueappend="$currentdir/resources/issue.append"

packages="iputils-ping openssh-client file git sudo build-essential libgl1-mesa-dri libpcre3-dev terminfo procps vim-tiny unzip zstd alsa-utils grub2 cpufrequtils fbset chrony cloud-utils parted lvm2 gdisk initramfs-tools fdisk intel-microcode amd64-microcode firmware-linux firmware-linux-nonfree firmware-linux-free libarchive-tools linux-image-amd64 ntfs-3g nfs-common "
packages_nox11="ifupdown dhcpcd-base"
packages_x11=" xserver-xorg-legacy xserver-xorg-core xserver-xorg-video-amdgpu xserver-xorg-input-all xinit iw connman connman-gtk feh xterm obconf openbox tint2 fbautostart menu python3-xdg xdg-utils lxrandr dex chromium pasystray pavucontrol pipewire pipewire-pulse wireplumber rtkit dex x11-xserver-utils dbus-x11 dbus-bin imagemagick pcmanfm gvfs-backends lxpolkit "

if [ "$minimal_kmsdrm" != "1" ];then
	packages+=$packages_x11
else
	packages+=$packages_nox11
	export minimal_kmsdrm
fi
export packages
export ezquakegitrepo
export nquakeresourcesurl
export nquakeresourcesurl_backup
export nquakezips

PATH=$PATH:/sbin:/usr/sbin
required="debootstrap sudo chroot truncate pigz fdisk git kpartx losetup uuidgen pvscan"
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
	if [ -e "$workdir/dev/pts/ptmx" ];then
		sudo umount -qlf "$workdir/dev/pts"||true >/dev/null 2>&1
		sudo umount -qlf "$workdir/proc"||true >/dev/null 2>&1
	fi
	if [ $clean -eq 1 ] && [ ! -z "$workdir" ];then
		sudo rm -rf "$workdir"
	fi
	mkdir -p "$workdir"
	
	if [ "$distro" = "devuan" ];then
		sudo debootstrap --include="devuan-keyring gnupg wget ca-certificates" --exclude="debian-keyring" --no-check-gpg --variant=minbase $release "$workdir" http://dev.beard.ly/devuan/merged/
	else
		sudo debootstrap --include="debian-keyring gnupg wget ca-certificates" --exclude="devuan-keyring" --no-check-gpg --variant=minbase $release "$workdir" https://deb.debian.org/debian/
	fi
	export distro
	
	sudo rm -rf "$workdir/etc/modprobe.d"
	sudo cp -rf "$modprobe" "$workdir/etc/"
	sudo mkdir -p "$workdir/etc/systemd/system"
	sudo cp -f "$rclocalservice" "$workdir/etc/systemd/system/rc-local.service"
	if [ -d "$workdir/root/quake" ];then
		sudo rm -rf "$workdir/root/quake"
	fi
	sudo mkdir -p "$workdir/root"
	sudo cp -fR "$quakedir" "$workdir/quake"
	sudo cp -f "$background" "$workdir/background.png"

	sudo --preserve-env=nquakeresourcesurl,nquakeresourcesurl_backup,nquakezips,ezquakegitrepo,packages,distro,minimal_kmsdrm chroot "$workdir" bash -e -c '
	
	#configure hostname
	echo "127.0.1.1 '$mediahostname'" >> /etc/hosts
	
	chown -f root:root /
	chmod -f 755 /
	
	useradd -m -p quake -s /bin/bash quakeuser
	mv -f /quake /home/quakeuser/.
	echo -e "quakeuser\nquakeuser" | passwd quakeuser
	
	#configure package manager and install packages
	export DEBIAN_FRONTEND=noninteractive
	mkdir -p /etc/apt/apt.conf.d
	echo "APT::Install-Suggests \"0\";APT::Install-Recommends \"false\";APT::AutoRemove::RecommendsImportant \"false\";" > /etc/apt/apt.conf.d/01lean
	echo "path-exclude=/usr/share/doc/*" > /etc/dpkg/dpkg.cfg.d/01_nodoc
	rm -rf /usr/share/doc
	echo "path-exclude=/usr/share/man/*" > /etc/dpkg/dpkg.cfg.d/01_noman
	rm -rf /usr/share/man
	echo "path-exclude=/usr/share/locale/*" > /etc/dpkg/dpkg.cfg.d/01_nolocale
	rm -rf /usr/share/locale
	sed -i "s/main$/main contrib non-free non-free-firmware/g" /etc/apt/sources.list

	##xanmod
	#echo "deb http://deb.xanmod.org releases main" > /etc/apt/sources.list.d/xanmod.list
	#gpg --keyserver keyserver.ubuntu.com --recv-keys 86F7D09EE734E623 || \
	#	gpg --keyserver pgp.mit.edu --recv-keys 86F7D09EE734E623 
	#gpg --output - --export --armor > /tmp/xanmod.gpg
	#APT_KEY_DONT_WARN_ON_DANGEROUS_USAGE=1 apt-key --keyring /etc/apt/trusted.gpg.d/xanmod-kernel.gpg add /tmp/xanmod.gpg
	#rm -f /tmp/xanmod.gpg

	apt-get -qy update
	(mount -t devpts devpts /dev/pts||true)
	(mount proc /proc -t proc||true)

	#apt-get -qy install $packages

	#install firmware from git?
	#rm -rf /lib/firmware
	#git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git /lib/firmware

	#version
	echo -n "'${release_ver}'" > /version

	#replace systemd with openrc, multiple steps required
	if [ "$distro" = "debian" ];then
		if [ "$minimal_kmsdrm" != "1" ];then
			elogind="elogind libpam-elogind"
		fi
		apt-get -qy install openrc sysvinit-core
		apt-get -qy install $elogind orphan-sysvinit-scripts systemctl procps
		apt-get -qy purge systemd
		apt-get -qy purge systemctl
	fi

	#reinstall packages that may have been removed by systemd purge
	apt-get -qy install $packages
	
	##log2ram on debian, devuan does not have systemd so the installation will fail
	#if [ "$distro" = "debian" ];then
	#	echo "configuring log2ram..."
	#	echo "deb http://packages.azlux.fr/debian/ stable main" > /etc/apt/sources.list.d/azlux.list
	#	wget -qO - https://azlux.fr/repo.gpg.key | sudo gpg --dearmour -o /etc/apt/trusted.gpg.d/azlux.gpg
	#	apt-get -qy update
	#	apt-get -qy install log2ram
	#fi

	#configure rc.local
	echo "configuring rc.local"
	chmod +x /etc/rc.local
	#(systemctl enable rc-local||true)
	(update-rc.d rc.local enable||true)
	
	#nodm
	#if [ "$minimal_kmsdrm" != "1" ];then
	#	echo "configuring nodm"
	#	(systemctl enable nodm||true)
	#	(update-rc.d nodm enable||true)
	#fi
	
	#add our user to some groups
	if grep messagebus /etc/group >/dev/null 2>&1;then messagebus="messagebus,";fi
	usermod -a -G ${messagebus}tty,video,audio,games,input,sudo,adm,plugdev quakeuser
	
	if [ "$minimal_kmsdrm" != "1" ];then
		#configure evte path for openbox running terminal applications
		update-alternatives --install /usr/bin/evte evte /usr/bin/xterm 0
	fi
	
	#configure vim symlink for vim
	update-alternatives --install /usr/bin/vim vim /usr/bin/vi 0
	
	#build ezquake
	echo "building ezquake"
	export CFLAGS="-pipe -march=nehalem -O3 -flto=$(nproc) -flto-partition=balanced -ftree-slp-vectorize -ffp-contract=fast -fno-defer-pop -finline-limit=64 -fmerge-all-constants"
	export LDFLAGS="$CFLAGS"
	rm -rf /home/quakeuser/build
	mkdir /home/quakeuser/build
	git clone --depth=1 $ezquakegitrepo /home/quakeuser/build/ezquake-source-official
	cd /home/quakeuser/build/ezquake-source-official
	eval $(grep --color=never PKGS_DEB build-linux.sh|head -n1)
	apt-get -qy install $PKGS_DEB
	git submodule update --init --recursive --remote
	make -j$(nproc)
	strip ezquake-linux-x86_64
	cp -f /home/quakeuser/build/ezquake-source-official/ezquake-linux-x86_64 /home/quakeuser/quake/.
	git clean -qfdx
	
	echo "cleaning up packages"
	#clean up dev packages
	apt-get -qy purge build-essential || true
	#apt-get -qy purge "*-dev"
	#clean up packages
	apt-get -qy autopurge
	
	#reinstall ezquake deps
	echo "reinstalling ezquake deps"
	ezquakedeps=$(apt-get --simulate install $(echo "$PKGS_DEB"|sed "s/build-essential//g") 2>/dev/null|grep --color=never "^Inst"|awk "{print \$2}"|grep --color=never -v "\-dev$"|tr "\n" " ")
	if [ ! -z "$ezquakedeps" ];then
	  apt-get -qy install $ezquakedeps
	fi

	#openrazer and kernel headers	
	apt-get -qy install openrazer-driver-dkms linux-headers-amd64

	if [ "$minimal_kmsdrm" != "1" ];then
		#install afterquake
		mkdir -p /home/quakeuser/quake-afterquake
		wget -qO /tmp/aq.zip https://fte.triptohell.info/moodles/linux_amd64/afterquake.zip
		unzip /tmp/aq.zip -d /home/quakeuser/quake-afterquake
		rm /tmp/aq.zip
		chown quakeuser:quakeuser -Rf /home/quakeuser/quake-afterquake

		#install nvidia and openrazer drivers
		apt-get -qy install nvidia-driver nvidia-settings
	fi

	#update nquake resources
	echo "updating nquake resources..."
	mkdir -p /home/quakeuser/quake/qw.nquake
	mkdir -p /tmp/nquakeresources
	for res in $nquakezips;do
	  wget "$nquakeresourcesurl/$res" -O /tmp/nquakeresources/$res || wget "$nquakeresourcesurl_backup/$res" -O /tmp/nquakeresources/$res || exit 5
		bsdtar xf /tmp/nquakeresources/$res --strip-components=1 -C /home/quakeuser/quake/qw.nquake || exit 6
  done
  rm -rf /tmp/nquakeresources
	
	#remove package cache
	apt-get -qy clean
	
	#clean up lists
	rm -rf /var/lib/apt/lists/*
	
	#configure /tmp as tmpfs
	if [ -f /etc/default/tmpfs ];then
		sed -i "s/#RAMTMP=.*/RAMTMP=yes/g" /etc/default/tmpfs
	fi

	#remove pasystray autostart, we do this ourselves so we do not end up with multiple instances
	rm -f /etc/xdg/autostart/pasystray.desktop

	#configure cpufreq
	echo "GOVERNOR=performance" > /etc/default/cpufrequtils

	#allow any user to start x
	echo -e "allowed_users=anybody\nneeds_root_rights=yes" > /etc/X11/Xwrapper.config

	#configure networking for minimal build
	if [ "$minimal_kmsdrm" = "1" ];then
		echo -e "auto /e*=eth\n  iface eth inet dhcp" > /etc/network/interfaces
	fi
	
	#configure grub
	sed -i "s/GRUB_TIMEOUT.*/GRUB_TIMEOUT=1/g" /etc/default/grub
	sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT.*/GRUB_CMDLINE_LINUX_DEFAULT=\"mitigations=off tsc=reliable nosplash\"/g" /etc/default/grub
	
	rm -rf /tmp/*
	rm -rf /var/log/*

	#let debootstick install this
	apt -y purge linux-image-amd64 || true
	apt-get -qy autopurge || true
	
	#remove temporary resolv.conf
	rm -f /etc/resolv.conf
	'
	if [ $? -ne 0 ];then
		echo "something failed, bailing out."
		exit 1
	fi

	echo "finished commands within chroot"

	cat "$issueappend" |sudo tee -a "$workdir/etc/issue" >/dev/null 2>&1
	sudo cp -f "$rclocal" "$workdir/etc/rc.local"
	sudo cp -f "$hwclock" "$workdir/etc/default/hwclock"
	sudo cp -f "$drirc" "$workdir/home/quakeuser/.drirc"
	sudo cp -f "$xinitrc" "$workdir/home/quakeuser/.xinitrc"
	sudo chmod -f +x "$workdir/home/quakeuser/.xinitrc"
	if [ -d "$workdir/usr/share/pipewire" ];then
		sudo mkdir -p "$workdir/home/quakeuser/.config"
		sudo rm -rf "$workdir/home/quakeuser/.config/pipewire"
		sudo cp -af "$workdir/usr/share/pipewire" "$workdir/home/quakeuser/.config"
		sudo cp -f "$pipewire" "$workdir/home/quakeuser/.config/pipewire/pipewire.conf"
	fi
	sudo cp -f "$xresources" "$workdir/home/quakeuser/.Xresources"
	sudo mkdir -p "$workdir/home/quakeuser/.local/share/applications"

	#desktop files
	for dfile in "$currentdir/resources/applications/"*;do
		sudo cp -f "$dfile" "$workdir/usr/share/applications/."
	done

	#/usr/local/bin
	sudo cp -f "$currentdir/resources/bin/"* "$workdir/usr/local/bin/."

	sudo mkdir -p "$workdir/home/quakeuser/.config/tint2"
	sudo cp -f "$tintrc" "$workdir/home/quakeuser/.config/tint2/tint2rc"
	
	sudo mkdir -p "$workdir/etc/X11/xorg.conf.d"
	sudo cp -f "$compositeconf" "$workdir/etc/X11/xorg.conf.d/01-composite.conf"
	
	sudo cp -f "$sudoers" "$workdir/etc/sudoers"
	
	sudo cp -f "$limitsconf" "$workdir/etc/security/limits.conf"
	
	sudo cp -f "$bashrc" "$workdir/home/quakeuser/.bashrc"
	sudo cp -f "$profile" "$workdir/home/quakeuser/.profile"
	sudo cp -f "$profilemessages" "$workdir/home/quakeuser/.profile_messages"
	
	#fix ownership for quakeuser
	sudo chroot "$workdir" chown quakeuser:quakeuser -Rf /home/quakeuser
	
	echo "configured chroot"

fi

if [ -e "$workdir/dev/pts/ptmx" ];then
	sudo umount -lf "$workdir/dev/pts" >/dev/null 2>&1
	sudo umount -lf "$workdir/proc" >/dev/null 2>&1
fi

export LVM_SYSTEM_DIR=$lvmdir

#clean up old lvs/pvs
#mount 2>/dev/null|grep --color=never DRAFT_|awk '{print $1}'|xargs -r sudo umount -lf
#sudo -E lvs 2>/dev/null|grep --color=never DRAFT_|awk '{print $2"/"$1}'|xargs -r sudo -E lvremove -f
#sudo -E vgs 2>/dev/null|grep --color=never DRAFT_|awk '{print $1}'|xargs -r sudo vgremove -f
#sudo pvs 2>/dev/null|grep --color=never 'mapper/loop'|awk '{print $1}'|xargs -r sudo pvremove -f
#sudo losetup|grep --color=never 'tmp.dbstck'|awk '{print $1}'|xargs -r sudo kpartx -d 

sudo -E ./debootstick/debootstick --config-kernel-bootargs "+pcie_aspm=off +processor.max_cstate=1 +audit=0 +apparmor=0 +preempt=full +mitigations=off +tsc=reliable -quiet +nosplash" --config-root-password-none --config-hostname $mediahostname "$workdir" "$imagename" 2>/tmp/quake_bootable.err 

if [ $? -eq 0 ];then
	echo "compressing..." && \
	mkdir -p ./output
	pigz --zip -9 "$imagename" -c > "./output/${imagename}.zip" && \
	md5sum "./output/${imagename}.zip" > "./output/${imagename}.zip.md5sum"
	if [ ! -z "$imagelatestname" ];then
		ln -sf "${imagename}.zip" "./output/${imagelatestname}.zip" && \
		ln -sf "${imagename}.zip.md5sum" "./output/${imagelatestname}.zip.md5sum"
	fi
else
	echo "errors in process:"
	cat /tmp/quake_bootable.err
fi

if [ -d "$targetdir" ];then
	echo -e "\ncopying to $targetdir"
	rsync -av ./output/* "$targetdir/."
fi

echo -e "\ncomplete."
