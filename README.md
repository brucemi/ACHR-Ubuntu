# ACHR-Ubuntu — 一键整机刷 MikroTik CHR v7.19.4（适配 Ubuntu）

把当前 Ubuntu 主机整机刷成 **MikroTik Cloud Hosted Router (CHR) v7.19.4**。  
脚本会从 MikroTik 官方下载镜像、写入启动自动配置（DHCP 或保留现网静态 IP）、并整盘 `dd` 写入目标磁盘，随后重启进入 CHR。

> ⚠️ **高危警告**：此流程会对目标磁盘执行**整盘写入**，清空其上所有数据与分区。请务必确认磁盘并做好备份！

---

## 适用环境
- 操作系统：Ubuntu 20.04 / 22.04 / 24.04（root 权限）
- 网络：能访问 `download.mikrotik.com`
- 硬件：x86_64 裸机或 VPS（KVM/Nested 环境均可）
- 目标：**整机**刷成 CHR v7，不从 v6 在线升级

---

## 快速开始（默认：保留现网静态 IP）
```bash
sudo su -
apt-get update -y && apt-get install -y git
git clone https://github.com/brucemi/ACHR-Ubuntu.git
cd ACHR-Ubuntu
chmod +x install.sh
sudo bash ./install.sh



执行时脚本会：

自动识别默认网卡与当前 IPv4/CIDR、默认网关；

选择根分区所在的整盘作为默认目标盘（也可手动指定）；

下载 chr-7.19.4.img.zip → 解压 → 写入 autorun.scr；

对目标盘执行整盘 dd → 同步 → 重启进入 CHR。

在执行前，脚本会打印磁盘/网络计划并要求你输入 YES 二次确认。

常用用法

1) 指定安装目标磁盘

推荐显式指定，避免错盘风险。
# 例如 NVMe 机器
sudo TARGET_DISK=/dev/nvme0n1 bash ./install.sh

# 或 SATA 机器
sudo TARGET_DISK=/dev/sda bash ./install.sh

2) 改为 DHCP（更保险，开机即拿地址）

sudo NETWORK_MODE=dhcp bash ./install.sh

若你的机房/云平台支持二层直连，DHCP 模式失败时仍可用 Winbox 的 MAC 方式连接（同网段宿主需在同二层）。
3) 临时改版本（仍为 v7 系列）

脚本默认 CHR_VERSION=7.19.4，如需覆盖：

sudo CHR_VERSION=7.19.3 bash ./install.sh

如何确认刷机成功

机器会自动重启；

DHCP 模式：路由器应从上游获取地址，可在上游 DHCP 租约、ARP 表或扫描同网段确认；

静态模式：继续使用原 Ubuntu 的 IPv4/CIDR 与网关（脚本已写入 autorun.scr 到 ether1）；

使用 Winbox（建议）或浏览器访问 WebFig（http://<设备IP>/）。首次登录请立即设置强密码。

若无法通过 IP 访问，可尝试 Winbox 的 Neighbors → MAC 方式直连。

云厂商 VPS 无二层可直通时，请使用控制台（VNC/Serial）进入后手动配置 IP：

/ip dhcp-client add interface=ether1 disabled=no
# 或者：
/ip address add address=<IP/CIDR> interface=ether1
/ip route add gateway=<GW>

常见问题（FAQ）

Q1：为什么不建议在 v6.49.13 上用 Winbox 直接升级到 v7？

大版本跨越（内核/驱动/包）容易“升挂”。已知 v6→v7 在线升级风险较高，全新刷 v7更稳。

Q2：如何确认要刷的磁盘？

lsblk -o NAME,SIZE,TYPE,MODEL,MOUNTPOINT

找到根分区所在的整盘（如 /dev/nvme0n1、/dev/sda），然后以：

sudo TARGET_DISK=/dev/nvme0n1 bash ./install.sh

运行。脚本在执行前也会打印一次磁盘列表并要求你 YES 确认。

Q3：刷完没拿到 IP 怎么办？

若是 DHCP，检查上游 DHCP 是否可用；

尝试 Winbox 的 MAC 直连（需同二层）；

进入控制台（VNC/Serial），执行：

/ip dhcp-client add interface=ether1 disabled=no

或改为静态地址。

Q4：可以改回 v6 吗？

可以，思路相同：把 CHR_VERSION 调回 6.49.x 并用对应下载地址即可。但不建议再从 v6 走在线升级到 v7。

安全与风险提示

整盘擦写：请确认目标盘，数据不可恢复。

网络变化：autorun.scr 默认写到 ether1。若你的平台接口命名差异，请在刷机后按实际接口名调整。

镜像下载：脚本默认从官方直链下载；网络抖动可重试。若你有合规需求，可在外部验证 SHA256 后再执行。

许可证与致谢

CHR 镜像版权归 MikroTik 所有；请遵循其许可与法律法规使用。

本仓库脚本仅用于自动化安装示例，使用风险自负。















