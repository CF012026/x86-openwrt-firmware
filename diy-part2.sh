#!/bin/bash
# ============================================================
# diy-part2.sh —— 在 `feeds install` 之后、`make defconfig` 之前执行
# 作用：把 GitHub Secrets 里的私人信息注入固件
# 仓库文件里只有占位符，真实密码只存在于 GitHub Secrets 与编译产物中
#
# 与 360T7 版的差异：
#   - 没有 PPPoE / WiFi 注入（x86 软路由按环境自行配置）
#   - Lucky / EasyTier 私人配置不由本仓库文件提供，
#     由 workflow 的「注入私人信息」步骤从 PRIVATE_FILES_B64 Secret 解包
# ============================================================

UCI_FILE="files/etc/uci-defaults/99-x86-custom"

if [ ! -f "$UCI_FILE" ]; then
    echo "!! 警告：找不到 $UCI_FILE，跳过私人信息注入"
    exit 0
fi

# ---------- 可选：root 管理密码 ----------
# 未设置 ROOT_PASSWORD 时固件保持默认（首次登录会要求设置密码）
if [ -n "$ROOT_PASSWORD" ]; then
    HASH=$(openssl passwd -6 "$ROOT_PASSWORD")
    cat > files/etc/uci-defaults/98-root-password <<EOF
#!/bin/sh
# 首次启动时写入 root 密码（SHA512）
# 注意：sed 表达式必须用单引号。SHA512 哈希以 6 算法标记和盐值开头，
# 若用双引号，本脚本运行时 shell 会把这些美元符当变量展开成空，写出无效哈希导致无法登录。
# SHA512 crypt 哈希字符集为 ./0-9A-Za-z 及美元符，不含单引号，嵌入单引号串是安全的。
sed -i 's|^root:[^:]*:|root:${HASH}:|' /etc/shadow
exit 0
EOF
    chmod +x files/etc/uci-defaults/98-root-password
    echo "== root 密码已写入（SHA512 哈希）"
else
    echo "== 未设置 ROOT_PASSWORD，沿用固件默认（首次登录自行设置）"
fi

# ---------- 回显校验（敏感值打码）----------
echo "===== 注入结果校验 ====="
ls -la files/etc/uci-defaults/

# ---------- daed Makefile 补丁：补写缺失的 +@NEED_BPF_TOOLCHAIN ----------
# 背景：small feed 新版 daed（2026.09.23+）编译期要用 clang 现场编 eBPF
#（PKG_BUILD_DEPENDS:=bpf-headers + include bpf.mk），但 kenzok8 的 DEPENDS
# 漏写了 +@NEED_BPF_TOOLCHAIN —— 上游正是靠它 select 出自建 llvm-bpf 工具链。
# 缺了它 CLANG 会解析成 /invalid/clang，bpf-headers 编译直接报
# "LLVM/clang version too old. Minimum required: 12"（2026-09-24 run 实锤）。
# 这里按上游其他 eBPF 包（xdp-tools 等）的标准写法补上。
DAED_MK="package/feeds/small/daed/Makefile"
if [ -f "$DAED_MK" ]; then
    if ! grep -q "NEED_BPF_TOOLCHAIN" "$DAED_MK"; then
        sed -i 's|+@KERNEL_XDP_SOCKETS \\|+@KERNEL_XDP_SOCKETS +@NEED_BPF_TOOLCHAIN \\|' "$DAED_MK"
    fi
    grep -q "NEED_BPF_TOOLCHAIN" "$DAED_MK" || {
        echo "::error::daed Makefile 打补丁失败（+@NEED_BPF_TOOLCHAIN 未写入），上游 Makefile 格式可能已变"; exit 1;
    }
    echo "== daed Makefile 已补 +@NEED_BPF_TOOLCHAIN（编译期自建 llvm-bpf 的触发开关）"

    # daed Makefile 剥离 GOEXPERIMENT=simd
    # 背景：small feed daed 2026.09.23 在 GO_PKG_TARGET_VARS 传了
    # GOEXPERIMENT=newinliner,simd，但 openwrt-24.10 的 Go 工具链不认识 simd
    # 实验特性，go 命令直接报 "go: unknown GOEXPERIMENT simd" 退出
    #（2026-09-24 run 35956562819 / 35988684666 实锤，daed/wing .built 失败）。
    # simd 只是向量化性能实验，去掉不影响功能；newinliner 在 Go 1.22+ 仍有效。
    sed -i 's/GOEXPERIMENT=newinliner,simd/GOEXPERIMENT=newinliner/' "$DAED_MK"
    if grep -q "GOEXPERIMENT=newinliner,simd" "$DAED_MK"; then
        echo "::error::daed Makefile 剥离 GOEXPERIMENT=simd 失败，上游写法可能已变"; exit 1;
    fi
    echo "== daed Makefile 已剥离 GOEXPERIMENT=simd（保留 newinliner）"
