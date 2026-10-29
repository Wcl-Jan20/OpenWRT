#!/bin/bash
# SPDX-License-Identifier: MIT
# Copyright (C) 2026 VIKINGYFY

#移除luci-app-attendedsysupgrade
sed -i "/attendedsysupgrade/d" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改默认主题
sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" $(find ./feeds/luci/collections/ -type f -name "Makefile")
#修改immortalwrt.lan关联IP
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js")
#添加编译日期标识
#sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" $(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js")

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
#修改默认IP地址
sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" $CFG_FILE
#修改默认主机名
sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" $CFG_FILE

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

#引入私有扩展配置
if [ -f "$GITHUB_WORKSPACE/Config/PRIVATE.txt" ]; then
	echo "Applying private configurations from PRIVATE.txt..."
	cat $GITHUB_WORKSPACE/Config/PRIVATE.txt >> ./.config
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ] && [ -f .config ]; then
    echo "$WRT_PACKAGE" | tr ' ' '\n' | sed '/^$/d' | while read -r line; do
        if [[ "$line" == *"="* ]]; then
            pkg_name="${line%=*}"
            state="${line#*=}"
        else
            pkg_name="$line"
            state="y"
        fi
        full_key="CONFIG_PACKAGE_${pkg_name}"
        sed -i "/^${full_key}=/d" ./.config
        sed -i "/^# ${full_key} is not set/d" ./.config
        if [ "$state" = "y" ]; then
            echo "${full_key}=y" >> ./.config
        elif [ "$state" = "n" ]; then
            echo "# ${full_key} is not set" >> ./.config
        fi
    done
fi

#无WIFI配置标志
if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
	echo "WRT_WIFI=wifi-no" >> $GITHUB_ENV
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/dts/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		find $DTS_PATH -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
		echo "qualcommax set up nowifi successfully!"
	fi
fi

#修改luci首页显示
#CPU 标签(兼容 _('CPU usage') 与 _('CPU usage (%)'))
sed -i "s#_('CPU usage[^']*')#_('CPU使用率')#g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
#去掉"主机名"整行
sed -i "/_('Hostname')/d" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
#温度行索引前移(删掉主机名/目标平台后数组少了4个元素)
sed -i "s#fields\.splice(6,[[:space:]]*0,[[:space:]]*_('Temperature'))#fields.splice(4, 0, _('Temperature'))#" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
sed -i "s#fields\.splice(7,[[:space:]]*0,[[:space:]]*tempinfo\.tempinfo)#fields.splice(5, 0, tempinfo.tempinfo)#" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
#运行时长
sed -i "s#_('Uptime')#_('运行时长')#g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
#本地时间去掉时区:timeStyle long/full 会带 GMT+8,medium 只留 时:分:秒
sed -i "s#timeStyle:[^,]*,#timeStyle: 'medium',#" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
#去掉"目标平台"整行
sed -i "/_('Target Platform')/d" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js
#内存精简 + 去掉存储
sed -i '38,47d' feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/20_memory.js
rm -rf feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/25_storage.js

#filogic PPE显示:MT7981实际只有1个PPE,隐藏PPE1并把PPE0显示为PPE
FILOGIC_CPUUSAGE="./target/linux/mediatek/filogic/base-files/sbin/cpuusage"
if [ -f "$FILOGIC_CPUUSAGE" ]; then
	cat << 'EOF' > "$FILOGIC_CPUUSAGE"
#!/bin/sh
# Copyright (C) 2024 ZqinKing <zqinking23@gmail.com>
read -r usr sys < <(top -bn1 | awk '/^CPU:/ {print $2, $4; exit}')
output="USR: ${usr} SYS: ${sys}"
#MT7981只有1个PPE:隐藏PPE1,并把PPE0显示为PPE
is_mt7981=0
for dt in /proc/device-tree/compatible /sys/firmware/devicetree/base/compatible; do
	[ -f "$dt" ] || continue
	if tr '\0' '\n' < "$dt" | grep -q 'mediatek,mt7981'; then
		is_mt7981=1
	fi
	break
