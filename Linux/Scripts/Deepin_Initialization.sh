#!/bin/bash
# >/dev/null 2>&1 不显示输出
# set -euo pipefail # 任何命令失败（-e）、使用未定义变量（-u）、或管道中任意命令失败（-o pipefail）时，脚本立即退出。

Variable () {
echo -en "----------\n"
echo "设置 变量"
echo -en "----------\n"
su="sudo"
version="$(hostnamectl | grep "System" | cut -b "19-50")"
deepin="https://cdn-community-packages.deepin.com/deepin/beige/pool/main/l"
download="aria2c -c -R -x 16 -s 999 -j 20 --file-allocation=none --check-certificate=false"
firmware=$(curl -sL "$deepin/linux-firmware" | grep -oP 'linux-firmware.*all.deb' | sort -Vr | head -1)
image=$(curl -sL "${deepin}/linux-upstream" | grep -oP 'linux-image.*-amd64-desktop-hwe.*deb' |sort -Vr | head -1)
headers=$(curl -sL "${deepin}/linux-upstream" | grep -oP 'linux-headers.*-amd64-desktop-hwe.*deb' |sort -Vr | head -1)
} && Variable 2> /dev/null

Setting_Deepin_20 () {
echo "系统 设置"
gsettings set com.deepin.dde.dock.module.keyboard enable "false" ## 任务栏 cn按钮 关闭 ##
gsettings set com.deepin.dde.power battery-lock-delay "900" ##  使用电池 自动锁屏 15分钟 ##
gsettings set com.deepin.dde.power battery-sleep-delay "0" ##  使用电池 进入待机模式 永不 ##
gsettings set com.deepin.dde.power battery-screen-black-delay "600" ##  使用电池 关闭显示器 10分钟 ##
gsettings set com.deepin.dde.power battery-press-power-button "shutdown" ## 使用电池 按电源按钮时 关机 ##
gsettings set com.deepin.dde.power battery-lid-closed-action "turnOffScreen" ## 使用电池 笔记本合盖时 关闭屏幕 ##
gsettings set com.deepin.dde.power line-power-sleep-delay "0" ##  连接电源 进入待机模式 永不 ##
gsettings set com.deepin.dde.power line-power-lock-delay "1800" ##  连接电源 自动锁屏 30分钟 ##
gsettings set com.deepin.dde.power line-power-screen-black-delay "600" ##  连接电源 关闭显示器 10分钟 ##
gsettings set com.deepin.dde.power line-power-press-power-button "shutdown" ## 连接电源 按电源按钮时 关机 ##
gsettings set com.deepin.dde.power line-power-lid-closed-action "turnOffScreen" ## 使用电源 笔记本合盖时 关闭屏幕 ##
busctl call com.deepin.lastore /com/deepin/lastore com.deepin.lastore.Updater SetUpdateNotify b "0" ## 更新提醒 关闭 ##
busctl call com.deepin.lastore /com/deepin/lastore com.deepin.lastore.Updater SetAutoCheckUpdates b "0" ## 更新检查 关闭 ##
busctl call com.deepin.lastore /com/deepin/lastore com.deepin.lastore.Updater SetAutoDownloadUpdates b "0" ## 更新下载 关闭 ##
}

Uninstall_Deepin_20 () {
echo "卸载 应用列表如下："
echo -en "----------\n"
echo "帮助手册、画板、启动盘制作工具、日志收集工具、深度之家、文档查看器、用户反馈、语音记事本、欢迎、连连看、五子棋、LibreOffice系列、浏览器、下载器、Deepin Union Code、社区、Laptop Mode Tools Configuration、sunpinyin、磁盘管理器、打印管理器、计算器、看图、扫描易、设备管理器、相册、相机、音乐、影院、截图录屏、字体管理器、邮箱"
echo -en "----------\n"
Deb=(deepin-manual deepin-draw deepin-boot-maker deepin-log-viewer deepin-home deepin-reader deepin-feedback deepin-voice-note dde-introduction com.deepin.lianliankan com.deepin.gomoku libreoffice* org.deepin.browser org.deepin.downloader deepin-unioncode deepin-forum laptop-mode-tools fcitx-sunpinyin deepin-diskmanager dde-printer deepin-calculator deepin-image-viewer simple-scan deepin-devicemanager deepin-album deepin-camera deepin-music deepin-movie deepin-screen-recorder deepin-font-manager deepin-mail)
for pkg in "${Deb[@]}"; do ${su} apt-get -qq autoremove --purge --yes $pkg ;done
}

