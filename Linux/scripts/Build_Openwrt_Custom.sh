#!/bin/bash
set -euo pipefail

# ════════════════════════════════════════════
# 基础工具函数（颜色、日志、数值校验）
# ════════════════════════════════════════════
G=$'\033[0;32m'; R=$'\033[0;31m'; Y=$'\033[0;33m'; C=$'\033[0m'
fmt_size(){ command -v numfmt &>/dev/null && numfmt --to=iec "$1" || echo "$1 bytes"; }
is_valid_dict(){ local d=$1; (( d >= 8192 && ( (d & (d-1)) == 0 || (d % 3 == 0 && ((d/3) & (d/3-1)) == 0) ) )); }
ok(){ echo -e "${G}✅ $*${C}"; }; err(){ echo -e "${R}❌ $*${C}" >&2; exit 1; }; warn(){ echo -e "${Y}⚠️  $*${C}"; }

# ════════════════════════════════════════════
# 全局变量（顶部声明，函数内不加 local，确保跨函数可见）
# ════════════════════════════════════════════
SQ_ROOT="" TMPDIR="" IMG="" IMG_ARG="" NEW_IMG="" NEW_ROOTFS="" PART2_START_SECTOR=""
PART2_END_BYTE="" OFFSET="" PT_TYPE="" ROOTFS="" SQ_INFO="" SQ_SIZE=""

