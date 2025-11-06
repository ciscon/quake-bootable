#!/bin/bash -e

build_type=${BUILDTYPE:-full} #do not install x11 or nvidia driver
arch=${BUILDARCH:-amd64}
onlybuild=0 #use existing workdir and only build image

distro="debian" #devuan or debian
release="testing"
mediahostname="quakeboot"

ezquakegitrepo="https://github.com/ezQuake/ezquake-source.git" #repository to use for ezquake build

builddate=$(date +%s)
gitcommit=$(git log -n 1|head -1|awk '{print $2}'|cut -c1-6)
githubref=${GITHUB_REF_NAME:-v0}
release_ver="${githubref}-${builddate}~${gitcommit}"

currentdir="$(cd "$(dirname "${BASH_SOURCE[0]}")/" >/dev/null 2>&1 && pwd)"
workdir="$currentdir/workdir"
quakedir="quake-base"
clean=1 #clean up previous environment

imagebase="quake_bootable"
if [ "$build_type" = "min" ];then
	imagesuffix="-min_kmsdrm"
else
	imagesuffix="-full"
fi


#for releases - without a target dir this means we're doing the build on github
targetdir="/mnt/nas-quake/quake_bootable"
if [ -d "$targetdir" ];then
	imagename="${imagebase}${imagesuffix}-${arch}-$(date +"%Y-%m-%d").img"
	imagelatestname="${imagebase}${imagesuffix}-${arch}-latest"
else
	imagename="${imagebase}${imagesuffix}-${arch}.img"
fi

policykitrules="$currentdir/resources/polkit-rules"
plymouththeme="$currentdir/resources/plymouth/quake-theme"
lvmdir="$currentdir/lvm"
greetd="$currentdir/resources/greetd"
#nodm="$currentdir/resources/nodm"
#slimconf="$currentdir/resources/slim.conf"
xresources="$currentdir/resources/xresources"
#pipewire="$currentdir/resources/pipewire.conf"
drirc="$currentdir/resources/drirc"
rclocal="$currentdir/resources/rc.local"
rclocalservice="$currentdir/resources/rc-local.service"
xinitrc="$currentdir/resources/xinitrc"
xinitrcreal="$currentdir/resources/xinitrc.real"
bashrc="$currentdir/resources/bashrc"
profile="$currentdir/resources/profile"
profilemessages="$currentdir/resources/profile_messages"
hwclock="$currentdir/resources/hwclock"
xorgconf="$currentdir/resources/xorg"
sudoers="$currentdir/resources/sudoers"
limitsconf="$currentdir/resources/limits.conf"
background="$currentdir/resources/background.png"
modprobe="$currentdir/resources/modprobe.d"
issueappend="$currentdir/resources/issue.append"
xfce="$currentdir/resources/xfce"

#base packages
packages="nano procps os-prober util-linux iputils-ping openssh-client file git sudo cmake ninja-build libgl1 libgl1-mesa-dri terminfo vim-tiny unzip zstd alsa-utils fbset systemd-timesyncd cloud-utils parted lvm2 gdisk initramfs-tools fdisk firmware-intel-graphics firmware-linux firmware-linux-nonfree firmware-linux-free firmware-realtek firmware-iwlwifi firmware-intel-sound firmware-sof-signed libarchive-tools linux-image-generic ntfs-3g nfs-common exfat-fuse plymouth plymouth-label iw connman wpasupplicant zip grub2 libfuse2 rename libarchive-tools log2ram "
#minimal build packages
packages_nox11="libegl1 ifupdown dhcpcd-base"
#full build packages
packages_x11=" xserver-xorg-legacy xserver-xorg-core xserver-xorg-video-amdgpu xserver-xorg-video-radeon xserver-xorg-input-all xinit connman-gtk feh menu python3-xdg xdg-utils chromium pasystray pavucontrol pipewire pipewire-pulse wireplumber x11-xserver-utils dbus dbus-user-session dbus-x11 dbus-bin imagemagick rtkit greetd fonts-recommended zip greetd xkbset fonts-recommended zip gvfs-backends "
#window manager/de packages
packages_x11+=" gnome-icon-theme xfce4-terminal xfce4 xfce-polkit mousepad xkbset thunar-archive-plugin file-roller "

