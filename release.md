images:
- full - full build with x11 (nvidia: newer drivers, no support for 10 series and prior gpus)
- full-old_nvidia - full build with x11 (nvidia: older drivers, support for 10 series and prior gpus)
- min_kmsdrm - minimal build using kms/drm, no x11 (untested with proprietary nvidia drivers, nvidia support experimental)

instructions:
- extract img file from zip archive
- use win32 disk imager (or dd in linux/bsd/osx) to write img file to usb device
