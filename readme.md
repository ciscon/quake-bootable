# Introduction
Want to try running Quake in Linux? Curious?
It's easy! Ciscon prepared this Linux Quake bootable image, which includes Chromium web browser, Discord and mostly everything you need to use when playing Quake, without missing anything. Everything works immediately.

# Instructions on how to "burn" this img file to a disk
The main use case for quake-bootable is to save the image to a USB flash drive. But you can also "burn" it to an empty disk on your system, and have dual boot (with Windows too). In this chapter, we will describe how to do it.

## Prerequisites
- Know how to use a linux terminal (console)
- Know how to use the nano text editor (follow instructions within the text editor for saving etc), or better yet, the most important shortcuts of vim (quit, save and quit, insert...).  Replace all vim references with nano if you choose this more user friendly text editor.

## Available commands in Quake-bootable (printed in terminal on boot)
- General
  - browser - starts chromium web browse
  - filebrowser
  - discord
  - lxrandr - configure display
  - shutdown-system
  - razer commands (if a razer device exists)
- Quake related commands
  - quake - runs the game with the selected preset
  - quakepreset - changes the qw folder
  - update-quake
  - quake-afterquake


## Step 1 - Burn the image
In Windows, to burn to a HDD or USB - download the software balenaEtcher, and burn the .img to the target drive.  For writing to a normal USB you can also just use win32 disk imager.

## Step 2 - Boot into Quake-bootable
When booting, press the key to open boot options (usually F8), and choose the disk to boot from.
Alternatively, go to BIOS and do it from there.
Note: If a red warning is displayed when you select the Quake-bootable disk, about secure boot, you have to disable "Secure Boot" on the BIOS. It is required to boot from non-Windows OSes.

## Stop 3 - Recommended optional steps
### change password from user (quakeuser)
The Quake-bootable user is quakeuser. The default password is quakeuser (you will need it)
You can change it with

`$ passwd`

### update packages
`$ sudo apt update`

## Step 4 - install a different window manager (optional)
By default Quake-bootable includes a very basic window manager (Openbox). If you struggle with it, you can install a more familiar one, for example xfce. To install: `$ sudo apt install xfce4`
And then, make it the default in the startup process. edit the file: `$ vim ~/.xinitrc`
And change the very bottom where it says
`exec openbox-session
to
exec xfce4-session`

On the next boot, it will boot into xfce. Don't do it now! Continue to next step.

## Step 5 - fix boot options (optional)
- If you want to keep Windows, you'll need to dual-boot. Let's ensure it will work.
Upon your first boot an entry should have been added to your grub boot menu if another operating system was detected.

## Step 6 - reboot
$ shutdown-system now -r
You can let it boot normally, and see to which OS it goes.
If you want to boot into other OS, press F8 on the startup process and select the disk to boot from.
Note: If you installed xfce and it doesn't look right, reboot again.
All your disks should be visible and accessible.

## Step 7 - Hardware tests
- Let's see if everything is right. visit https://devicetests.com/
- Check your monitor refresh rate: `$ lxrandr`
It should be correct. If it isn't, see "Other info" below.

## Step 8 - run Quake
$ quake
It should run smooth as butter!
You can change the selected "Quake install" to use: `$ quakepreset`

## Step 9 - use your own Quake! (optional)
This is the best thing - you can use Quake-bootable with your Quake folder: your config, your graphics, everything.
- create a folder in quakeuser homedirectory/quake, (where the existing qw.* folders are). something like
`$ mkdir /home/quakeuser/quake/qw.mushi`
- copy your Quake's qw/ folder into this qw.mushi folder
- copy your config file to the /home/quakeuser/quake/ezquake/configs folder
- copy id1.pak to /home/quakeuser/quake/id1
change the selected qw folder to use to your own (qw.mushi):
`$ quakepreset`
And that's it. You can run the game and have it exactly your way:
`$ quake`

# Other info:
- configuration of your gpu can be found in `/etc/rc.local`
- see what runs in the startup `$ vim ~/.xinitrc` 
- if your Quake isn't as smooth as it should, go to the ezQuake menu, and change the resolution there. Play around with settings, and apply them. Once its ok, cfg_save
- if your Quake still isn't smooth, your monitor detailed resolution might need to be updated. You'll use xrandr command for this. Ask for help.


## Building your own image:
```
create:
 ./create_image.sh

test:
 quake_bootable=$(ls -t quake_bootable-*.img| head -1)
 truncate -s 4G $quake_bootable `#simulate writing to 4GB media, warning: this will resize the image, zip file will remain unmodified`
 qemu-system-x86_64 -cpu Nehalem-v2 -m 4096 -smp 4 -drive format=raw,file=$quake_bootable -audio driver=pa,model=hda,id=foo -device virtio-vga-gl -display gtk,gl=on -device virtio-tablet-pci -device virtio-keyboard-pci -machine q35,vmport=off$([ -e /dev/kvm ] && echo ",accel=kvm") -device virtio-rng-pci

package (not after truncate):
 quake_bootable=$(ls -t quake_bootable-*.img| head -1)
 pigz --zip -9 $quake_bootable
```
