# X86_64 私人 OpenWrt 固件

基于 [ImmortalWrt](https://github.com/immortalwrt/immortalwrt) `openwrt-24.10` 分支自编译的 x86_64 软路由固件，插件集与本人的 360T7 固件保持一致，额外集成 iStore 全家桶与 Docker。

## 固件特性

| 项目 | 说明 |
| --- | --- |
| 平台 | x86_64 generic（软路由 / 小主机 / 虚拟机通用） |
| LAN 地址 | `192.168.88.1`（默认，首次启动自动设置） |
| 软件空间 | 4 GB（`TARGET_ROOTFS_PARTSIZE=4096`） |
| 代理后端 | daed（eBPF 透明代理，内核 BTF 已开启） |
| daed 可视化 | luci-app-daed（内嵌 2023 面板，含连接 / 流量统计，烤入固件） |
| 组网 | EasyTier + WireGuard + Tailscale |
| 穿透 / DDNS | Lucky 大吉 |
| 软件中心 | iStore + QuickStart + iStoreX + Linkease + ddnsto + DiskMan + Unishare（iStoreOS 全家桶） |
| 容器 | Docker + docker-compose + LuCI dockerman |
| 限速 | EQoS（按设备上下行限速） |
| 其他 | mwan3 多拨、DDNS、UPnP、ttyd、argon 主题（中文） |

> 拨号（PPPoE）与 WAN 配置不在固件内预置，首次开机后在 LuCI → 网络 → 接口 中按环境自行配置。

## 刷机说明

产物在 Actions Artifact 中（需登录 GitHub 才能下载），包含：

- `immortalwrt-24.10-x86-64-generic-squashfs-combined-efi.img.gz`（UEFI 启动，推荐）
- `immortalwrt-24.10-x86-64-generic-squashfs-combined.img.gz`（Legacy BIOS）

写盘示例（macOS / Linux）：

```bash
gunzip immortalwrt-*-x86-64-generic-squashfs-combined-efi.img.gz
dd if=immortalwrt-*-x86-64-generic-squashfs-combined-efi.img of=/dev/你的磁盘 bs=4M conv=fsync
```

默认 LAN：`192.168.88.1`，LuCI 默认账号 `root`，密码由编译时 Secrets 注入（未注入则首次登录设置）。

## 编译集成要点

- **iStore**：官方集成方式（`src-git istore https://github.com/linkease/istore;main`），x86_64 完整支持
- **daed**：必须开启内核 BTF（`DEBUG_INFO_BTF=y`、`DEBUG_INFO=y`、关闭 `DEBUG_INFO_REDUCED`），否则 eBPF 程序无法加载
- **瘦身**：第三方 feed 全部按需安装，mihomo/clashoo/nikki 等大块头有黑名单双重校验
- **私人配置**：Lucky 数据目录、EasyTier `config.toml` 等私密内容通过 GitHub Secrets（`PRIVATE_FILES_B64`）在编译期注入，**不进仓库**

## 私密说明

本仓库公开，不含任何账号密码 / 网络配置 / 设备绑定信息。编译时需要配置的 Secrets：

| Secret | 作用 |
| --- | --- |
| `ROOT_PASSWORD` | root 密码（编译期生成 SHA512 哈希写入固件，可留空） |
| `PRIVATE_REPO_TOKEN` | 私有配置仓库 `x86-firmware-private` 的访问 Token（可留空） |

私人配置单独存放于私有仓库 **`x86-firmware-private`**（Lucky 数据目录、EasyTier config.toml），编译时自动拉取合并进固件；该私有仓库同样与本项目 1:1 对应，更新配置只需推送私有仓库后重新编译。

## 免责声明

仅供个人学习与家用折腾使用，请遵守当地法律法规。
