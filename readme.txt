create:
 ./create_image.sh

test:
 quake_bootable=$(ls -t quake_bootable-*.img| head -1)
 truncate -s 4G $quake_bootable `#simulate writing to 4GB media, warning: this will resize the image, zip file will remain unmodified`
 qemu-system-x86_64 -cpu Nehalem-v2 -m 4096 -smp 4 -drive format=raw,file=$quake_bootable -audio driver=pa,model=hda,id=foo -device virtio-vga-gl -display sdl,gl=on -device virtio-tablet-pci -device virtio-keyboard-pci -machine q35,vmport=off,accel=kvm

package (not after truncate):
 quake_bootable=$(ls -t quake_bootable-*.img| head -1)
 pigz --zip -9 $quake_bootable