# ════════════════════════════════════════════
# 环境检查 & 临时目录设置
# ════════════════════════════════════════════
check_env(){ dd --help 2>&1 | grep -q skip || err "需要 GNU coreutils dd（支持 iflag=skip_bytes）"; command -v unsquashfs >/dev/null || err "需要 squashfs-tools"; command -v mksquashfs >/dev/null || err "需要 squashfs-tools"; [[ "$(id -u)" -eq 0 ]] || err "需要 root 权限 (sudo)"; }
setup_tmpdir_and_traps(){ TMPDIR="$(pwd)/.inject_tmp"; rm -rf "$TMPDIR"; mkdir -p "$TMPDIR"; trap 'cleanup_global' EXIT; trap 'echo -e "${R}❌ 脚本在第 $LINENO 行异常中断${C}" >&2; exit 1' ERR INT TERM; }
cleanup_global(){ [[ -n "$SQ_ROOT" && -d "$SQ_ROOT" ]] && check_mount_clean 2>/dev/null || true; [[ -z "${KEEP_TMP:-}" ]] && [[ -n "$TMPDIR" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"; }

# ════════════════════════════════════════════
# 定位镜像文件（支持自动查找 & 解压 .img.gz）
# ════════════════════════════════════════════
locate_image(){ shopt -s nullglob; local arr=(*.img.gz *.img); shopt -u nullglob; [[ $# -ge 1 ]] && IMG_ARG="$1" || { [[ ${#arr[@]} -eq 1 ]] && IMG_ARG="${arr[0]}" || err "请手动指定镜像 (发现 ${#arr[@]} 个镜像)"; }; [[ "$IMG_ARG" == *.img.gz ]] && { echo "🔓 解压 $IMG_ARG ..."; gunzip -kf "$IMG_ARG" 2>&1 || true; IMG="${IMG_ARG%.gz}"; } || IMG="$IMG_ARG"; [[ -f "$IMG" ]] || err "镜像不存在: $IMG"; ok "镜像: $IMG ($(fmt_size "$(stat -c%s "$IMG")"))"; }

# ════════════════════════════════════════════
# 检测分区表 & 分区2边界
# ════════════════════════════════════════════
detect_partition(){ echo "🔍 探测分区表..."; PT_TYPE=$(blkid -o value -s PTTYPE "$IMG" 2>/dev/null || echo "gpt"); PART2_START_SECTOR=$(partx -g -o START "$IMG" 2>/dev/null | sed -n '2p'); local sectors=$(partx -g -o SECTORS "$IMG" 2>/dev/null | sed -n '2p'); PART2_END_BYTE=$(( (PART2_START_SECTOR + sectors) * 512 )); OFFSET=$(( PART2_START_SECTOR * 512 )); echo "   part2: start=${PART2_START_SECTOR}s end=$(fmt_size "$PART2_END_BYTE") type=$PT_TYPE"; [[ -z "$PART2_START_SECTOR" ]] && { warn "partx 失败，回退 sfdisk"; PART2_START_SECTOR=$(sfdisk --list -o Start "$IMG" 2>/dev/null | awk 'NR==3{print $1}'); sectors=$(sfdisk --list -o Sectors "$IMG" 2>/dev/null | awk 'NR==3{print $1}'); PART2_END_BYTE=$(( (PART2_START_SECTOR + sectors) * 512 )); OFFSET=$(( PART2_START_SECTOR * 512 )); }; [[ -z "$PART2_START_SECTOR" ]] && { warn "无法解析分区2，使用镜像末尾"; PART2_END_BYTE=$(stat -c%s "$IMG"); OFFSET=0; }; ok "分区信息已探测 (start=$PART2_START_SECTOR, end=$(fmt_size "$PART2_END_BYTE"))"; }

# ════════════════════════════════════════════
# 定位有效 squashfs 超级块
# ════════════════════════════════════════════
find_squashfs(){ echo "🔍 搜索 squashfs 超级块..."; local cand sb="$TMPDIR/_sb"; while IFS=: read -r cand _; do dd if="$IMG" of="$sb" bs=1M count=4 iflag=skip_bytes skip="$cand" 2>/dev/null; if unsquashfs -s "$sb" >/dev/null 2>&1; then OFFSET="$cand"; ok "squashfs 签名 @ $OFFSET (0x$(printf '%x' "$OFFSET"))"; rm -f "$sb"; return; fi; done < <(grep -aob -E 'hsqs|sqsh' "$IMG" 2>/dev/null); rm -f "$sb"; err "未找到有效 squashfs 超级块"; }

# ════════════════════════════════════════════
# 读取超级块信息 & 提取 rootfs
# ════════════════════════════════════════════
read_superblock_info(){ local sb="$TMPDIR/_sb"; dd if="$IMG" of="$sb" bs=1M count=4 iflag=skip_bytes skip="$OFFSET" 2>/dev/null; SQ_INFO=$(unsquashfs -s "$sb"); SQ_SIZE=$(echo "$SQ_INFO" | awk '/Filesystem size/{print $3+0; exit}'); rm -f "$sb"; [[ "$SQ_SIZE" -gt 0 ]] || err "无法读取 squashfs Filesystem size"; ok "squashfs 大小: $(fmt_size "$SQ_SIZE")"; }
do_extract_rootfs(){ ROOTFS="$TMPDIR/rootfs.squashfs"; local max_avail=$(( PART2_END_BYTE - OFFSET )); [[ "$SQ_SIZE" -le "$max_avail" ]] || err "squashfs 大小超出分区2可用空间"; echo "📤 提取 rootfs..."; dd if="$IMG" of="$ROOTFS" bs=1M iflag=skip_bytes,count_bytes skip="$OFFSET" count="$SQ_SIZE" 2>/dev/null; }

# ════════════════════════════════════════════
# 完整性校验（提取后立即执行）
# ════════════════════════════════════════════
verify_rootfs(){ echo "🔍 完整性检查..."; unsquashfs -l "$ROOTFS" >/dev/null 2>&1 || err "squashfs 数据不完整（EOF/截断），镜像可能损坏"; ok "完整性检查通过"; }

# ════════════════════════════════════════════
# 解析 squashfs 压缩参数（从 SQ_INFO 中提取）
# ════════════════════════════════════════════
parse_squashfs_info(){ BLOCK_SIZE=$(echo "$SQ_INFO" | awk '/Block size/{print $3+0; exit}'); BLOCK_SIZE="${BLOCK_SIZE:-262144}"; DICT_SIZE=$(echo "$SQ_INFO" | awk '/Dictionary size/{print $3+0; exit}'); FILTER=$(echo "$SQ_INFO" | awk '/Filters selected/{for(i=3;i<=NF;i++){t=$i;gsub(/[()+]/,"",t);if(t~/(x86|arm|armthumb|arm64|powerpc|sparc|ia64|riscv)$/){print t;break}}}'); FILTER="${FILTER:-none}"; if [[ -n "$DICT_SIZE" ]] && ! is_valid_dict "$DICT_SIZE"; then warn "字典大小 $DICT_SIZE 非法，回退到 262144"; DICT_SIZE=262144; fi; echo "   块=$BLOCK_SIZE 字典=${DICT_SIZE} 过滤=${FILTER}"; }

# ════════════════════════════════════════════
# . 解包 squashfs（TMPDIR 复用 setup_tmpdir_and_traps 已创建的目录，不再 mktemp 覆盖）
# ════════════════════════════════════════════
unpack(){ SQ_ROOT="$TMPDIR/squashfs-root"; echo "📂 解包..."; rm -rf "$SQ_ROOT"; unsquashfs -d "$SQ_ROOT" "$ROOTFS" >/dev/null; ok "解包完成: $SQ_ROOT"; }

# ════════════════════════════════════════════
# . chroot 挂载 / 卸载虚拟文件系统
# ════════════════════════════════════════════
mount_vfs(){ local r="${SQ_ROOT:?SQ_ROOT未设置}"; echo "📎 挂载虚拟文件系统 → $r"; mkdir -p "$r/proc" "$r/sys" "$r/dev/pts" "$r/dev/shm" "$r/tmp"; local i; for i in proc sys dev dev/pts dev/shm; do mount --bind "/$i" "$r/$i" 2>/dev/null || warn "$i"; done; mount -t tmpfs tmpfs "$r/tmp" 2>/dev/null || warn "tmp"; ok "虚拟文件系统已挂载"; }
umount_vfs(){ local r="${SQ_ROOT:-}"; [[ -z "$r" ]] && { warn "SQ_ROOT 未设置，跳过卸载"; return 0; }; echo "📎 卸载虚拟文件系统 ← $r"; local mp; while read -r mp; do umount -l "$mp" 2>/dev/null || true; done < <(mount | awk -v r="$r" '$3 ~ r {print $3}' | sort -r); ok "已卸载"; }
check_mount_clean(){ local r="${SQ_ROOT:-}"; [[ -z "$r" ]] && return 0; if [[ -n "$(mount | awk -v r="$r" '$3 ~ r')" ]]; then warn "仍有挂载点残留，强制清理"; umount_vfs; fi; }

# ════════════════════════════════════════════
# . 注入自定义内容
# ════════════════════════════════════════════
inject(){
    apt-get install -y qemu-user-static >/dev/null 2>&1
    [[ -d "Diy" ]] && { mkdir -p "$SQ_ROOT/root"; cp -rf "Diy" "$SQ_ROOT/root/Diy"; ok "📦 注入 Diy → /root/Diy"; } || { warn "未找到 Diy 目录，跳过"; return 1; }
    mount_vfs; cat > "$SQ_ROOT/root/Diy/Install.sh" <<-'INEOF' && chmod +x "$SQ_ROOT/root/Diy/Install.sh" && { chroot "$SQ_ROOT" "/bin/ash" "/root/Diy/Install.sh" 2>&1 && ok "注入完成" || warn "注入脚本返回非0（可忽略）"; } #&& read -p "断点"
#!/bin/sh
dir="/root/Diy"
Unpackages="bootstrap|modemmanager|wireguard|ota|filetransfer|appfilter|linkease|ddns|wol|upnp|nfs|mergerfs"
#Inpackages="luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-attendedsysupgrade-zh-cn luci-i18n-dockerman-zh-cn"

echo "==> Custom..."; echo "nameserver 223.5.5.5" > /etc/resolv.conf; mkdir -p /var/lock && touch /var/lock/opkg.lock

case "$(command -v apk || command -v opkg)" in
	*apk)  echo "==> Updating apk list..."; sed -i 's_https\?://downloads.openwrt.org_http://mirrors.cernet.edu.cn/openwrt_g' /etc/apk/repositories.d/distfeeds.list 2>/dev/null && apk update || echo "update failed"
		install="apk add --allow-untrusted"; ext="apk"; [ -n "$Unpackages" ] && { echo "==> UnInstall Packages..."; apk info 2>/dev/null | grep -iE "$Unpackages" | xargs -r apk del --force --rdepends 2>/dev/null; } ;;
	*opkg) echo "==> Updating opkg list..."; sed -i 's_https\?://downloads.openwrt.org_http://mirrors.cernet.edu.cn/openwrt_g' /etc/opkg/distfeeds.conf 2>/dev/null && opkg update || echo "update failed"
		install="opkg install"; ext="ipk"; [ -n "$Unpackages" ] && { echo "==> UnInstall Packages..."; opkg list-installed | awk '{print $1}' | grep -iE "$Unpackages" | xargs -r opkg remove --autoremove --force-depends --force-removal-of-dependent-packages 2>/dev/null; } ;;
	*) echo "==> System Not Supported"; install="" ;;
esac

[ -n "$install" ] && [ -n "$Inpackages" ] && { echo "==> Install Online_Packages..."; for pkg in $Inpackages; do $install --force-overwrite "$pkg" 2>/dev/null; done; }
[ -n "$install" ] && [ -d "$dir/packages" ] && { echo "==> Install Offline_Packages..."; find "$dir/packages" -type f -name "*.$ext" | xargs -r ls -Sd 2>/dev/null | awk '{print $NF}' | while read -r pkg; do $install "$pkg" 2>/dev/null && rm -f "$pkg"; done; }
[ -d "$dir/etc" ] && { echo "==> Copy Config..."; cp -rf "$dir/etc/." /etc/; }; echo "==> Done..."; rm -rf "$dir"; : > /etc/resolv.conf
INEOF
}

# ════════════════════════════════════════════
# . 重打包 squashfs
# ════════════════════════════════════════════
repack(){ check_mount_clean; NEW_ROOTFS="$TMPDIR/new_rootfs.squashfs"; echo "📦 重打包..."; local args=(-comp xz -all-root -b "$BLOCK_SIZE"); mksquashfs -help 2>&1 | grep -q -- '-Xdict-size' && args+=(-Xdict-size "$DICT_SIZE"); case "$FILTER" in none) ;; x86|x86_64) args+=(-Xbcj x86);; *) args+=(-Xbcj "$FILTER");; esac; mksquashfs "$SQ_ROOT" "$NEW_ROOTFS" "${args[@]}" >/dev/null 2>&1; ok "新 rootfs $(fmt_size "$(stat -c%s "$NEW_ROOTFS")")"; }

