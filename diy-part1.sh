#!/bin/bash
# ============================================================
# diy-part1.sh —— 在 `feeds update` 之前执行
# 作用：改写/追加第三方软件源
# 源码树：官方 immortalwrt/immortalwrt  openwrt-25.12 分支
# 目标平台：x86_64
#
# 2026-09-26 关键变更（iStore 三件套被 defconfig 静默丢弃的根因修复）：
#   25.12 官方 immortalwrt 全面"去 Lua 化"（删了 lua/libubus-lua/liblucihttp/
#   luci-lib-nixio/ucode-mod-lua），而 luci.mk 会自动给所有带 luasrc/ 的 app
#   追加 +luci-lua-runtime 依赖 → luci-lua-runtime 依赖链断裂 →
#   iStore 三件套（store/quickstart/istorex）全部被 kconfig 静默丢弃。
#   修复方式 = 照抄 iStoreOS 25.12 官方姿势：换用 iStore 作者 jjm2473
#   自己维护的 packages/luci fork（已补回全部 lua 生态，iStoreOS 25.12.5
#   x86 固件实测可用）。
# ============================================================

# 1) 移除 IP 电话源（用不到，省下 feeds 拉取时间）
sed -i '/telephony/d' feeds.conf.default

# 2) packages / luci feed 换成 jjm2473 fork（iStoreOS 25.12 官方同款）
#    - luci fork 补回 lucihttp / ucode-mod-lua / luci-lib-nixio /
#      luci-lua-runtime / luci-compat（contrib/ 与 libs/ 下）
#    - packages fork 提供 lua 解释器包（lang/lua/lua5.4，PKG_NAME=lua）
sed -i 's#^src-git packages .*#src-git packages https://github.com/jjm2473/packages.git;istoreos-25.12#' feeds.conf.default
sed -i 's#^src-git luci .*#src-git luci https://github.com/jjm2473/luci.git;istoreos-25.12#' feeds.conf.default

# 3) kenzok8/small —— 提供 daed 本体（自带 init.d/daed + /etc/config/daed）
echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default

# 4) lucky 大吉 —— lucky 核心 + luci 界面（内网穿透 / DDNS / WebDAV）
echo 'src-git lucky https://github.com/gdy666/luci-app-lucky' >> feeds.conf.default

# 5) EasyTier —— P2P 异地组网（easytier 核心 + luci 界面）
echo 'src-git easytier https://github.com/lmq8267/luci-app-easytier' >> feeds.conf.default

# 6) iStore 全家桶（linkease 官方三件套，x86_64 完整支持）
#    istore      -> luci-app-store（软件中心）
#    nas         -> NAS 系依赖包（quickstart/istorex 的后端等）
#    nas_luci    -> luci-app-quickstart / luci-app-istorex / luci-app-linkease
#                   / luci-app-ddnsto / luci-app-diskman / luci-app-unishare 等
echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
echo 'src-git nas https://github.com/linkease/nas-packages.git;master' >> feeds.conf.default
echo 'src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' >> feeds.conf.default

# 7) Nikki —— mihomo 内核透明代理（feed 自带 mihomo-alpha/mihomo-meta 内核包）
echo 'src-git nikki https://github.com/nikkinikki-org/OpenWrt-nikki.git;main' >> feeds.conf.default

# 8) PassWall 双 feed（官方推荐姿势）
#    2026-09-26：xiaorouji 已把仓库迁到 Openwrt-Passwall 组织
#    （xiaorouji/openwrt-passwall 已删除无重定向 → clone 直接失败，
#    run 36218684133 实锤；packages 旧地址有重定向仍可用，但统一切新）
#    passwall_packages -> xray-core / sing-box / chinadns-ng / geoview 等核心
#    passwall_luci     -> luci-app-passwall 界面
echo 'src-git passwall_packages https://github.com/Openwrt-Passwall/openwrt-passwall-packages.git;main' >> feeds.conf.default
echo 'src-git passwall_luci https://github.com/Openwrt-Passwall/openwrt-passwall.git;main' >> feeds.conf.default

# 9) jjm2473/openwrt-third —— argon 主题 + argon-config 等
#    （run 36220035542 实锤：jjm2473 luci fork 和 kenzok8/small 都没有 argon；
#    iStoreOS 25.12 官方 base feeds.conf.default 就是这个 third feed）
echo 'src-git third https://github.com/jjm2473/openwrt-third.git;main' >> feeds.conf.default

echo "===== 当前 feeds.conf.default ====="
cat feeds.conf.default