done
for ppe in /sys/kernel/debug/ppe*/entries; do
	[ -f "$ppe" ] || continue
	name="$(basename "$(dirname "$ppe")" | tr 'a-z' 'A-Z')"
	[ "$is_mt7981" = "1" ] && [ "$name" = "PPE1" ] && continue
	[ "$is_mt7981" = "1" ] && name="PPE"
	read -r total ipv4 ipv6 < <(awk '/IPv4/{a++}/IPv6/{b++} END {print NR, a+0, b+0}' "$ppe")
	[ -n "$total" ] && output="${output} ${name}: ${total} (IPv4: ${ipv4} IPv6: ${ipv6})"
done
echo -n "$output"
EOF
	echo "MT7981 PPE显示已调整:PPE0显示为PPE"
fi

# 25.12 feeds fix
for mk in $(grep -rl --include=Makefile '^[[:space:]]*USERID' ./feeds 2>/dev/null); do
	perl -i -pe '
		BEGIN {
			%hw = (audio => 29, "audio-capture" => 32, midi => 55,
			       video => 40, "video-capture" => 36, render => 43,
			       input => 41, dvb => 49, kvm => 34, lp => 7,
			       scanner => 47, hidraw => 48);
		}
		if (/^(\s*USERID:=)(.+)$/) {
			my ($pre, $spec) = ($1, $2);
			my @f = split(/:/, $spec, 3);
			for my $i (1 .. 2) {
				next unless defined $f[$i];
				my @g = split(/,/, $f[$i]);
				for my $j (0 .. $#g) {
					my ($n) = split(/=/, $g[$j], 2);
					$g[$j] = "$n=$hw{$n}" if exists $hw{$n};
				}
				$f[$i] = join(",", @g);
			}
			$_ = $pre . join(":", @f) . "\n";
		}
	' "$mk"
done

#去掉(OpenWrt U-Boot layout)后缀
if [ -d "./target/linux/mediatek/dts" ]; then
	find ./target/linux/mediatek/dts -type f -name '*.dts' -exec sed -i 's/ (OpenWrt U-Boot layout)//g' {} +
	echo "MTK已去掉型号后缀(OpenWrt U-Boot layout)"
fi

#去掉luci版本后缀并显示年份
sed -i "s#_('Firmware Version'), (L.isObject(boardinfo.release) ? boardinfo.release.description + ' / ' : '') + (luciversion || ''),#_('Firmware Version'), (L.isObject(boardinfo.release) ? (boardinfo.release.description || '').replace('SNAPSHOT r0', 'r$(date +%Y)') : ''),#g" feeds/luci/modules/luci-mod-status/htdocs/luci-static/resources/view/status/include/10_system.js

#为fakeip关闭重绑定保护
sed -i 's/option rebind_protection 1/option rebind_protection 0/g' package/network/services/dnsmasq/files/dhcp.conf

#禁用zram开机自启
#if ! grep -q "S15zram" include/rootfs.mk; then
#    sed -i "/clean_ipkg,\$(1)/a $(printf '\t')rm -f \$(1)/etc/rc.d/S15zram" include/rootfs.mk
#	echo "禁用zram开机启动"
#fi
#zram默认大小改为内存的1/3,并默认使用lz4压缩
ZRAM_INIT="./package/system/zram-swap/files/zram.init"
if [ -f "$ZRAM_INIT" ]; then
	#ram_size单位是kB: ram_size/1024/3 => MB,即 1/3 内存
	sed -i 's|echo \$(( ram_size / 2048 ))|echo $(( ram_size / 3072 ))|' "$ZRAM_INIT"
	#同步更新注释
	sed -i 's|# e.g. 6mb for 16mb-routers or 61mb for 128mb-routers|# use 1/3 of RAM, e.g. 5mb for 16mb-routers or 40mb for 128mb-routers|' "$ZRAM_INIT"
	#默认压缩算法 lzo -> lz4
	sed -i 's|zram_comp_algo="lzo"|zram_comp_algo="lz4"|' "$ZRAM_INIT"
	sed -i 's|# default to lzo, which is always available|# default to lz4|' "$ZRAM_INIT"
	if grep -q 'ram_size / 3072' "$ZRAM_INIT"; then
		echo "zram已调整: 1/3内存 + lz4"
	else
		echo "警告: zram.init 默认大小替换失败,请检查上游是否改动了该文件" >&2
	fi
fi
