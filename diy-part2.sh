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
exit 0