Optimize_Deepin_20 () {
echo "系统 优化"
# 终端 修改&禁用
${su} timedatectl set-timezone Asia/Shanghai
if [ $(whoami) == "uos" ];then ${su} passwd uos -d ;fi
${su} chattr -R +i /usr/share/dde-file-manager/extensions/appEntry
${su} sed -i '$a\rm -f ${tmp_file}' /usr/share/initramfs-tools/hooks/deepin-fix-init
${su} rm -rf ~/.bash_history && ${su} touch ~/.bash_history && ${su} chattr +i ~/.bash_history
${su} cp -rf /etc/apt/sources.list.d/devicemanager.list /etc/apt/sources.list.d/devicemanager.list.bak
${su} rm -rf /root/.bash_history && ${su} touch /root/.bash_history && ${su} chattr +i /root/.bash_history
echo "deb https://mirrors.cernet.edu.cn/deepin apricot main contrib non-free" | ${su} tee /etc/apt/sources.list

# 自启 添加&修改
### echo -e '\n#启动延时\nsleep 5 && notify-send "用户命令设定启动"' | ${su} tee -a /etc/profile
### echo -e 'amixer -c 0 sset "Headphone" 3 && amixer -c 0 sset "Headphone Mixer" 11' | ${su} tee -a /etc/profile
### echo -e 'amixer -c 0 sset "Headphone" unmute && amixer -c 0 sset "Right Headphone Mixer Right DAC" unmute' | ${su} tee -a /etc/profile

# 应用 安装&卸载
${su} rm -rf /var/lib/apt/lists/lock
${su} rm -rf /var/lib/dpkg/updates/*
${su} apt-get -qq update && ${su} apt-get -qq --fix-broken install -fy
${su} apt-get -qq full-upgrade -fy && ${su} apt-get -qq install -fy git cups telnet aria2 ssh vsftpd
${su} dpkg -l | grep "^rc" | awk '{print $2}' | xargs ${su} apt-get -qq autoremove --purge --yes
### ${su} ${download} ${deepin}/linux-upstream/${image} && ${su} ${download} ${deepin}/linux-upstream/${headers}
### ${su} ${download} ${deepin}/linux-firmware/${firmware} && ${su} apt-get -qq install -fy ./linux-*deb && ${su} rm -rf ./linux-*deb

# 配置 修改&优化
${su} sed -i 's/env_reset/env_reset,pwfeedback/g' /etc/sudoers
${su} sed -i "/^127.0.0.1.*/a 127.0.0.1\t$(whoami)" /etc/hosts
${su} sed -i 's/^#write_enable=YES/write_enable=YES\nlocal_root=\/media\nutf8_filesystem=YES/g' /etc/vsftpd.conf
${su} sed -i '2,6d' /etc/default/grub.d/12_deepin_ab_recovery.cfg && ${su} cp -rf /etc/default/grub /etc/default/grub.bak
${su} sed -i '$a\download="aria2c -c -R -x 16 -s 999 -j 20 --file-allocation=none --check-certificate=false"' /etc/profile
#${su} sed -i 's/^GRUB_THEME=.*/GRUB_THEME=""/g;s/^GRUB_BACKGROUND=.*/GRUB_BACKGROUND=""/g;s/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0\nGRUB_TIMOUT_STYLE=hidden/g' /etc/default/grub
${su} sed -i 's/^GRUB_GFXMODE=.*/GRUB_GFXMODE=auto/g;s/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="splash quiet loglevel=0 "\nGRUB_CMDLINE_LINUX="zswap.shrinker_enabled=1 zswap.enabled=1 zswap.compressor=lz4hc iwlmvm.power_scheme=1 "/g' /etc/default/grub && ${su} update-grub

# 服务 屏蔽&启用
${su} systemctl restart ssh vsftpd && ${su} systemctl enable ssh vsftpd
${su} systemctl mask nmbd.service exim4.service apt-daily.service apt-daily-upgrade.service plymouth-quit-wait.service NetworkManager-wait-online.service
}