if [ "$build_type" != "min" ];then
	packages+=$packages_x11
else
	packages+=$packages_nox11
fi

#vars to be used in chroot
export build_type
export packages
export ezquakegitrepo
export nquakeresourcesurl
export nquakeresourcesurl_backup
export nquakezips
export arch
export distro
export release

#limit file descriptors or certain programs can get into a spin attempting to close all of them
ulimit -n 1000

SUDO="sudo -n"
required="sudo "
if [ $(id -u) -eq 0 ];then
	SUDO=""
	required=""
fi

PATH=$PATH:/sbin:/usr/sbin
required+="debootstrap chroot truncate pigz fdisk git kpartx losetup uuidgen pvscan mkfs.vfat mkfs.ext4"
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
git config --global --add safe.directory '*' >/dev/null 2>&1
git submodule update --init --recursive >/dev/null 2>&1
git submodule update --recursive --remote >/dev/null 2>&1

if [ ! -e /dev/loop0 ];then
    $SUDO mknod /dev/loop0 b 7 0
fi

if [ $onlybuild -eq 0 ] || [ ! -d "$workdir/usr" ];then

	#clean up previous build
	if [ -e "$workdir/dev/pts/ptmx" ];then
		$SUDO umount -qlf "$workdir/dev/pts"||true >/dev/null 2>&1
		$SUDO umount -qlf "$workdir/proc"||true >/dev/null 2>&1
	fi
	if [ $clean -eq 1 ] && [ ! -z "$workdir" ];then
		$SUDO rm -rf "$workdir"
	fi
	mkdir -p "$workdir"

	if [ "$arch" = "686" ];then
		cpuarch="i386"
	elif [ "$arch" = "aarch64" ];then
		cpuarch="arm64"
	else
		cpuarch=$arch
	fi

	echo "building chroot for arch $cpuarch, passed $arch"

	if [ "$distro" = "devuan" ];then
		$SUDO debootstrap --arch=${cpuarch} --include="devuan-keyring gnupg wget ca-certificates" --exclude="debian-keyring" --no-check-gpg --variant=minbase $release "$workdir" http://dev.beard.ly/devuan/merged/
	else
		$SUDO debootstrap --arch=${cpuarch} --include="debian-keyring gnupg wget ca-certificates" --exclude="devuan-keyring" --no-check-gpg --variant=minbase $release "$workdir" https://deb.debian.org/debian/
	fi

	if [ $? -ne 0 ];then
		echo "chroot files:"
		$SUDO find "$workdir" -type f
		if [ -f "$workdir/debootstrap/debootstrap.log" ];then
			echo "debootstrap log:"
			cat "$workdir/debootstrap/debootstrap.log"
		fi
		echo "debootstrap failed, bailing out"
		exit 1
	fi

	echo "debootstrap complete"
	
	$SUDO rm -rf "$workdir/etc/modprobe.d"
	$SUDO cp -rf "$modprobe" "$workdir/etc/"
	$SUDO mkdir -p "$workdir/etc/systemd/system"
	$SUDO cp -f "$rclocalservice" "$workdir/etc/systemd/system/rc-local.service"

	$SUDO mkdir -p "$workdir/root"
	$SUDO cp -f "$bashrc" "$workdir/root/.bashrc"
	$SUDO cp -f "$profile" "$workdir/root/.profile"
	$SUDO cp -f "$bashrc" "$workdir/root/.bashrc"
	$SUDO cp -f "$profilemessages" "$workdir/root/.profile_messages"

	if [ -d "$workdir/quake" ];then
		$SUDO rm -rf "$workdir/quake"
	fi
	$SUDO cp -fR "$quakedir" "$workdir/quake"
	$SUDO cp -f "$background" "$workdir/background.png"
	$SUDO mkdir -p "$workdir/usr/share/plymouth/themes"
	$SUDO cp -rf "$plymouththeme" "$workdir/usr/share/plymouth/themes"

	SCRIPTCMD=""
	if [ ! -z "$SUDO" ];then
		SCRIPTCMD="$SUDO --preserve-env=release,nquakeresourcesurl,nquakeresourcesurl_backup,nquakezips,ezquakegitrepo,packages,distro,build_type,arch"
	fi

	$SCRIPTCMD chroot "$workdir" /bin/bash -e -c '
	
	#configure hostname
	echo "127.0.1.1 '$mediahostname'" >> /etc/hosts
	
	chown -f root:root /
	chmod -f 755 /
	
	useradd -m -p quake -s /bin/bash quakeuser
	mv -f /quake /home/quakeuser/.
	mv -f /root/.profile /home/quakeuser/.
	mv -f /root/.profile_messages /home/quakeuser/.
	cp -f /root/.bashrc /home/quakeuser/.
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

	if [ "$release" != "unstable" ];then
		echo "
		deb http://security.debian.org/debian-security ${release}-security main contrib non-free non-free-firmware
		deb http://deb.debian.org/debian ${release}-updates main contrib non-free non-free-firmware
		" >> /etc/apt/sources.list
	fi

	#enable contrib/non-free
	sed -i "s/main$/main contrib non-free non-free-firmware/g" /etc/apt/sources.list

	#enable stable repo
	if [ "$release" != "stable" ];then
		echo "
		deb http://deb.debian.org/debian stable main contrib non-free non-free-firmware
		deb http://security.debian.org/debian-security stable-security main contrib non-free non-free-firmware
		deb http://deb.debian.org/debian stable-updates main contrib non-free non-free-firmware
		" > /etc/apt/sources.list.d/stable.list
	fi

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

	#install firmware from git?
	#rm -rf /lib/firmware
	#git clone git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git /lib/firmware

	#version
	echo -n "'${release_ver}'" > /version

	#replace systemd with openrc, multiple steps required
	#if [ "$distro" = "debian" ];then
	#	apt-get -qy install openrc sysvinit-core
	#	apt-get -qy install orphan-sysvinit-scripts systemctl systemd-standalone-sysusers
	#	apt-mark hold systemd
	#	apt-get -qy purge systemd libsystemd0
	#	apt-get -qy purge systemctl
	#	apt-get -qy autopurge
	#fi
	#apt-get -qy install rtkit

	#install packages
	apt -qy install $packages
	#for package in $packages;do
	#	apt -qy install $package
	#	echo "completed $package"
	#done

	#install firmware packages
	apt -qy install "*-microcode" || true
	
	##log2ram on debian, devuan does not have systemd so the installation will fail
	#if [ "$distro" = "debian" ];then
	#	echo "configuring log2ram..."
	#	echo "deb http://packages.azlux.fr/debian/ stable main" > /etc/apt/sources.list.d/azlux.list
	#	wget -qO - https://azlux.fr/repo.gpg.key | gpg --dearmour -o /etc/apt/trusted.gpg.d/azlux.gpg
	#	apt-get -qy update
	#	apt-get -qy install log2ram
	#fi

	#plymouth theme
	plymouth-set-default-theme quake-theme

	#configure rc.local
	echo "configuring rc.local"
	(systemctl enable rc-local||true)
	(update-rc.d rc.local enable||true)
	
	#nodm
	#if [ "$build_type" != "min" ];then
	#	echo "configuring nodm"
	#	(systemctl enable nodm||true)
	#	(update-rc.d nodm enable||true)
	#fi
	
	#add our user to some groups
	if grep messagebus /etc/group >/dev/null 2>&1;then messagebus="messagebus,";fi
	usermod -a -G ${messagebus}tty,video,audio,games,input,sudo,adm,plugdev quakeuser
	
	#configure vim symlink for vim
	update-alternatives --install /usr/bin/vim vim /usr/bin/vi 0


	#pull in appimage
	wget -qO /tmp/ezquake-linux https://builds.quakeworld.nu/ezquake/snapshots/latest/linux/x86_64/ezQuake-x86_64.AppImage
	[ ! -s /tmp/ezquake-linux ] && exit 12
	mv /tmp/ezquake-linux /home/quakeuser/quake/ezquake-linux
	chmod +x /home/quakeuser/quake/ezquake-linux
  chown quakeuser:quakeuser -Rf /home/quakeuser/quake

	##build ezquake
	#echo "building ezquake"
	#HOME=/home/quakeuser . /home/quakeuser/.profile
	##drop march to nehalem instead of native
	#if [ "$arch" == "amd64" ];then
	#	export CFLAGS="${CFLAGS} -march=nehalem"
	#	export LDFLAGS="${CFLAGS}"
	#else
	#	export CFLAGS="-O3 -pipe"
	#	export LDFLAGS="${CFLAGS}"
  #fi
	#rm -rf /home/quakeuser/build
	#mkdir /home/quakeuser/build
	#git clone --depth=1 $ezquakegitrepo /home/quakeuser/build/ezquake-source-official
	#cd /home/quakeuser/build/ezquake-source-official
	##version
	#ezquake_ver=$(grep VERSION_NUMBER src/version.h |tr -d \"|awk "{print \$3}")
	#ezquake_ver+=-$(git rev-parse --short HEAD)
	#echo -n "$ezquake_ver" > /ezquake_ver
	#eval $(grep --color=never PKGS_DEB build-linux.sh|head -n1)
	#PKGS_DEB=$(echo "$PKGS_DEB"|tr " " "\n"|grep -v "freetype"|tr "\n" " ")
	#apt-get -qy install $PKGS_DEB
	#git submodule update --init --recursive --remote
	#cmake .
	#make -j$(nproc)
	#strip ezquake-linux-*
	#cp -f /home/quakeuser/build/ezquake-source-official/ezquake-linux-* /home/quakeuser/quake/ezquake-linux
	#git clean -qfdx
	#
	#echo "cleaning up packages"
	##clean up dev packages
	#apt-get -qy purge build-essential || true
	##apt-get -qy purge "*-dev"
	##clean up packages
	#apt-get -qy autopurge
	#
	##reinstall ezquake deps
	#echo "reinstalling ezquake deps"
	#ezquakedeps=$(apt-get --simulate install $(echo "$PKGS_DEB"|sed "s/build-essential//g") 2>/dev/null|grep --color=never "^Inst"|awk "{print \$2}"|grep --color=never -v "\-dev$"|tr "\n" " ")
	#if [ ! -z "$ezquakedeps" ];then
	#  apt-get -qy install $ezquakedeps
	#fi

	#openrazer and kernel headers	
	if [ "$arch" == "amd64" ] || [ "$arch" == "686" ];then
	  apt-get -qy install openrazer-driver-dkms linux-headers-generic pahole
  fi

  if [ "$arch" == "amd64" ] && [ "$build_type" != "min" ];then
	  #install afterquake
  	echo "install afterquake..."
  	mkdir -p /home/quakeuser/quake-afterquake
  	wget -qO /tmp/aq.zip https://fte.triptohell.info/moodles/linux_amd64/afterquake.zip
  	unzip /tmp/aq.zip -d /home/quakeuser/quake-afterquake
  	rm /tmp/aq.zip
  	chown quakeuser:quakeuser -Rf /home/quakeuser/quake-afterquake
  
  	#install nvidia drivers
		wget -qO /tmp/cuda.deb https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/cuda-keyring_1.1-1_all.deb
		dpkg -i /tmp/cuda.deb
		apt-get update
		#apt-get -qy install cuda-drivers
		apt-get -qy install nvidia-driver nvidia-settings nvidia-xconfig
	fi

	#qizmo deps
	if [ "$arch" == "amd64" ];then
		dpkg --add-architecture i386
		apt-get -qy update
		apt-get -qy install libc6:i386
	fi

	#list all available packages and versions into file
	apt list > /versions.txt 2>/dev/null
	
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

	#allow any user to start x
	echo -e "allowed_users=anybody\nneeds_root_rights=yes" > /etc/X11/Xwrapper.config

	#configure networking for minimal build
	if [ "$build_type" = "min" ];then
		echo -e "auto /e*=eth\n  iface eth inet dhcp" > /etc/network/interfaces.d/99-dhcp
	fi
	
	#configure grub
	if [ -f /etc/default/grub ];then
	  sed -i "s/GRUB_TIMEOUT.*/GRUB_TIMEOUT=1/g" /etc/default/grub
  fi

	#explicitly disable selinux just to get rid of warnings on boot
	echo "SELINUX=disabled" > /etc/selinux/config

	#configure openrc to run jobs in parallel
	if [ -f /etc/rc.conf ];then
		sed -i "s/.*rc_parallel=.*/rc_parallel=\"YES\"/g" /etc/rc.conf
	fi

	#configure rcS to be quiet
	if [ -f /etc/default/rcS ];then
		sed -i "s/#*\(.*\)VERBOSE=.*/\1VERBOSE=\"no\"/g" /etc/default/rcS
	fi

  ###let the system take care of this
	#disable user pipewire service, we do this manually in xinitrc
	#(su - quakeuser bash -c "systemctl --user mask pipewire;systemctl --user mask pipewire-pulse;systemctl --user mask wireplumber"||true)
	
	#tmpfs on /tmp
	(systemctl enable tmp.mount || true)

	#disable connman-wait-online in case user has no networking
	systemctl disable connman-wait-online

	#enable greetd
	(systemctl enable greetd || true)

	#disable silken mouse
	if [ -f /etc/X11/xinit/xserverrc ];then
		sed -i "s|/usr/bin/X|/usr/bin/X -nosilk|g" /etc/X11/xinit/xserverrc
	fi

	#set journald to log to memory
	if [ -f /etc/systemd/journald.conf ];then
		sed -i "s|.*Storage=.*|Storage=volatile|g" /etc/systemd/journald.conf
		sed -i "s|.*SystemMaxUse=.*|SystemMaxUse=64M|g" /etc/systemd/journald.conf
		sed -i "s|.*RuntimeMaxUse=.*|RuntimeMaxUse=64M|g" /etc/systemd/journald.conf
	fi

	#apt-get -qy purge g++*
	apt-get -qy autopurge || true

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

	cat "$issueappend" |$SUDO tee -a "$workdir/etc/issue" >/dev/null 2>&1
	$SUDO cp -f "$rclocal" "$workdir/etc/rc.local"
	$SUDO chmod +x "$workdir/etc/rc.local"
	$SUDO mkdir -p "$workdir/etc/polkit-1/rules.d"
	$SUDO cp -f "$hwclock" "$workdir/etc/default/hwclock"
	$SUDO cp -f "$drirc" "$workdir/home/quakeuser/.drirc"
	$SUDO cp -f "$xinitrc" "$workdir/home/quakeuser/.xinitrc"
	$SUDO chmod -f +x "$workdir/home/quakeuser/.xinitrc"
	$SUDO cp -f "$xinitrcreal" "$workdir/home/quakeuser/.xinitrc.real"
	$SUDO chmod -f +x "$workdir/home/quakeuser/.xinitrc.real"
	$SUDO mkdir -p "$workdir/home/quakeuser/.config"
	#$SUDO cp -af "$slimconf" "$workdir/etc/slim.conf"
	$SUDO cp -af "$greetd/"* "$workdir/etc/greetd/."
	$SUDO rm -rf "$workdir/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
	$SUDO cp -af "$xfce/xfce-perchannel-xml" "$workdir/etc/xdg/xfce4/xfconf/"
	#if [ -d "$workdir/usr/share/pipewire" ];then
	#	$SUDO rm -rf "$workdir/home/quakeuser/.config/pipewire"
	#	$SUDO cp -af "$workdir/usr/share/pipewire" "$workdir/home/quakeuser/.config"
	#	$SUDO cp -f "$pipewire" "$workdir/home/quakeuser/.config/pipewire/pipewire.conf"
	#fi
	$SUDO cp -f "$xresources" "$workdir/home/quakeuser/.Xresources"
	$SUDO mkdir -p "$workdir/home/quakeuser/.local/share/applications"

	#policy kit rules
	for dfile in "$policykitrules/"*;do
		$SUDO cp -f "$dfile" "$workdir/etc/polkit-1/rules.d/."
	done

	#desktop files
	for dfile in "$currentdir/resources/applications/"*;do
		$SUDO cp -f "$dfile" "$workdir/home/quakeuser/.local/share/applications"
	done

	#home bin
	$SUDO mkdir -p "$workdir/home/quakeuser/bin"
	$SUDO cp -f "$currentdir/resources/bin/"* "$workdir/home/quakeuser/bin/."

	$SUDO mkdir -p "$workdir/etc/X11/xorg.conf.d"
	$SUDO cp -f "$xorgconf/"* "$workdir/etc/X11/xorg.conf.d/"
	
	$SUDO cp -f "$sudoers" "$workdir/etc/sudoers"
	
	$SUDO cp -f "$limitsconf" "$workdir/etc/security/limits.conf"

	#nodm config	
	#$SUDO cp -f "$nodm" "$workdir/etc/defaults/nodm"

	#fix ownership for quakeuser
	$SUDO chroot "$workdir" chown quakeuser:quakeuser -Rf /home/quakeuser
	
	echo "configured chroot"

