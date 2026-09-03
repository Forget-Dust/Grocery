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
# 环境检查 & 临时目录设置
# ════════════════════════════════════════════
check_env() { dd --help 2>&1 | grep -q skip || err "需要 GNU coreutils dd（支持 iflag=skip_bytes）"; [[ "$(id -u)" -eq 0 ]] || err "需要 root 权限 (sudo)"; }
setup_tmpdir_and_traps() { TMPDIR="$(pwd)/.inject_tmp"; mkdir -p "$TMPDIR"; trap '[[ -z "${KEEP_TMP:-}" ]] && rm -rf "$TMPDIR"' EXIT; trap 'echo -e "${R}❌ 脚本在第 $LINENO 行异常中断${C}" >&2; exit 1' ERR INT TERM; }

# ════════════════════════════════════════════
# 定位镜像文件（支持自动查找 & 解压 .img.gz）
# ════════════════════════════════════════════
locate_image(){
    shopt -s nullglob; local arr=(*.img.gz *.img); shopt -u nullglob
    [[ $# -ge 1 ]] && IMG_ARG="$1" || { [[ ${#arr[@]} -eq 1 ]] && IMG_ARG="${arr[0]}" || err "请手动指定镜像"; }
    [[ "$IMG_ARG" == *.img.gz ]] && { echo "🔓 解压 $IMG_ARG ..."; gzip -t "$IMG_ARG" 2>/dev/null || warn "gzip -t 报告尾部垃圾，尝试强制解压"; gunzip -kf "$IMG_ARG" 2>&1 || true; IMG="${IMG_ARG%.gz}"; } || IMG="$IMG_ARG"
    [[ -f "$IMG" ]] || err "镜像不存在: $IMG";ok "镜像: $IMG ($(fmt_size "$(stat -c%s "$IMG")"))"
}

# ════════════════════════════════════════════
# 检测分区表 & 分区2边界
# ════════════════════════════════════════════
detect_partition() {
	PT_TYPE=$(fdisk -l "$IMG" 2>/dev/null | awk '/Disklabel type/{print $3; exit}'); PT_TYPE="${PT_TYPE:-unknown}"; echo "   分区表: $PT_TYPE";local s e d; unset PART2_START PART2_END
	command -v sfdisk &>/dev/null && while read -r d s e; do [[ "$d" == *img2 || "$d" == *p2 ]] && { PART2_START=$s; PART2_END=$e; break; }; done < <(sfdisk --list -o Device,Start,End "$IMG" 2>/dev/null | awk 'NR>1')
	[[ -z "${PART2_END:-}" ]] && while read -r d s e _; do [[ "$d" == *img2 || "$d" == *p2 ]] && { PART2_START=$s; PART2_END=$e; break; }; done < <(fdisk -l "$IMG" 2>/dev/null | awk 'NR>=2 && /[0-9]+/{print $1,$2,$3}')
	[[ -n "${PART2_END:-}" ]] && { PART2_END_BYTE=$(( PART2_END * 512 )); ok "分区2: 起始扇区=$PART2_START 结束扇区=$PART2_END"; } || { warn "无法解析分区2边界，使用镜像末尾"; PART2_END_BYTE=$(stat -c%s "$IMG"); }
}

# ════════════════════════════════════════════
# 定位有效 squashfs 超级块
# ════════════════════════════════════════════
find_squashfs(){ echo "🔍 搜索 squashfs 超级块..."; local cand sb="$TMPDIR/_sb"; while IFS=: read -r cand _; do dd if="$IMG" of="$sb" bs=1M count=4 iflag=skip_bytes skip="$cand" 2>/dev/null; unsquashfs -s "$sb" >/dev/null 2>&1 && { OFFSET="$cand"; ok "squashfs 签名 @ $OFFSET (0x$(printf '%x' "$OFFSET"))"; rm -f "$sb"; return; }; done < <(grep -aob -E 'hsqs|sqsh' "$IMG" 2>/dev/null); rm -f "$sb"; err "未找到有效 squashfs 超级块"; }

# ════════════════════════════════════════════
# 读取超级块信息 & 提取 rootfs
# ════════════════════════════════════════════
read_superblock_info(){ local sb="$TMPDIR/_sb"; dd if="$IMG" of="$sb" bs=1M count=4 iflag=skip_bytes skip="$OFFSET" 2>/dev/null; SQ_INFO=$(unsquashfs -s "$sb"); SQ_SIZE=$(echo "$SQ_INFO" | awk '/Filesystem size/{print $3+0; exit}'); rm -f "$sb"; [[ "$SQ_SIZE" -gt 0 ]] || err "无法读取 squashfs Filesystem size"; ok "squashfs 大小: $(fmt_size "$SQ_SIZE")"; }
do_extract_rootfs(){ ROOTFS="$TMPDIR/rootfs.squashfs"; local max_avail=$(( PART2_END_BYTE - OFFSET )); [[ "$SQ_SIZE" -le "$max_avail" ]] || err "squashfs 大小超出分区2可用空间"; echo "📤 提取 rootfs..."; dd if="$IMG" of="$ROOTFS" bs=1M iflag=skip_bytes,count_bytes skip="$OFFSET" count="$SQ_SIZE" 2>/dev/null; }
extract_rootfs() { read_superblock_info; do_extract_rootfs; }

# ════════════════════════════════════════════
# 完整性校验（提取后立即执行）
# ════════════════════════════════════════════
verify_rootfs(){ echo "🔍 完整性检查..."; unsquashfs -l "$ROOTFS" >/dev/null 2>&1 || err "squashfs 数据不完整（EOF/截断），镜像可能损坏"; ok "完整性检查通过"; }

# ════════════════════════════════════════════
# 解析 squashfs 压缩参数（从 SQ_INFO 中提取）
# ════════════════════════════════════════════
parse_squashfs_info(){ BLOCK_SIZE=$(echo "$SQ_INFO" | awk '/Block size/{print $3+0; exit}'); BLOCK_SIZE="${BLOCK_SIZE:-262144}"; DICT_SIZE=$(echo "$SQ_INFO" | awk '/Dictionary size/{print $3+0; exit}'); FILTER=$(echo "$SQ_INFO" | awk '/Filters selected/{for(i=3;i<=NF;i++){t=$i;gsub(/[()+]/,"",t);if(t~/(x86|arm|armthumb|arm64|powerpc|sparc|ia64|riscv)$/){print t;break}}}'); FILTER="${FILTER:-none}"; if [[ -n "$DICT_SIZE" ]] && ! is_valid_dict "$DICT_SIZE"; then warn "字典大小 $DICT_SIZE 非法，回退到 262144"; DICT_SIZE=262144; fi; echo "   块=$BLOCK_SIZE 字典=${DICT_SIZE} 过滤=${FILTER}"; }

# ════════════════════════════════════════════
# . 解包 squashfs
# ════════════════════════════════════════════
unpack(){ SQ_ROOT="$TMPDIR/squashfs-root"; echo "📂 解包..."; rm -rf "$SQ_ROOT"; unsquashfs -d "$SQ_ROOT" "$ROOTFS" >/dev/null; }

# ════════════════════════════════════════════
# . 注入自定义内容
# ════════════════════════════════════════════
inject() {
    [[ -d "Diy" ]] && { mkdir -p "$SQ_ROOT/root"; cp -rf Diy "$SQ_ROOT/root/Diy"; ok "📦 注入 Diy → /root/Diy"; } || warn "未找到 Diy/ 目录，跳过"
    cat > "$SQ_ROOT/root/Diy/Install.sh" << 'INEOF' && chmod +x "$SQ_ROOT/root/Diy/Install.sh" && chroot "$SQ_ROOT" /bin/ash "/root/Diy/Install.sh" 2>&1 && ok "注入完成" || warn "注入脚本返回非0（可忽略）"
#!/bin/sh
echo "==> Custom..."; mkdir -p /var/lock && touch /var/lock/opkg.lock
case "$(command -v apk || command -v opkg)" in *apk) pm="apk add --allow-untrusted --force-overwrite"; ext="apk" ;; *opkg) pm="opkg install --force-overwrite"; ext="ipk" ;; *) echo "==> System Not Supported"; pm="" ;; esac
if [ -n "$pm" ] && [ -d "/root/Diy/packages" ];then find "/root/Diy/packages" -type f -name "*.$ext" | xargs ls -Sd 2>/dev/null | awk '{print $NF}' | while read -r pkg; do $pm "$pkg" 2>&1 && rm -f "$pkg"; done; fi
[ -d "/root/Diy/etc" ] && cp -rf "/root/Diy/etc/." /etc/; echo "==> Done..."; rm -rf "/root/Diy"
INEOF
}

