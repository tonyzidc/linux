#!/usr/bin/env bash
# auto-init-server.sh — Debian 11/12: full upgrade, swap = RAM, Docker, fail2ban, benchmark + media check.
# Usage: sudo ./auto-init-server.sh

set -euo pipefail

if [ "${EUID:-$(id -u)}" -ne 0 ]; then
  echo "Chay voi quyen root: sudo $0" >&2
  exit 1
fi

if [ ! -f /etc/os-release ]; then
  echo "Khong doc duoc /etc/os-release." >&2
  exit 1
fi

# shellcheck source=/dev/null
. /etc/os-release

if [ "${ID:-}" != "debian" ]; then
  echo "Script chi danh cho Debian (hien tai: ${ID:-unknown})." >&2
  exit 1
fi

case "${VERSION_ID:-}" in
  11|12) ;;
  *)
    echo "Ho tro Debian 11 va 12; phien ban hien tai: ${VERSION_ID:-unknown}." >&2
    exit 1
    ;;
esac

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

APT_FULL=(
  apt-get
  -y
  -o Dpkg::Options::=--force-confdef
  -o Dpkg::Options::=--force-confold
)

log() { printf '%s\n' "$*"; }

# --- b1: nang cap OS day du (full-upgrade, khong hoi, giu cau hinh cu khi co the) ---
log "==> [b1] Cap nhat va nang cap he dieu hanh (full-upgrade)..."
"${APT_FULL[@]}" update
"${APT_FULL[@]}" full-upgrade
"${APT_FULL[@]}" autoremove --purge
"${APT_FULL[@]}" clean

# --- b2: swap bang dung luong RAM ---
log "==> [b2] Tao swap bang dung luong RAM..."
MEM_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
if [ -z "${MEM_KB}" ] || ! [[ "${MEM_KB}" =~ ^[0-9]+$ ]]; then
  echo "Khong doc duoc MemTotal." >&2
  exit 1
fi

WANT_BYTES=$((MEM_KB * 1024))

if [ -f /swapfile ]; then
  if swapon --show | grep -qF '/swapfile'; then
    swapoff /swapfile || true
  fi
  sed -i '\|/swapfile|d' /etc/fstab
  rm -f /swapfile
fi

if ! fallocate -l "${WANT_BYTES}" /swapfile 2>/dev/null; then
  dd if=/dev/zero of=/swapfile bs=1024 count="${MEM_KB}" status=none
fi
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile

if ! grep -qF '/swapfile' /etc/fstab; then
  echo '/swapfile none swap sw 0 0' >> /etc/fstab
fi

SYSCTL_SWAP=/etc/sysctl.d/99-swap-tuning.conf
cat > "${SYSCTL_SWAP}" << 'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl --system >/dev/null || sysctl -p "${SYSCTL_SWAP}" || true

# --- b3: Docker (repo chinh thuc, goi day du) ---
log "==> [b3] Cai dat Docker..."
"${APT_FULL[@]}" install ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/debian/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian ${VERSION_CODENAME} stable" \
  > /etc/apt/sources.list.d/docker.list

"${APT_FULL[@]}" update
"${APT_FULL[@]}" install \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker
systemctl restart docker

# --- b4: fail2ban ---
log "==> [b4] Cai dat va kich hoat fail2ban..."
"${APT_FULL[@]}" install fail2ban

JAIL_LOCAL=/etc/fail2ban/jail.d/local.conf
cat > "${JAIL_LOCAL}" << 'EOF'
[DEFAULT]
bantime = 1h
findtime = 10m
maxretry = 5

[sshd]
enabled = true
EOF

systemctl enable fail2ban
systemctl restart fail2ban

# --- b5: benchmark VPS hieu nang/toc do ---
log "==> [b5] Chay benchmark VPS (YABS)..."
if command -v curl >/dev/null 2>&1; then
  if ! bash <(curl -fsSL https://yabs.sh) -f; then
    log "Canh bao: YABS chay that bai, bo qua de tiep tuc."
  fi
else
  log "Canh bao: thieu curl, bo qua benchmark YABS."
fi

# --- b6: kiem tra IP stream/media unlock ---
log "==> [b6] Kiem tra IP stream..."
if command -v curl >/dev/null 2>&1; then
  if ! bash <(curl -L -s media.ispvps.com); then
    log "Canh bao: media.ispvps.com that bai, thu RegionRestrictionCheck..."
    if ! bash <(curl -fsSL https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh); then
      log "Canh bao: khong the chay kiem tra stream IP."
    fi
  fi
else
  log "Canh bao: thieu curl, bo qua kiem tra stream IP."
fi

log "==> Hoan tat. Script KHONG tu reboot server."