fi

if [ -e "$workdir/dev/pts/ptmx" ];then
	$SUDO umount -lf "$workdir/dev/pts" >/dev/null 2>&1
	$SUDO umount -lf "$workdir/proc" >/dev/null 2>&1
fi

export LVM_SYSTEM_DIR=$lvmdir

#preserve environment for following sudo commands
if [ ! -z "$SUDO" ];then
	SUDO+=" -E "
fi

#package versions
versions=$(cat workdir/versions.txt ; rm -f workdir/versions.txt)
mesa_version=$(echo "$versions"|grep libgl1-mesa-dri|tail -1|awk '{print $2}')
kernel_version=$(echo "$versions"|grep linux-image-${arch}|tail -1|awk '{print $2}')
nvidia_version=$(echo "$versions"|grep nvidia-driver|tail -1|awk '{print $2}')
ezquake_version=$(cat "$workdir/ezquake_ver")

echo -e "\n\nversions:" > versions.txt
if [ ! -z "$mesa_version" ];then
	echo "- mesa: $mesa_version" >> versions.txt
fi
if [ ! -z "$kernel_version" ];then
	echo "- kernel: $kernel_version" >> versions.txt
fi
if [ ! -z "$nvidia_version" ];then
	echo "- nvidia: $nvidia_version" >> versions.txt
