test:
 sudo truncate -s 4G quake_bootable-*.img
 sudo qemu-system-x86_64 -enable-kvm -audiodev pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native,out.stream-name=foobar,in.stream-name=foobar -device intel-hda -device hda-duplex,audiodev=pa,mixer=off -vga virtio -m 4096 -smp 4 -drive format=raw,file=quake_bootable-*.img
