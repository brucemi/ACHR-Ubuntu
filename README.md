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
