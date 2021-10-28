create:
 ./create_image.sh

test:
 quake_bootable=$(ls -t quake_bootable-*.img| head -1)
 sudo truncate -s 4G $quake_bootable `#simulate writing to 4GB media, warning: this will resize the image, zip file will remain unmodified`
 sudo qemu-system-x86_64 -enable-kvm -audiodev pa,id=pa,server=unix:${XDG_RUNTIME_DIR}/pulse/native,out.stream-name=foobar,in.stream-name=foobar -device intel-hda -device hda-duplex,audiodev=pa,mixer=off -vga virtio -m 4096 -smp 4 -drive format=raw,file=$quake_bootable

package (not after truncate):
 quake_bootable=$(ls -t quake_bootable-*.img| head -1)
 pigz --zip -9 $quake_bootable
