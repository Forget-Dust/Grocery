#!/bin/bash
# >/dev/null 2>&1 不显示输出
# set -euo pipefail # 任何命令失败（-e）、使用未定义变量（-u）、或管道中任意命令失败（-o pipefail）时，脚本立即退出。
# sed -i.bak 's|https\?://[^/]*/|http://mirrors.cernet.edu.cn/|g' /etc/apt/sources.list

Variable () {
	Su="sudo"
	Patch="$(pwd)"
	ConfigSource="config"
	Mirror="https://mirrors.cernet.edu.cn/kernel"
	Deepin="https://cdn-community-packages.deepin.com/deepin/beige/pool/main/l"
	Download="aria2c -c -x 16 -s 999 --file-allocation=none --check-certificate=false"
	Linux=$(curl -sL "${Mirror}/v6.x/" | grep -oE "linux-6.6.[A-Za-z0-9.]+" | sort -Vr | head -1)
	Firmware=$(curl -sL "${Mirror}/firmware/" | grep -oE "linux-firmware.[A-Za-z0-9.]+" | sort -Vr | head -1)
	Packages=(aria2 build-essential flex bison debhelper libdw-dev libelf-dev libssl-dev libncurses-dev dwarves openssl gawk bc xz-utils zstd fakeroot checkinstall)
} && Variable >/dev/null 2>&1

echo -e "Install the required dependencies ..."
	${Su} apt-get -qq update && for pkg in "${Packages[@]}"; do ${Su} apt-get -qq install -fy $pkg ;done

echo -e "\nDownload and extract the source code package ..."
	cd "${Patch}" && ${Su} rm -rf "${Linux%.tar.xz}"
	${Su} ${Download} "${Mirror}/v$(echo ${Linux%%.*} | cut -f2 -d '-').x/${Linux}" >/dev/null 2>&1
	${Su} tar -xf "${Linux}" && cd "${Patch}/${Linux%.tar.xz}"

	if [ ! -s "${Patch}/${ConfigSource}" ]; then
		echo -e "\nGenerate default configuration ..."
			${Su} make mrproper && ${Su} make defconfig && ${Su} make menuconfig
	else
		echo -e "\nMove specified configuration ..."
			${Su} mv "${Patch}/${ConfigSource}" ".config"
			${Su} make clean && ${Su} sh -c "yes '' | make oldconfig"
	fi

echo -e "\nBuild the deb package ..."
	DEB_BUILD_OPTIONS="noddebs" && ${Su} make bindeb-pkg -j$(nproc --ignore=1)

echo -e "\nDownload and extract the source code package ..."
	cd "${Patch}" && ${Su} rm -rf "${Firmware%.tar.xz}"
	${Su} ${Download} "${Mirror}/firmware/${Firmware}" >/dev/null 2>&1
	${Su} tar -xf "${Firmware}" && cd "${Patch}/${Firmware%.tar.xz}"

echo -e "\nBuild the deb package ..."
	${Su} sed -i 's/ln -s/ln -sf/g' copy-firmware.sh
	${Su} checkinstall -y --install=no --backup=no --maintainer="Forget-Dust" --pkgname="${Firmware%-*}" --pakdir="${Patch}" --pkgversion="$(date +%Y.%m.%d)"

read -p "All Done, Press any key to continue and clear the decompressed file..."
	cd "${Patch}" && ${Su} rm -rf "${Patch}/${Linux%.tar.xz}" && ${Su} rm -rf "${Patch}/${Firmware%.tar.xz}"

exit