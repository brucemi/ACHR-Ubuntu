# install.sh（v7.19.4 版，整机刷 CHR v7）

> **危险提示**：该脚本会对目标磁盘执行整盘写入（`dd`），清空其上所有数据。运行前请确认磁盘并做好备份。

```bash
#!/usr/bin/env bash
# install.sh — Flash MikroTik CHR v7.19.4 onto this machine (whole-disk)
# Repo: https://github.com/brucemi/ACHR-Ubuntu
# Default: keep current host IP/gateway as static on ether1.
# Optional env:
#   TARGET_DISK=/dev/sda         # explicitly choose disk (e.g. /dev/sda, /dev/vda, /dev/nvme0n1)
#   NETWORK_MODE=static|dhcp     # default: static (use current IP/CIDR and gateway); dhcp = enable client on ether1
#   CHR_VERSION=7.19.4           # override version if needed
set -euo pipefail

# ---------------------- Config ----------------------
CHR_VERSION="${CHR_VERSION:-7.19.4}"
NETWORK_MODE="${NETWORK_MODE:-static}"   # static or dhcp
# ----------------------------------------------------

die() { echo "ERROR: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing command: $1"; }

[[ $EUID -eq 0 ]] || die "Please run as root (sudo)."

need_cmd lsblk
need_cmd ip
need_cmd awk
need_cmd sed
need_cmd grep
need_cmd wget
need_cmd unzip
need_cmd dd
need_cmd mount
need_cmd umount

# Install unzip if missing (Ubuntu)
if ! dpkg -s unzip >/dev/null 2>&1; then
  apt-get update -y && apt-get install -y unzip
fi

echo "=== MikroTik CHR installer ==="
echo "Target version: $CHR_VERSION"

# Detect default interface, IP/CIDR, gateway
DEF_ROUTE="$(ip route get 1.1.1.1 2>/dev/null || true)"
if [[ -z "$DEF_ROUTE" ]]; then
  DEF_ROUTE="$(ip route show default 2>/dev/null | head -n1 || true)"
fi
DEV="$(awk '{for(i=1;i<=NF;i++) if($i=="dev"){print $(i+1); exit}}' <<<"$DEF_ROUTE")"
[[ -n "${DEV:-}" ]] || die "Cannot detect default interface."
IPCIDR="$(ip -4 -o addr show dev "$DEV" | awk '/inet /{print $4; exit}')"
[[ -n "${IPCIDR:-}" ]] || { echo "WARN: cannot detect IPv4 on $DEV; static mode may fail."; }
GATEWAY="$(awk '/default/{for(i=1;i<=NF;i++) if($i=="via"){print $(i+1); exit}}' <<<"$DEF_ROUTE")"
[[ -n "${GATEWAY:-}" ]] || { echo "WARN: cannot detect default gateway; static mode may fail."; }

# Detect disk: prefer the root device's parent disk; fallback to first disk
detect_disk() {
  local root_src pk
  root_src="$(findmnt -n -o SOURCE / || true)"  # e.g. /dev/sda2 or /dev/nvme0n1p3
  if [[ -n "$root_src" && -b "$root_src" ]]; then
    pk="$(lsblk -no PKNAME "$root_src" 2>/dev/null || true)"
    if [[ -n "$pk" && -b "/dev/$pk" ]]; then
      echo "/dev/$pk"
      return
    fi
  fi
  # fallback: first 'disk'
  lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print "/dev/"$1; exit}'
}

DISK="${TARGET_DISK:-$(detect_disk)}"
[[ -n "${DISK:-}" ]] || die "Cannot detect target disk. Set TARGET_DISK=/dev/XXX and retry."
[[ "$(lsblk -no TYPE "$DISK")" == "disk" ]] || die "$DISK is not a whole-disk block device."

# Show plan and confirm
echo
echo "Install plan:"
echo "  CHR version : $CHR_VERSION"
echo "  Target disk : $DISK (WILL BE ERASED)"
echo "  Net device  : $DEV"
echo "  Mode        : $NETWORK_MODE"
if [[ "$NETWORK_MODE" == "static" ]]; then
  echo "  IP/CIDR     : ${IPCIDR:-<unknown>}"
  echo "  Gateway     : ${GATEWAY:-<unknown>}"
else
  echo "  DHCP client : enabled on ether1"
fi
echo
lsblk -o NAME,SIZE,TYPE,MODEL | sed 's/^/  /'
echo
read -r -p "Type YES to erase $DISK and install CHR $CHR_VERSION: " ANS
[[ "$ANS" == "YES" ]] || { echo "Cancelled."; exit 1; }

# Work dirs & cleanup
WORKDIR="$(mktemp -d)"
MNTDIR="$(mktemp -d)"
cleanup() {
  sync || true
  mountpoint -q "$MNTDIR" && umount "$MNTDIR" || true
  rm -rf "$WORKDIR" "$MNTDIR" || true
}
trap cleanup EXIT

cd "$WORKDIR"

IMGZIP="chr-${CHR_VERSION}.img.zip"
IMG="chr-${CHR_VERSION}.img"
URL="https://download.mikrotik.com/routeros/${CHR_VERSION}/chr-${CHR_VERSION}.img.zip"

echo "[1/6] Downloading image: $URL"
wget -q --show-progress -O "$IMGZIP" "$URL"

echo "[2/6] Unzipping image..."
unzip -q "$IMGZIP"

# Try to mount RW partition to write autorun.scr
echo "[3/6] Writing autorun script..."
mounted=false
# Try common offsets
for off in 512 1048576; do
  if mount -o "loop,offset=${off}" "$IMG" "$MNTDIR" 2>/dev/null; then
    mounted=true
    break
  fi
done

if $mounted; then
  mkdir -p "$MNTDIR/rw"
  if [[ "$NETWORK_MODE" == "dhcp" ]]; then
    cat > "$MNTDIR/rw/autorun.scr" <<'RSC'
/ip dhcp-client add interface=ether1 disabled=no
RSC
  else
    if [[ -z "${IPCIDR:-}" || -z "${GATEWAY:-}" ]]; then
      echo "WARN: missing IPCIDR/GATEWAY; falling back to DHCP."
      cat > "$MNTDIR/rw/autorun.scr" <<'RSC'
/ip dhcp-client add interface=ether1 disabled=no
RSC
    else
      cat > "$MNTDIR/rw/autorun.scr" <<RSC
/ip address add address=${IPCIDR} interface=ether1
/ip route add gateway=${GATEWAY}
RSC
    fi
  fi
  sync
  umount "$MNTDIR" || true
else
  echo "WARN: cannot mount image to write autorun.scr. Device may boot without IP; use Winbox MAC or console."
fi

echo "[4/6] Syncing caches..."
sync

echo "[5/6] Writing image to $DISK (this will take a while)..."
dd if="$IMG" of="$DISK" bs=1M status=progress conv=fsync

echo "[6/6] Final sync & reboot..."
sync
# Try sysrq reboot; if not available, force reboot
echo u > /proc/sysrq-trigger 2>/dev/null || true
sleep 1
reboot -f
```
