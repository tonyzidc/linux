#!/usr/bin/env bash
# auto-init-server.sh — Debian 11/12 + Ubuntu 22/24: full upgrade, swap = RAM, Docker, fail2ban, benchmark + media check.
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

case "${ID:-}" in
  debian)
    case "${VERSION_ID:-}" in
      11|12) ;;
      *)
        echo "Ho tro Debian 11/12; phien ban hien tai: ${VERSION_ID:-unknown}." >&2
        exit 1
        ;;
    esac
    ;;
  ubuntu)
    case "${VERSION_ID:-}" in
      22.04|24.04) ;;
      *)
        echo "Ho tro Ubuntu 22.04/24.04; phien ban hien tai: ${VERSION_ID:-unknown}." >&2
        exit 1
        ;;
    esac
    ;;
  *)
    echo "Script chi ho tro Debian 11/12 hoac Ubuntu 22.04/24.04 (hien tai: ${ID:-unknown} ${VERSION_ID:-unknown})." >&2
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

# true neu nguoi dung chon y/yes (doc tu stdin TTY hoac /dev/tty khi pipe curl|bash)
confirm_run() {
  local msg="$1"
  local input=/dev/stdin
  if [ ! -t 0 ]; then
    if [ -r /dev/tty ]; then
      input=/dev/tty
    else
      log "Khong co TTY — bo qua: ${msg}"
      return 1
    fi
  fi
  local ans
  read -r -p "${msg} [y/N]: " ans <"${input}" || return 1
  [[ "${ans,,}" =~ ^y(es)?$ ]]
}

# mem_kb: MemTotal (kB) tu /proc/meminfo
swapfile_ready() {
  local mem_kb="$1"
  local want_bytes=$((mem_kb * 1024))
  [ -f /swapfile ] || return 1
  local sz
  sz="$(stat -c%s /swapfile 2>/dev/null)" || return 1
  local diff=$((sz > want_bytes ? sz - want_bytes : want_bytes - sz))
  [ "$diff" -le 16384 ] || return 1
  swapon --show=NAME 2>/dev/null | grep -qx '/swapfile' || return 1
  awk '$1 == "/swapfile" && $3 == "swap" {found=1} END {exit !found}' /etc/fstab || return 1
  return 0
}

docker_ready() {
  command -v docker >/dev/null 2>&1 || return 1
  dpkg -s docker-ce >/dev/null 2>&1 || return 1
  systemctl is-active --quiet docker 2>/dev/null || return 1
  return 0
}

fail2ban_ready() {
  dpkg -s fail2ban >/dev/null 2>&1 || return 1
  systemctl is-active --quiet fail2ban 2>/dev/null || return 1
  return 0
}

# Jail hardening file trong repo: config/fail2ban/jail.d/zz-hardening.local
# Khi chay qua curl|bash: tai tu GitHub (ghi de bien FAIL2BAN_JAIL_CONFIG_URL neu can)
DEFAULT_FAIL2BAN_JAIL_URL='https://raw.githubusercontent.com/tonyzidc/linux/main/config/fail2ban/jail.d/zz-hardening.local'
install_fail2ban_jail_config() {
  local dst=/etc/fail2ban/jail.d/zz-hardening.local
  install -d -m 0755 /etc/fail2ban/jail.d
  local bundled=""
  local s="${BASH_SOURCE[0]:-}"
  if [ -n "${s}" ] && [ "${s}" != "-" ] && [ -f "${s}" ]; then
    bundled="$(cd "$(dirname "${s}")" && pwd)/config/fail2ban/jail.d/zz-hardening.local"
  fi
  if [ -n "${bundled}" ] && [ -f "${bundled}" ]; then
    install -m 0644 "${bundled}" "${dst}"
    log "Da dat jail fail2ban (tu file repo): ${dst}"
  else
    local url="${FAIL2BAN_JAIL_CONFIG_URL:-${DEFAULT_FAIL2BAN_JAIL_URL}}"
    log "Tai jail fail2ban tu: ${url}"
    curl -fsSL "${url}" -o "${dst}.new"
    mv "${dst}.new" "${dst}"
    chmod 0644 "${dst}"
  fi
}

# --- b1: nang cap OS day du (full-upgrade, khong hoi, giu cau hinh cu khi co the) ---
log "==> [b1] Cap nhat va nang cap he dieu hanh (full-upgrade)..."
"${APT_FULL[@]}" update
"${APT_FULL[@]}" full-upgrade
"${APT_FULL[@]}" autoremove --purge
"${APT_FULL[@]}" clean

# --- b2: swap bang dung luong RAM ---
MEM_KB="$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)"
if [ -z "${MEM_KB}" ] || ! [[ "${MEM_KB}" =~ ^[0-9]+$ ]]; then
  echo "Khong doc duoc MemTotal." >&2
  exit 1
fi

WANT_BYTES=$((MEM_KB * 1024))

if swapfile_ready "${MEM_KB}"; then
  log "==> [b2] Swap da thiet lap (/swapfile = RAM, da bat, co trong fstab) — bo qua."
else
  log "==> [b2] Tao swap bang dung luong RAM..."
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
fi

SYSCTL_SWAP=/etc/sysctl.d/99-swap-tuning.conf
cat > "${SYSCTL_SWAP}" << 'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF
sysctl --system >/dev/null || sysctl -p "${SYSCTL_SWAP}" || true

# --- b3: Docker (repo chinh thuc, goi day du) ---
if docker_ready; then
  log "==> [b3] Docker (docker-ce) da cai va dang chay — bo qua."
else
  log "==> [b3] Cai dat Docker..."
  "${APT_FULL[@]}" install ca-certificates curl gnupg

  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL "https://download.docker.com/linux/${ID}/gpg" | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${ID} ${VERSION_CODENAME} stable" \
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
fi

# --- b4: fail2ban ---
if fail2ban_ready; then
  log "==> [b4] fail2ban da cai va dang chay — bo qua."
else
  log "==> [b4] Cai dat va kich hoat fail2ban..."
  "${APT_FULL[@]}" install fail2ban
  install_fail2ban_jail_config
  systemctl enable fail2ban
  systemctl restart fail2ban
fi

# --- b6: benchmark VPS hieu nang/toc do ---
log "==> [b6] Benchmark VPS (YABS)..."
if confirm_run "Ban co muon chay benchmark VPS (YABS)"; then
  if command -v curl >/dev/null 2>&1; then
    if ! bash <(curl -fsSL https://yabs.sh) -f; then
      log "Canh bao: YABS chay that bai, bo qua de tiep tuc."
    fi
  else
    log "Canh bao: thieu curl, bo qua benchmark YABS."
  fi
else
  log "Da bo qua benchmark YABS."
fi

# --- b7: kiem tra IP stream/media unlock ---
log "==> [b7] Kiem tra IP stream..."
if confirm_run "Ban co muon chay kiem tra IP stream / media unlock"; then
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
else
  log "Da bo qua kiem tra IP stream."
fi

log "==> Hoan tat. Script KHONG tu reboot server."