# ════════════════════════════════════════════
# . 重打包 squashfs
# ════════════════════════════════════════════
repack(){ NEW_ROOTFS="$TMPDIR/new_rootfs.squashfs"; echo "📦 重打包..."; local args=(-comp xz -all-root -b "$BLOCK_SIZE"); mksquashfs -help 2>&1 | grep -q -- '-Xdict-size' && args+=(-Xdict-size "$DICT_SIZE"); case "$FILTER" in none) ;; x86|x86_64) args+=(-Xbcj x86);; *) args+=(-Xbcj "$FILTER");; esac; mksquashfs "$SQ_ROOT" "$NEW_ROOTFS" "${args[@]}" >/dev/null 2>&1; ok "新 rootfs $(fmt_size "$(stat -c%s "$NEW_ROOTFS")")"; }

# ════════════════════════════════════════════
# . 空间检查 & 写回 & 校验
# ════════════════════════════════════════════
check_space(){ local new_size=$(stat -c%s "$NEW_ROOTFS") avail=$(( PART2_END_BYTE - OFFSET )); echo "🔎 空间检查: 可用 $(fmt_size "$avail") / 需要 $(fmt_size "$new_size")"; [[ "$new_size" -le "$avail" ]] || err "空间不足，差 $(fmt_size "$((new_size - avail))")"; ok "空间充足 (剩 $(fmt_size "$((avail - new_size))"))"; }
write_back(){ NEW_IMG="$TMPDIR/istoreos_custom.img"; echo "💾 写回镜像..."; cp "$IMG" "$NEW_IMG"; local offset_sector=$(( (OFFSET + 511) / 512 )); dd if="$NEW_ROOTFS" of="$NEW_IMG" bs=512 conv=notrunc seek="$offset_sector" 2>/dev/null || err "dd 写回失败"; }
verify_write(){ echo "🔍 校验..."; local new_size; new_size=$(stat -c%s "$NEW_ROOTFS"); local chunks=$(( (new_size + 4194303) / 4194304 )); dd if="$NEW_IMG" of="$TMPDIR/_v" bs=4M iflag=skip_bytes skip="$OFFSET" count="$chunks" 2>/dev/null || err "校验读取失败"; dd if=/dev/null of="$TMPDIR/_v" bs=1 seek="$new_size" 2>/dev/null; unsquashfs -s "$TMPDIR/_v" >/dev/null 2>&1 || err "校验失败（超级块不匹配）"; [[ -n "${DEEP_CHECK:-}" ]] && { echo "   深度校验文件列表..."; unsquashfs -l "$TMPDIR/_v" >/dev/null 2>&1 || warn "深度校验发现问题（超级块正常）"; }; rm -f "$TMPDIR/_v"; ok "校验通过"; }

