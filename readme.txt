test:
 sudo truncate -s 4G quake_bootable-*.img
 sudo qemu-system-x86_64 -enable-kvm -soundhw ac97 -audiodev pa,id=snd0 -vga virtio -m 4096 -smp 4 -drive format=raw,file=quake_bootable-*.img
