#!/bin/bash
#set -euo pipefail

# ════════════════════════════════════════════
# · 构建固件
# ════════════════════════════════════════════
Download_Imagebuilder() {
	echo -e "====》Download Imagebuilder..."
	cd "${Work_Dir}"; ${Download} ${Releases_Url}/${Version}/targets/${Target}/${Imagebuilder}
}

Unpack_Imagebuilder() {
	echo -e "====》Unpack Imagebuilder..."
	rm -rf ${Imagebuilder%.tar.zst}; tar -axf ${Imagebuilder}; cd ${Imagebuilder%.tar.zst} || { echo "Directory not found"; exit 1; }
}

Dynamic_Custom() {
	echo -e "====》Dynamic Custom"
	mkdir -p files/etc/uci-defaults; cat > files/etc/uci-defaults/99_Diy << 'EOF' && echo -e "	====》Network Dhcp"
#!/bin/sh
# ===== 重建网络 =====
uci -q delete network.lan
uci -q delete network.lan6
uci set network.lan='interface'
uci set network.lan6='interface'
uci set network.lan.proto='dhcp'
uci set network.lan6.proto='dhcpv6'
uci set network.lan.device='br-lan'
uci set network.lan6.device='br-lan'
uci commit && for svc in network; do service $svc restart; done
exit 0
EOF
}

Build_Image() {
	echo -e "====》Start Imagebuilder"
	sed -i 's|downloads.openwrt.org|mirrors.tuna.tsinghua.edu.cn/openwrt|g' repositories*
	make image ROOTFS_PARTSIZE=512 FILES="files" BIN_DIR="${Work_Dir}/out/" PACKAGES="${Online_Packages[*]}"
}

Build() {
	Work_Dir=$(pwd)
	Versions=(24 25)
	Targets=(x86/64 armsr/armv8)
	Releases_Url="https://mirrors.tuna.tsinghua.edu.cn/openwrt/releases"
	Download="aria2c -c -R -x 16 -s 999 -j 20 --max-tries=3 --retry-wait=5 --file-allocation=none --check-certificate=false"
	Packages=(build-essential file libncurses-dev zlib1g-dev gawk git gettext libssl-dev xsltproc rsync wget unzip python3 zstd aria2)
	Online_Packages=(luci luci-ssl luci-compat luci-i18n-base-zh-cn luci-i18n-package-manager-zh-cn luci-i18n-dockerman-zh-cn)

	echo -e "====》Install Packages..."; apt update; apt install -fy ${Packages[@]}
	for ver in "${Versions[@]}"; do for Target in "${Targets[@]}"; do
	Version=$(curl -sfSL "${Releases_Url}" | grep -oP 'href="\K\d+\.\d+\.\d+' | grep -E "^${ver}" | sort -V |tail -1)
	Imagebuilder=$(curl -sfSL "${Releases_Url}/${Version}/targets/${Target}" | grep -oP 'href="\Kopenwrt-imagebuilder[^"]+\.tar\.zst')
	[[ -z "${Version}" || -z "${Imagebuilder}" ]] && { echo "解析失败: ver=${ver} target=${Target}"; exit 1; }
	echo -e "====》Start Build OpenWrt Image..."; Download_Imagebuilder; Unpack_Imagebuilder; Dynamic_Custom; Build_Image
	echo -e "====》Build Completed!"; rm -rf ${Work_Dir}/${Imagebuilder%.tar.zst}
	done; done
}

Build