fi
if [ ! -z "$ezquake_version" ];then
	echo "- ezquake: $ezquake_version" >> versions.txt
fi


#clean up old lvs/pvs
#mount 2>/dev/null|grep --color=never DRAFT_|awk '{print $1}'|xargs -r $SUDO umount -lf
#$SUDO -E lvs 2>/dev/null|grep --color=never DRAFT_|awk '{print $2"/"$1}'|xargs -r $SUDO -E lvremove -f
#$SUDO -E vgs 2>/dev/null|grep --color=never DRAFT_|awk '{print $1}'|xargs -r $SUDO vgremove -f
#$SUDO pvs 2>/dev/null|grep --color=never 'mapper/loop'|awk '{print $1}'|xargs -r $SUDO pvremove -f
#$SUDO losetup|grep --color=never 'tmp.dbstck'|awk '{print $1}'|xargs -r $SUDO kpartx -d 

$SUDO ./debootstick/debootstick --kernel-package linux-image-generic --config-kernel-bootargs "+selinux=0 +amdgpu.ppfeaturemask=0xffffffff +pcie_aspm=off +usbcore.autosuspend=-1 +cpufreq.default_governor=performance +ipv6.disable=1 +audit=0 +apparmor=0 +preempt=full +mitigations=off +ibt=off +rootwait +tsc=reliable +quiet +splash +loglevel=1 -rootdelay" --config-root-password-none --config-hostname $mediahostname "$workdir" "$imagename"

if [ $? -eq 0 ];then
	mkdir -p ./output
	if [ -d "$targetdir" ];then
		echo -e "\ncopying to $targetdir"
		rsync -av ./output/* "$targetdir/."
		echo "compressing..." && \
			mkdir -p ./output
			pigz --zip "$imagename" -c > "./output/${imagename}.zip" && \
			md5sum "./output/${imagename}.zip" > "./output/${imagename}.zip.md5sum"
		if [ ! -z "$imagelatestname" ];then
			ln -sf "${imagename}.zip" "./output/${imagelatestname}.zip" && \
				ln -sf "${imagename}.zip.md5sum" "./output/${imagelatestname}.zip.md5sum"
		fi
	else #this is an automated build we do compression later
		mv -f "$imagename" ./output/.
		md5sum "./output/${imagename}" > "./output/${imagename}.md5sum"
	fi
else
	echo "errors in process"
	exit 1
fi



echo -e "\ncomplete."