else
    echo "::error::找不到 $DAED_MK —— feeds install 可能未完成，无法打工具链补丁"; exit 1
fi

# ---------- Go 工具链升级：1.23.12 → 1.26.8（扩 bootstrap 链） ----------
# 背景：daed 2026.09.23 快照的 go.mod 要求 go >= 1.26.0，openwrt-24.10
# packages feed 的 golang 包只有 1.23.12，GOTOOLCHAIN=local 下 go
# generate/build 直接拒跑："go.mod requires go >= 1.26.0 (running
# go 1.23.12; GOTOOLCHAIN=local)"（2026-09-24 run 35988684666 实锤）。
# 修法：把 feeds/packages 的 golang 升到 1.26.8。注意 go 1.26 make.bash
# 要求 bootstrap 工具链 >= 1.24.6，而 24.10 链条只到 go1.20，因此按
# Go 官方 bootstrap 规则（1.N 需 1.(N-2 向下取偶)）把链扩成：
#   1.4 → 1.17 → 1.20 → 1.22.12 → 1.24.6 → 1.26.8
# go1.26.8 原生支持 GOEXPERIMENT=simd，与 small feed daed Makefile 匹配。
#
# 【25.12 自适应】openwrt-25.12 的 packages feed 已默认 Go 1.26
#（golang-values.mk: GO_DEFAULT_VERSION:=1.26，golang 包改成 dummy 包，
# GO_VERSION_MAJOR_MINOR 锚点已不存在），此时整段升级补丁无需执行。
GO_VALUES_MK="feeds/packages/lang/golang/golang-values.mk"
if [ -f "$GO_VALUES_MK" ] && grep -qE 'GO_DEFAULT_VERSION:=1\.2[6-9]' "$GO_VALUES_MK"; then
    echo "== packages feed 已内置 Go 1.26+（25.12 路径），跳过 Go 工具链升级补丁"
else

python3 - <<'PYEOF'
import sys

mk_path = "feeds/packages/lang/golang/golang/Makefile"
try:
    mk = open(mk_path).read()
except FileNotFoundError:
    print("::error::找不到 %s —— feeds install 未完成？" % mk_path); sys.exit(1)

def rep(s, old, new, what):
    if old not in s:
        print("::error::golang Makefile 打补丁失败：找不到锚点（%s），上游可能已变" % what)
        sys.exit(1)
    return s.replace(old, new, 1)

# 1) 版本号与哈希 1.23.12 -> 1.26.8（哈希已本地校验）
mk = rep(mk, "GO_VERSION_MAJOR_MINOR:=1.23", "GO_VERSION_MAJOR_MINOR:=1.26", "GO_VERSION_MAJOR_MINOR")
mk = rep(mk, "GO_VERSION_PATCH:=12", "GO_VERSION_PATCH:=8", "GO_VERSION_PATCH")
mk = rep(mk,
    "PKG_HASH:=e1cce9379a24e895714a412c7ddd157d2614d9edbe83a84449b6e1840b4f1226",
    "PKG_HASH:=4e39b98e42f946fa05ac8bc5b71877df97dbdb7cbb1a777b541667ad7117fd2e",
    "PKG_HASH")