# ════════════════════════════════════════════
# . 分区表修复
# ════════════════════════════════════════════
fix_partition_table(){ echo "🛠️  修复分区表..."; case "$PT_TYPE" in gpt) sgdisk -e "$NEW_IMG" 2>/dev/null && ok "GPT 已修复" || warn "sgdisk 修复失败（可忽略）";; dos|msdos) hexdump -C -n 2 -s 510 "$NEW_IMG" 2>/dev/null | grep -q "55 aa" && ok "MBR 签名正常" || warn "MBR 签名异常";; *) warn "未知分区表: $PT_TYPE，跳过";; esac; }

# ════════════════════════════════════════════
# . 输出最终文件
# ════════════════════════════════════════════
finalize(){ local output="istoreos_custom.img"; mv "$NEW_IMG" "$output"; [[ -z "${SKIP_COMPRESS:-}" ]] && { echo "🗜️  压缩..."; rm -f "${output}.gz"; gzip -kf "$output"; output="${output}.gz"; }; echo; ok "完成！ 文件: $output  大小: $(fmt_size "$(stat -c%s "$output")")"; echo "   烧录: dd if=$output bs=4M | gunzip | dd of=/dev/sdX bs=4M conv=fsync"; }

# ════════════════════════════════════════════
# . 主流程（按步骤串联）
# ════════════════════════════════════════════
main(){ check_env; setup_tmpdir_and_traps; locate_image "$@"; detect_partition; find_squashfs; extract_rootfs; verify_rootfs; parse_squashfs_info; unpack; inject; repack; check_space; write_back; verify_write; fix_partition_table; finalize; }
main "$@"; rm -rf *.img
