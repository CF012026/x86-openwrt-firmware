#!/bin/bash
# ============================================================
# diy-part1.sh —— 在 `feeds update` 之前执行
# 作用：向 feeds.conf.default 追加第三方软件源
# 源码树：官方 immortalwrt/immortalwrt  openwrt-24.10 分支
# 目标平台：x86_64
# ============================================================

# 1) 移除 IP 电话源（用不到，省下 feeds 拉取时间）
sed -i '/telephony/d' feeds.conf.default

# 2) kenzok8/small —— 提供 daed 本体（自带 init.d/daed + /etc/config/daed）
echo 'src-git small https://github.com/kenzok8/small' >> feeds.conf.default

# 3) lucky 大吉 —— lucky 核心 + luci 界面（内网穿透 / DDNS / WebDAV）
echo 'src-git lucky https://github.com/gdy666/luci-app-lucky' >> feeds.conf.default

# 4) EasyTier —— P2P 异地组网（easytier 核心 + luci 界面）
echo 'src-git easytier https://github.com/lmq8267/luci-app-easytier' >> feeds.conf.default

# 5) iStore 全家桶（linkease 官方三件套，x86_64 完整支持）
#    istore      -> luci-app-store（软件中心）
#    nas         -> NAS 系依赖包（quickstart/istorex 的后端等）
#    nas_luci    -> luci-app-quickstart / luci-app-istorex / luci-app-linkease
#                   / luci-app-ddnsto / luci-app-diskman / luci-app-unishare 等
echo 'src-git istore https://github.com/linkease/istore;main' >> feeds.conf.default
echo 'src-git nas https://github.com/linkease/nas-packages.git;master' >> feeds.conf.default
echo 'src-git nas_luci https://github.com/linkease/nas-packages-luci.git;main' >> feeds.conf.default

echo "===== 当前 feeds.conf.default ====="
cat feeds.conf.default
