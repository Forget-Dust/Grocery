#!/bin/bash

echo "✉  Install..."
	(apt-get update ;apt-get install -y 7zip squashfs-tools xorriso)>/dev/null 2>&1

echo "✉  Unpack_Iso..."
	for f in *.iso ;do iso_dir="${f%.*}" && rm -rf "$iso_dir" && 7z x "$f" -o"$iso_dir" -y >/dev/null 2>&1 || continue

echo "✉  Unpack_Squashfs..."
	find "$iso_dir" -type f -name "filesystem.squashfs" | while IFS= read -r sq; do SQ_ROOT="${sq%.squashfs}_fs" && rm -rf "$SQ_ROOT" && unsquashfs -d "$SQ_ROOT" "$sq" >/dev/null 2>&1 || continue

echo "✉  Chroot_$SQ_ROOT..."
	[[ -d "Diy" ]] && { mkdir -p "$SQ_ROOT/root" && cp -rf "Diy" "$SQ_ROOT/root/Diy"; }
	F=$SQ_ROOT; mount -t proc proc $F/proc && mount -t sysfs sys $F/sys && mount -o bind /dev $F/dev && mount -o bind /dev/pts $F/dev/pts
	cat > "$SQ_ROOT/root/Diy/Install.sh" <<-'INEOF' && chmod +x "$SQ_ROOT/root/Diy/Install.sh" && { chroot "$SQ_ROOT" "/bin/bash" "/root/Diy/Install.sh"; } #&& read -p "断点"
Deb=(deepin-manual deepin-draw deepin-boot-maker deepin-log-viewer deepin-home deepin-reader deepin-feedback deepin-voice-note dde-introduction com.deepin.lianliankan com.deepin.gomoku libreoffice* org.deepin.browser org.deepin.downloader deepin-unioncode deepin-forum laptop-mode-tools fcitx-sunpinyin deepin-diskmanager dde-printer deepin-calculator deepin-image-viewer simple-scan deepin-devicemanager deepin-album deepin-camera deepin-music deepin-movie deepin-screen-recorder deepin-font-manager deepin-mail)
(sed -i '$a\rm -f ${tmp_file}' /usr/share/initramfs-tools/hooks/deepin-fix-init; echo "deb https://mirrors.cernet.edu.cn/deepin apricot main contrib non-free" > /etc/apt/sources.list)
(echo "nameserver 223.5.5.5" > /etc/resolv.conf; apt-get update && for pkg in "${Deb[@]}"; do apt-get autoremove --purge --yes $pkg ;done && apt-get full-upgrade -fy; :> /etc/resolv.conf)>/dev/null 2>&1
([[ -d "/root/Diy" ]] && { find "/root/Diy" -type f -name "*.deb" | xargs -r ls -Sd 2>/dev/null | awk '{print $NF}' | while read -r deb; do apt-get install -y "$deb" 2>/dev/null && rm -f "$deb"; done; dpkg-query -W -f='${Package}\n' 'linux-image-[0-9]*-desktop*' 'linux-headers-[0-9]*-desktop*' | sort -t- -k3,3Vr | tail -n +3 | xargs -r apt purge -y; })>/dev/null 2>&1
INEOF

echo "✉  Packing_Squashfs..."
	F=$SQ_ROOT; umount $F/dev/pts && umount $F/dev && umount $F/sys && umount $F/proc
	rm -rf $iso_dir/[BOOT] $iso_dir/live/initrd* $iso_dir/live/vmlinuz* $iso_dir/live/filesystem.squashfs
	chroot $SQ_ROOT dpkg-query -W --showformat='${Package} ${Version}\n' > $iso_dir/live/filesystem.manifest
	for n in initrd vmlinuz; do cp -f "$(find "$SQ_ROOT/boot" -type f -name "$n*" | sort -V | tail -1)" "$iso_dir/live/$n"; done
	mksquashfs $SQ_ROOT $iso_dir/live/filesystem.squashfs -comp xz -b 1048576 -noappend && printf $(du -sx --block-size=1 $SQ_ROOT | cut -f1) > $iso_dir/live/filesystem.size >/dev/null 2>&1 && rm -rf $SQ_ROOT

echo "✉  Configure_Startup_Menu..."
sed -i '/^label /,$d' "$iso_dir/isolinux/live.cfg" && cat <<'EOF' | tee -a "$iso_dir/isolinux/live.cfg" >/dev/null
label live
	menu label ^Install Deepin 20.9
	menu default
	linux /live/vmlinuz
	initrd /live/initrd
	append boot=live components quiet splash union=overlay locales=zh_CN.UTF-8

label live-safe
	menu label Install Deepin 20.9 (^Safe graphics)
	linux /live/vmlinuz
	initrd /live/initrd
	append boot=live components quiet splash union=overlay locales=zh_CN.UTF-8 nomodeset
EOF

sed -i '/^menuentry /,$d' "$iso_dir/boot/grub/grub.cfg" && cat <<'EOF' | tee -a "$iso_dir/boot/grub/grub.cfg" >/dev/null
menuentry "Install Deepin 20.9" {
	set gfxpayload=keep
	linux	/live/vmlinuz boot=live components quiet splash union=overlay locales=zh_CN.UTF-8 --
	initrd	/live/initrd
}
menuentry "Install Deepin 20.9 (Safe graphics)" {
	set gfxpayload=keep
	linux	/live/vmlinuz boot=live components quiet splash union=overlay locales=zh_CN.UTF-8 nomodeset --
	initrd	/live/initrd
}
EOF

echo "✉  Packing_Iso..."
	rpt=$(xorriso -indev "$iso_dir.iso" -report_el_torito as_mkisofs 2>/dev/null)
	while IFS="'" read -r k v _; do case $k in '-V ') volid=$v;; '-b ') bios=${v#/};; '-c ') cat=${v#/};; '-e ') efi=${v#/};; esac; done <<< "$rpt"
	xorriso -as mkisofs -V "$volid" -r -J -b "$bios" -c "$cat" -no-emul-boot -boot-load-size 4 -boot-info-table -eltorito-alt-boot -e "$efi" -no-emul-boot -isohybrid-mbr --interval:local_fs:0s-15s:zero_mbrpt,zero_gpt:"$iso_dir.iso" -isohybrid-gpt-basdat -o "$iso_dir-custom.iso" "$iso_dir"

done;done
echo "✉  Packing_Done"