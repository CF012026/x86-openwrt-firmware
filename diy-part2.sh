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
else
    echo "::error::找不到 $DAED_MK —— feeds install 可能未完成，无法打工具链补丁"; exit 1
fi
exit 0
