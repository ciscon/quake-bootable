test:
 sudo truncate -s 4G quake_bootable-*.img
 sudo qemu-system-x86_64 -enable-kvm -device intel-hda -device hda-output,audiodev=hda -vga virtio -m 4096 -smp 4 -drive format=raw,file=quake_bootable-*.img
 #sudo qemu-system-x86_64 -enable-kvm -device AC97 -vga virtio -m 4096 -smp 4 -drive format=raw,file=quake_bootable-*.img