# ════════════════════════════════════════════
# . 空间检查 & 写回 & 校验
# ════════════════════════════════════════════
expand_partition(){ local need_size=${1:?need size}; local grow=$(( need_size - (PART2_END_BYTE - OFFSET) + 1048576 )); echo "📏 扩展 $(fmt_size "$grow")"; truncate -s "+$grow" "$IMG" 2>/dev/null || err "扩展失败"; case "$PT_TYPE" in gpt) local ts=$(( $(stat -c%s "$IMG")/512 )); local orig_type; orig_type=$(sgdisk -p "$IMG" 2>/dev/null | awk '/^ *2 /{print $6; exit}'); sgdisk -d 2 "$IMG" >/dev/null 2>&1; sgdisk -n 2:${PART2_START_SECTOR}:$((ts-1)) "$IMG" >/dev/null 2>&1; [[ -n "$orig_type" ]] && sgdisk -t 2:"$orig_type" "$IMG" >/dev/null 2>&1 || sgdisk -t 2:${PART2_TYPECODE:-8300} "$IMG" >/dev/null 2>&1; sgdisk -e "$IMG" >/dev/null 2>&1;; dos|msdos) printf "d\n2\nn\np\n2\n${PART2_START_SECTOR}\n\nw\n" | fdisk "$IMG" >/dev/null 2>&1;; *) err "未知分区表 $PT_TYPE";; esac; PART2_END_BYTE=$(stat -c%s "$IMG"); ok "已扩展至 $(fmt_size "$PART2_END_BYTE")"; }
check_space(){ local new_size avail; new_size=$(stat -c%s "$NEW_ROOTFS"); avail=$(( PART2_END_BYTE - OFFSET )); echo "🔎 空间检查: 可用 $(fmt_size "$avail") / 需要 $(fmt_size "$new_size")"; while [[ "$new_size" -gt "$avail" ]]; do echo "⚠️  不足，差 $(fmt_size "$((new_size-avail))")，自动扩展..."; expand_partition "$new_size"; avail=$(( PART2_END_BYTE - OFFSET )); done; ok "空间充足 (剩 $(fmt_size "$((avail-new_size))"))"; }
write_back(){ NEW_IMG="$TMPDIR/istoreos_custom.img"; echo "💾 写回镜像..."; cp "$IMG" "$NEW_IMG"; local offset_sector=$(( (OFFSET + 511) / 512 )); dd if="$NEW_ROOTFS" of="$NEW_IMG" bs=512 conv=notrunc seek="$offset_sector" 2>/dev/null || err "dd 写回失败"; }
verify_write(){ echo "🔍 校验..."; local new_size; new_size=$(stat -c%s "$NEW_ROOTFS"); local chunks=$(( (new_size + 4194303) / 4194304 )); dd if="$NEW_IMG" of="$TMPDIR/_v" bs=4M iflag=skip_bytes skip="$OFFSET" count="$chunks" 2>/dev/null || err "校验读取失败"; dd if=/dev/null of="$TMPDIR/_v" bs=1 seek="$new_size" 2>/dev/null; unsquashfs -s "$TMPDIR/_v" >/dev/null 2>&1 || err "校验失败（超级块不匹配）"; [[ -n "${DEEP_CHECK:-}" ]] && { echo "   深度校验文件列表..."; unsquashfs -l "$TMPDIR/_v" >/dev/null 2>&1 || warn "深度校验发现问题（超级块正常）"; }; rm -f "$TMPDIR/_v"; ok "校验通过"; }