Uninstall_Deepin_25 () {
echo "卸载 应用列表如下："
echo -en "----------\n"
echo "玲珑：浏览器、相机、画板、字体管理器、看图、邮箱、影院、音乐、文档查看器、语音记事本、帮助手册、计算器、相册、"
echo "原生：磁盘管理器、欢迎、跨端协同、连连看、五子棋、LibreOffice、日志收集工具、设备管理器、深度之家、文档扫描仪、WPS Office、国际化翻译呼吁、搜狗输入法Deepin Next版 属性设置、打印管理器、下载器、备份还原、uos ai、全局搜索"
echo -en "----------\n"
Ll=(org.deepin.browser org.deepin.camera org.deepin.draw org.deepin.fontmanager org.deepin.image.viewer org.deepin.mail org.deepin.movie org.deepin.music org.deepin.reader org.deepin.voice.note org.deepin.manual org.deepin.calculator org.deepin.album)
Deb=(deepin-diskmanager dde-introduction dde-cooperation com.deepin.lianliankan com.deepin.gomoku libreoffice* deepin-log-viewer deepin-devicemanager deepin-home simple-scan dummyapp-wpsoffice deepin-global-translation com.sogou.ime.ng.fcitx5.deepin dde-printer org.deepin.downloader uos-recovery uos-ai dde-grand-search)
for pkg in "${Ll[@]}"; do ${su} ll-cli uninstall $pkg ;done
for pkg in "${Deb[@]}"; do ${su} apt-get -qq autoremove --purge --yes $pkg ;done
}

Optimize_Deepin_25 () {
echo "系统 优化"
# 终端 修改&禁用
${su} rm -rf ~/.bash_history && ${su} touch ~/.bash_history && ${su} chattr +i ~/.bash_history
${su} rm -rf /root/.bash_history && ${su} touch /root/.bash_history && ${su} chattr +i /root/.bash_history
echo "deb https://mirrors.cernet.edu.cn/deepin/beige/ $(grep VERSION_CODENAME /etc/os-release | cut -d= -f2) main commercial community" | sudo tee /etc/apt/sources.list

# 应用 安装&卸载
${su} rm -rf /var/lib/apt/lists/lock
${su} rm -rf /var/lib/dpkg/updates/*
echo "y" | ${su} deepin-immutable-writable enable
${su} apt-get -qq update && ${su} apt-get -qq --fix-broken install -fy
${su} apt-get -qq full-upgrade -fy && ${su} apt-get -qq install -fy deepin-wallpapers git cups telnet aria2 ssh vsftpd
${su} dpkg -l | grep "^rc" | awk '{print $2}' | xargs ${su} apt-get -qq autoremove --purge --yes

# 配置 修改&优化
${su} sed -i 's/env_reset/env_reset,pwfeedback/g' /etc/sudoers
${su} sed -i "/^127.0.0.1.*/a 127.0.0.1\t$(whoami)" /etc/hosts
${su} sed -i 's/^#write_enable=YES/write_enable=YES\nlocal_root=\/media\nutf8_filesystem=YES/g' /etc/vsftpd.conf
${su} sed -i '$a\download="aria2c -c -R -x 16 -s 999 -j 20 --file-allocation=none --check-certificate=false"' /etc/profile
${su} cp -rf /etc/default/grub /etc/default/grub.bak && ${su} sed -i 's/^GRUB_GFXMODE=.*/GRUB_GFXMODE=auto/g' /etc/default/grub && ${su} update-grub

# 服务 屏蔽&启用
${su} systemctl restart ssh vsftpd && ${su} systemctl enable ssh vsftpd
${su} systemctl mask nmbd.service exim4.service apt-daily.timer apt-daily-upgrade.timer plymouth-quit-wait.service NetworkManager-wait-online.service
}