# 2) 追加两级 bootstrap 的源码变量（紧随 1.20 块）
old = "BOOTSTRAP_1_20_BUILD_DIR:=$(HOST_BUILD_DIR)/.go_bootstrap_1.20"
new = old + """
BOOTSTRAP_1_22_SOURCE:=go1.22.12.src.tar.gz
BOOTSTRAP_1_22_SOURCE_URL:=$(GO_SOURCE_URLS)
BOOTSTRAP_1_22_HASH:=012a7e1f37f362c0918c1dfa3334458ac2da1628c4b9cf4d9ca02db986e17d71
BOOTSTRAP_1_22_BUILD_DIR:=$(HOST_BUILD_DIR)/.go_bootstrap_1.22
BOOTSTRAP_1_24_SOURCE:=go1.24.6.src.tar.gz
BOOTSTRAP_1_24_SOURCE_URL:=$(GO_SOURCE_URLS)
BOOTSTRAP_1_24_HASH:=e1cb5582aab588668bc04c07de18688070f6b8c9b2aaf361f821e19bd47cfdbd
BOOTSTRAP_1_24_BUILD_DIR:=$(HOST_BUILD_DIR)/.go_bootstrap_1.24"""
mk = rep(mk, old, new, "BOOTSTRAP_1_20_BUILD_DIR 变量块")

# 3) 追加解包命令变量
old = 'BOOTSTRAP_1_20_UNPACK:=$(HOST_TAR) -C "$(BOOTSTRAP_1_20_BUILD_DIR)" --strip-components=1 -xzf "$(DL_DIR)/$(BOOTSTRAP_1_20_SOURCE)"'
new = old + """
BOOTSTRAP_1_22_UNPACK:=$(HOST_TAR) -C "$(BOOTSTRAP_1_22_BUILD_DIR)" --strip-components=1 -xzf "$(DL_DIR)/$(BOOTSTRAP_1_22_SOURCE)"
BOOTSTRAP_1_24_UNPACK:=$(HOST_TAR) -C "$(BOOTSTRAP_1_24_BUILD_DIR)" --strip-components=1 -xzf "$(DL_DIR)/$(BOOTSTRAP_1_24_SOURCE)\""""
mk = rep(mk, old, new, "BOOTSTRAP_1_20_UNPACK 变量")

# 4) 追加 1.22 / 1.24 的 Download/Prepare/profile 块（照抄 1.20 的结构）
anchor = "$(eval $(call GoCompiler/AddProfile,Bootstrap-1.20,$(BOOTSTRAP_1_20_BUILD_DIR),,bootstrap-1.20,$(GO_HOST_OS_ARCH)))"
block = anchor + """

# Bootstrap 1.22

define Download/golang-bootstrap-1.22
  FILE:=$(BOOTSTRAP_1_22_SOURCE)
  URL:=$(BOOTSTRAP_1_22_SOURCE_URL)
  HASH:=$(BOOTSTRAP_1_22_HASH)
endef
$(eval $(call Download,golang-bootstrap-1.22))

define Bootstrap-1.22/Prepare
\tmkdir -p "$(BOOTSTRAP_1_22_BUILD_DIR)" && $(BOOTSTRAP_1_22_UNPACK) ;
endef
Hooks/HostPrepare/Post+=Bootstrap-1.22/Prepare

$(eval $(call GoCompiler/AddProfile,Bootstrap-1.22,$(BOOTSTRAP_1_22_BUILD_DIR),,bootstrap-1.22,$(GO_HOST_OS_ARCH)))

# Bootstrap 1.24

define Download/golang-bootstrap-1.24
  FILE:=$(BOOTSTRAP_1_24_SOURCE)
  URL:=$(BOOTSTRAP_1_24_SOURCE_URL)
  HASH:=$(BOOTSTRAP_1_24_HASH)
endef
$(eval $(call Download,golang-bootstrap-1.24))

define Bootstrap-1.24/Prepare
\tmkdir -p "$(BOOTSTRAP_1_24_BUILD_DIR)" && $(BOOTSTRAP_1_24_UNPACK) ;
endef
Hooks/HostPrepare/Post+=Bootstrap-1.24/Prepare

$(eval $(call GoCompiler/AddProfile,Bootstrap-1.24,$(BOOTSTRAP_1_24_BUILD_DIR),,bootstrap-1.24,$(GO_HOST_OS_ARCH)))"""
mk = rep(mk, anchor, block, "Bootstrap-1.20 profile")

