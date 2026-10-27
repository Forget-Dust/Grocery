#!/bin/bash
#set -euo pipefail

Arch="$(uname -m)"
System="System_$Arch.qcow2" ;Data="Data.qcow2"
Img=$(find . -type f -name '*.img' | xargs -r file | grep "boot sector" | cut -d ":" -f1 | head -1)
SMP=$(nproc); MEM_TOTAL_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo); MEM_GB=$((MEM_TOTAL_KB/1024/1024)); MEM=$((MEM_GB<=2?1:MEM_GB-1))
Packages=$([ "$Arch" = "x86_64" ] && echo "qemu-system-x86 ovmf ipxe-qemu qemu-utils" || echo "qemu-system-arm qemu-efi-aarch64 ipxe-qemu qemu-utils")

(apt update ;for pkg in $Packages ;do apt install -fy "$pkg" ;done)
cd "$(pwd -P)" ;[[ -f "$Data" ]] || qemu-img create -f qcow2 "$Data" 70G
[[ -f "$System" ]] || { [[ -f "$Img" ]] && qemu-img convert -p -f raw -O qcow2 "$Img" "$System" && qemu-img resize "$System" +2G && rm -rf "$Img" || { echo "System file does not exist" >&2; exit 1; }; }

TAP=tap$$; BR=br0; UPLINK=eth0
! ip link show "$BR" >/dev/null 2>&1 && ip link add name "$BR" type bridge && ip link set "$BR" up
! ip link show "$TAP" >/dev/null 2>&1 && ip tuntap add dev "$TAP" mode tap && ip link set "$TAP" up
! bridge link show | grep -q "$TAP.*master $BR" && ip link set "$TAP" master "$BR"
ip link show "$UPLINK" >/dev/null 2>&1 && {
	OLD_IP=$(ip -4 addr show "$UPLINK" scope global | awk '/inet /{print $2; exit}')
	! bridge link show | grep -q "$UPLINK.*master $BR" && ip link set "$UPLINK" master "$BR"
	[ -n "$OLD_IP" ] && ! ip addr show "$BR" | grep -qF "$OLD_IP" && ip addr add "$OLD_IP" dev "$BR" 2>/dev/null || true
}
MAC="52:54:00:$(echo -n "$System" | md5sum | head -c 6 | sed 's/\(..\)/\1:/g;s/:$//')"
cleanup() { bridge link show | grep -q "$TAP.*master $BR" && ip link set "$TAP" nomaster 2>/dev/null || true; ip tuntap del dev "$TAP" mode tap 2>/dev/null || true; }; trap cleanup EXIT

case "$Arch" in
    aarch64) UEFI=(-drive if=pflash,format=raw,readonly=on,file="/usr/share/qemu-efi-aarch64/QEMU_EFI.fd");;
    x86_64) UEFI=(-drive if=pflash,format=raw,readonly=on,unit=0,file="/usr/share/OVMF/OVMF_CODE_4M.fd" -drive if=pflash,format=raw,readonly=on,unit=1,file="/usr/share/OVMF/OVMF_VARS_4M.fd");;
esac

case "$Arch" in
	aarch64)
		echo "==> arm → qemu-system-aarch64 (-M virt,no -accel kvm)"
		qemu-system-aarch64 -M virt -cpu cortex-a53 "${UEFI[@]}" -smp $SMP -m ${MEM}G \
		-drive file="$System",format=qcow2,if=virtio,id=hd0 ${Data:+-drive file="$Data",format=qcow2,if=virtio,id=hd1} \
		-nic tap,model=virtio-net-pci,ifname=$TAP,mac=$MAC,script=no,downscript=no -nographic -serial mon:stdio
;;
	x86_64)
		echo "==> x86_64 → qemu-system-x86_64 (-M q35)"
		qemu-system-x86_64 -M q35 -cpu qemu64 "${UEFI[@]}" -smp $SMP -m ${MEM}G \
		-drive file="$System",format=qcow2,if=virtio,id=hd0 ${Data:+-drive file="$Data",format=qcow2,if=virtio,id=hd1} \
		-nic tap,model=virtio-net-pci,ifname=$TAP,mac=$MAC,script=no,downscript=no -nographic -serial mon:stdio
;;esac

#前台启动		-nographic -serial mon:stdio
#后台启动		-daemonize -display none && echo "已经在后台运行"