# ════════════════════════════════════════════
# . 分区表修复
# ════════════════════════════════════════════
fix_partition_table(){ echo "🛠️  修复分区表..."; case "$PT_TYPE" in gpt) sgdisk -e "$NEW_IMG" 2>/dev/null && ok "GPT 已修复" || warn "sgdisk 修复失败（可忽略）";; dos|msdos) hexdump -C -n 2 -s 510 "$NEW_IMG" 2>/dev/null | grep -q "55 aa" && ok "MBR 签名正常" || warn "MBR 签名异常";; *) warn "未知分区表: $PT_TYPE，跳过";; esac; }

# ════════════════════════════════════════════
# . 输出最终文件
# ════════════════════════════════════════════
finalize(){ local output="${IMG_ARG%.img.gz}_custom.img"; mv "$NEW_IMG" "$output"; [[ -z "${SKIP_COMPRESS:-}" ]] && { echo "🗜️  压缩..."; rm -f "${output}.gz"; gzip -kf "$output"; output="${output}.gz"; }; echo; ok "完成！ 文件: $output  大小: $(fmt_size "$(stat -c%s "$output")")"; echo "   烧录: dd if=$output bs=4M | gunzip | dd of=/dev/sdX bs=4M conv=fsync"; }

# ════════════════════════════════════════════
# . 主流程（按步骤串联）
# ════════════════════════════════════════════
main(){ check_env; setup_tmpdir_and_traps; locate_image "$@"; detect_partition; find_squashfs; read_superblock_info; do_extract_rootfs; verify_rootfs; parse_squashfs_info; unpack; inject; repack; check_space; write_back; verify_write; fix_partition_table; finalize; }
main "$@"; rm -rf *.img