Setting_GXDE_25 () {
echo "系统 设置"
gsettings set com.deepin.dde.power battery-sleep-delay "0" ##  使用电池 进入待机模式 永不 ##
gsettings set com.deepin.dde.power battery-screen-black-delay "600" ##  使用电池 关闭显示器 10分钟 ##
gsettings set com.deepin.dde.power line-power-sleep-delay "0" ##  连接电源 进入待机模式 永不 ##
gsettings set com.deepin.dde.power line-power-screen-black-delay "600" ##  连接电源 关闭显示器 10分钟 ##
}

Uninstall_GXDE_25 () {
echo "卸载 应用列表如下："
echo -en "----------\n"
echo "2048-Qt、Firefox火狐浏览器、GXDE 音乐、GXDE 影院、GXDE 看图、GXDE 录音、GXDE 启动盘制作工具、备份还原工具、计算器、GXDE 字体安装器、分区编辑器、XDE OCR、GXDE 下载助手、GXDE 取色器、GXDE 系统助手、GXDE 词典、Ghostty、GtkHash、Laptop Mode Tools Configuration、Onboard 设置、Remmina、Vim、WPS Office、Wine 运行器、X11VNC Server、mpv 媒体播放器、星火动态壁纸、欢迎、经典扫雷、打印管理器、日志收集工具、Debian 参考手册、跨端协同"
echo -en "----------\n"
Deb=(2048-qt firefox-spark gxde-music gxde-movie gxde-image-viewer gxde-voice-recorder gxde-boot-maker deepin-clone deepin-calculator gxde-font-installer gparted gxde-ocr gxde-downloader gxde-picker gxde-system-assistant gxde-dict ghostty gtkhash laptop-mode-tools onboard remmina vim-common  dummyapp-wps-office dummyapp-spark-deepin-wine-runner x11vnc mpv fantascene-dynamic-wallpaper gxde-introduction com.github.minesweep dde-printer deepin-log-viewer debian-reference-common dde-cooperation)
for pkg in "${Deb[@]}"; do ${su} apt-get -qq autoremove --purge --yes $pkg ;done
}

Optimize_GXDE_25 () {
echo "系统 优化"
# 终端 修改&禁用
${su} rm -rf ~/.bash_history && ${su} touch ~/.bash_history && ${su} chattr +i ~/.bash_history
${su} rm -rf /root/.bash_history && ${su} touch /root/.bash_history && ${su} chattr +i /root/.bash_history
echo "deb https://mirrors.cernet.edu.cn/debian trixie main contrib non-free non-free-firmware" | ${su} tee /etc/apt/sources.list

# 应用 安装&卸载
${su} rm -rf /var/lib/apt/lists/lock
${su} rm -rf /var/lib/dpkg/updates/*
${su} apt-get -qq update && ${su} apt-get -qq --fix-broken install -fy
${su} apt-get -qq full-upgrade -fy && ${su} apt-get -qq install -fy git cups telnet aria2 ssh vsftpd
${su} dpkg -l | grep "^rc" | awk '{print $2}' | xargs ${su} apt-get -qq autoremove --purge --yes

# 配置 修改&优化
${su} sed -i 's/env_reset/env_reset,pwfeedback/g' /etc/sudoers
${su} sed -i 's/^#write_enable=YES/write_enable=YES\nlocal_root=\/media\nutf8_filesystem=YES/g' /etc/vsftpd.conf
${su} sed -i '$a\download="aria2c -c -R -x 16 -s 999 -j 20 --file-allocation=none --check-certificate=false"' /etc/profile

# 服务 屏蔽&启用
${su} systemctl restart ssh vsftpd && ${su} systemctl enable ssh vsftpd
${su} systemctl mask nmbd.service exim4.service apt-daily.timer apt-daily-upgrade.timer plymouth-quit-wait.service NetworkManager-wait-online.service
}

if [ "${version/20.*/20}" = "Deepin 20" ];then
Setting_Deepin_20
Uninstall_Deepin_20
Optimize_Deepin_20
elif [ "${version/25.*/25}" = "Deepin 25" ];then
Uninstall_Deepin_25
Optimize_Deepin_25
elif [ "${version/25.*/25}" = "GXDE OS 25" ];then
Setting_GXDE_25
Uninstall_GXDE_25
Optimize_GXDE_25
else
echo "暂不支持当前系统......"
fi

read -p "完成 部分功能重启后生效 回车结束！"
exit