# 5) Host/Compile：链条接上 1.22 -> 1.24，最终版用 1.24 bootstrap
old = '''\t$(call GoCompiler/Host/Make, \\
\t\tGOROOT_BOOTSTRAP="$(BOOTSTRAP_1_20_BUILD_DIR)" \\'''
new = '''\t$(call GoCompiler/Bootstrap-1.22/Make, \\
\t\tGOROOT_BOOTSTRAP="$(BOOTSTRAP_1_20_BUILD_DIR)" \\
\t\t$(HOST_GO_VARS) \\
\t)

\t$(call GoCompiler/Bootstrap-1.24/Make, \\
\t\tGOROOT_BOOTSTRAP="$(BOOTSTRAP_1_22_BUILD_DIR)" \\
\t\t$(HOST_GO_VARS) \\
\t)

\t$(call GoCompiler/Host/Make, \\
\t\tGOROOT_BOOTSTRAP="$(BOOTSTRAP_1_24_BUILD_DIR)" \\'''
mk = rep(mk, old, new, "Host/Compile bootstrap 链")

open(mk_path, "w").write(mk)
print("== golang 已升级 1.23.12 -> 1.26.8（bootstrap 链 1.4→1.17→1.20→1.22→1.24→1.26.8）")
PYEOF

if [ $? -ne 0 ]; then
    echo "::error::Go 工具链升级补丁失败"; exit 1
fi

# 自检：确认版本号与链条均已写入
grep -q "GO_VERSION_MAJOR_MINOR:=1.26" feeds/packages/lang/golang/golang/Makefile && \
grep -q "BOOTSTRAP_1_24_BUILD_DIR" feeds/packages/lang/golang/golang/Makefile && \
grep -q 'GOROOT_BOOTSTRAP="$(BOOTSTRAP_1_24_BUILD_DIR)"' feeds/packages/lang/golang/golang/Makefile && \
echo "== Go 工具链升级补丁自检通过" || {
    echo "::error::Go 工具链升级补丁自检失败"; exit 1;
}

fi  # Go_VALUES_MK 1.26+ 检测分支结束

# ---------- eqos：jjm2473 luci fork 剪掉了 luci-app-eqos，从官方 luci 25.12 补回 ----------
# run 36220035542 实锤：jjm2473/luci istoreos-25.12 无 applications/luci-app-eqos，
# 官方 immortalwrt/luci openwrt-25.12 有（依赖 +tc +kmod-sched-core +kmod-ifb 全是基础包）。
# 做法：把 app 目录拷进 feeds/luci（luci.mk 的 ../../include 相对路径在 feed 树内自洽）。
#
# run 36221464928 实锤（关键坑）：feeds install 只读缓存索引 feeds/luci.index
# （scripts/feeds 第 279 行），索引由 update 时生成。事后拷入新包，install 根本看不见，
# 静默失败。必须先 `feeds update -i luci` 重建索引（仅重扫 feed 目录，不拉仓库）再 install。
if [ ! -e feeds/luci/applications/luci-app-eqos ]; then
    echo "== 补回 luci-app-eqos（官方 luci 25.12 -> jjm2473 fork）=="
    rm -rf /tmp/luci-official
    git clone -q --depth 1 -b openwrt-25.12 https://github.com/immortalwrt/luci /tmp/luci-official \
        || { echo "::error::克隆官方 luci 失败"; exit 1; }
    cp -r /tmp/luci-official/applications/luci-app-eqos feeds/luci/applications/ \
        || { echo "::error::拷贝 luci-app-eqos 失败"; exit 1; }
    # 关键：重建 luci feed 缓存索引，否则 install 查旧索引找不到新包
    ./scripts/feeds update -i luci \
        || { echo "::error::重建 luci feed 索引失败"; exit 1; }
    ./scripts/feeds install -p luci luci-app-eqos
    # i18n 包由 luci.mk 按 CONFIG_LUCI_LANG 生成，feed 索引中未必存在，装不上不算失败
    ./scripts/feeds install -p luci luci-i18n-eqos-zh-cn || echo "WARN: luci-i18n-eqos-zh-cn 不在 feed 索引（i18n 由 CONFIG_LUCI_LANG 控制生成），继续"
    test -e package/feeds/luci/luci-app-eqos \
        || { echo "::error::luci-app-eqos 注册失败！"; ls feeds/luci.index; cat feeds/luci.index 2>/dev/null | grep -c eqos; exit 1; }
    echo "== ✓ luci-app-eqos 已补回并注册 =="
fi

exit 0
