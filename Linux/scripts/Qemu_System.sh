#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd -P)"
cd -- "$SCRIPT_DIR" || (echo "ERROR: 无法 cd 到脚本目录: $SCRIPT_DIR" >&2 && exit 1)

Data="Data.qcow2"
Arch="$(uname -m)"
System="System_$Arch.qcow2"
Img=$(find . -type f -name '*.img' | xargs -r file | grep "boot sector" | cut -d ":" -f1 | head -1)
Packages=$([ "$Arch" = "x86_64" ] && echo "qemu-system-x86 ovmf ipxe-qemu qemu-utils" || echo "qemu-system-arm qemu-efi-aarch64 ipxe-qemu qemu-utils")
declare -a Uefi='-drive if=pflash,format=raw,readonly=on,unit=0,file="/usr/share/OVMF/OVMF_CODE_4M.fd" -drive if=pflash,format=raw,readonly=on,unit=1,file="/usr/share/OVMF/OVMF_VARS_4M.fd"'

for pkg in $Packages ;do apt-get install -fy "$pkg" >/dev/null 2>&1;done
[[ -f "$Data" ]] || qemu-img create -f qcow2 "$Data" 70G
[[ -f "$System" ]] || ([[ -f "$Img" ]] && (qemu-img convert -p -f raw -O qcow2 "$Img" "$System" && qemu-img resize "$System" +2G && rm -rf "$Img") || (echo "System file does not exist" && exit 1))

TAP=tap0; BR=br0; UPLINK=eth0
ip link show $BR  >/dev/null 2>&1 || { ip link add name $BR  type bridge && ip link set $BR  up; }
ip link show $TAP >/dev/null 2>&1 || { ip tuntap add dev $TAP mode tap && ip link set $TAP up; }
bridge link show | grep -q "$TAP.*master $BR" || ip link set $TAP master $BR
if ip link show $UPLINK >/dev/null 2>&1; then
    OLD_IP=$(ip -4 addr show $UPLINK scope global | awk '/inet /{print $2; exit}')
    bridge link show | grep -q "$UPLINK.*master $BR" || ip link set $UPLINK master $BR
    [ -n "$OLD_IP" ] && ip addr add "$OLD_IP" dev $BR 2>/dev/null || true
fi

case "$Arch" in
	aarch64)
		echo "==> arm → qemu-system-aarch64 (-M virt,no -accel kvm)"
		qemu-system-aarch64 -M virt -cpu cortex-a53 -bios "/usr/share/qemu-efi-aarch64/QEMU_EFI.fd" -smp 1 -m 1G \
		-drive file="$System",format=qcow2,if=virtio,id=hd0 ${Data:+-drive file="$Data",format=qcow2,if=virtio,id=hd1} \
		-nic tap,model=virtio-net-pci,ifname=tap0,script=no,downscript=no -nographic -serial mon:stdio
;;
	x86_64)
		echo "==> x86_64 → qemu-system-x86_64 (-M q35)"
		qemu-system-x86_64 -M q35 "${UEFI[@]}" -smp 1 -m 1G \
		-drive file="$System",format=qcow2,if=virtio,id=hd0 ${Data:+-drive file="$Data",format=qcow2,if=virtio,id=hd1} \
		-nic tap,model=virtio-net-pci,ifname=tap0,script=no,downscript=no -nographic -serial mon:stdio
;;esac

#前台启动		-nographic -serial mon:stdio
#后台启动		-daemonize -display none && echo "已经在后台运行"