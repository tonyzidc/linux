#!/usr/bin/env bash
set -euo pipefail

# ==========================================
# Auto Swap Creator for Debian 11/12 and Ubuntu 22/24
# - Detects total RAM
# - Chooses a reasonable swap size
# - Creates and enables swapfile
# - Persists across reboot
# ==========================================

SWAPFILE="/swapfile"
SWAPPINESS="10"
VFS_CACHE_PRESSURE="50"
AUTO_YES=0
FORCE_RECREATE=0

log() {
  echo "[INFO] $1"
}

warn() {
  echo "[WARN] $1"
}

err() {
  echo "[ERROR] $1" >&2
}

usage() {
  cat <<'EOF'
Usage: auto-create-swap.sh [options]

Options:
  -y, --yes      Non-interactive mode, auto-confirm prompts
  -f, --force    Recreate /swapfile without asking when swap exists
  -h, --help     Show this help message
EOF
}

parse_args() {
  while (($#)); do
    case "$1" in
      -y|--yes)
        AUTO_YES=1
        ;;
      -f|--force)
        FORCE_RECREATE=1
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unknown option: $1"
        usage
        exit 1
        ;;
    esac
    shift
  done
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    err "Please run this script as root."
    exit 1
  fi
}

check_os() {
  if [[ -f /etc/os-release ]]; then
    . /etc/os-release
    case "${ID:-}" in
      debian)
        case "${VERSION_ID:-}" in
          11|12) ;;
          *)
            err "Unsupported Debian version: ${VERSION_ID:-unknown}. Supported: 11, 12."
            exit 1
            ;;
        esac
        ;;
      ubuntu)
        case "${VERSION_ID:-}" in
          22.04|24.04) ;;
          *)
            err "Unsupported Ubuntu version: ${VERSION_ID:-unknown}. Supported: 22.04, 24.04."
            exit 1
            ;;
        esac
        ;;
      *)
        err "Unsupported OS: ${PRETTY_NAME:-unknown}. Supported: Debian 11/12, Ubuntu 22.04/24.04."
        exit 1
        ;;
    esac
  else
    err "Cannot read /etc/os-release."
    exit 1
  fi
}

get_total_ram_mb() {
  awk '/MemTotal/ {printf "%d", $2/1024}' /proc/meminfo
}

get_recommended_swap_mb() {
  local ram_mb="$1"
  local swap_mb=0

  # Quy tắc thực tế, cân bằng giữa hiệu năng và tài nguyên:
  # <= 2GB RAM   -> swap = 2x RAM
  # <= 4GB RAM   -> swap = 1.5x RAM
  # <= 8GB RAM   -> swap = 1x RAM
  # <= 16GB RAM  -> swap = 0.5x RAM
  # > 16GB RAM   -> swap = 4GB ~ 8GB tùy RAM
  #
  # Mục tiêu: đủ để chống OOM, không quá lãng phí disk.
  if (( ram_mb <= 2048 )); then
    swap_mb=$(( ram_mb * 2 ))
  elif (( ram_mb <= 4096 )); then
    swap_mb=$(( ram_mb * 3 / 2 ))
  elif (( ram_mb <= 8192 )); then
    swap_mb=$ram_mb
  elif (( ram_mb <= 16384 )); then
    swap_mb=$(( ram_mb / 2 ))
  elif (( ram_mb <= 32768 )); then
    swap_mb=4096
  else
    swap_mb=8192
  fi

  # Sàn/tối thiểu
  if (( swap_mb < 1024 )); then
    swap_mb=1024
  fi

  echo "$swap_mb"
}

swap_exists() {
  swapon --show | grep -q .
}

swapfile_exists_in_fstab() {
  awk '$1 == "/swapfile" && $3 == "swap" {found=1} END {exit !found}' /etc/fstab
}

remove_old_swapfile_if_needed() {
  if [[ -f "$SWAPFILE" ]]; then
    warn "$SWAPFILE already exists."
    if swapon --show=NAME | grep -qx "$SWAPFILE"; then
      warn "Existing swapfile is active. Disabling it first..."
      swapoff "$SWAPFILE"
    fi
    rm -f "$SWAPFILE"
    log "Old swapfile removed."
  fi
}

create_swapfile() {
  local swap_mb="$1"

  log "Creating swapfile: ${swap_mb}MB"

  # fallocate nhanh hơn; nếu lỗi thì fallback sang dd
  if fallocate -l "${swap_mb}M" "$SWAPFILE" 2>/dev/null; then
    :
  else
    warn "fallocate failed, falling back to dd..."
    dd if=/dev/zero of="$SWAPFILE" bs=1M count="$swap_mb" status=progress
  fi

  chmod 600 "$SWAPFILE"
  mkswap "$SWAPFILE" >/dev/null
  swapon "$SWAPFILE"
}

persist_swapfile() {
  if ! swapfile_exists_in_fstab; then
    echo "$SWAPFILE none swap sw 0 0" >> /etc/fstab
    log "Added swapfile to /etc/fstab"
  else
    log "Swapfile entry already exists in /etc/fstab"
  fi
}

set_sysctl_value() {
  local key="$1"
  local value="$2"
  local conf_file="/etc/sysctl.d/99-swap-tuning.conf"

  if [[ -f "$conf_file" ]]; then
    sed -i "/^${key}\s*=/d" "$conf_file"
  fi

  echo "${key}=${value}" >> "$conf_file"
  sysctl -w "${key}=${value}" >/dev/null
}

show_result() {
  echo
  log "Swap setup completed."
  echo "========== MEMORY =========="
  free -h
  echo
  echo "========== SWAP DETAIL =========="
  swapon --show
  echo
  echo "========== SYSCTL =========="
  sysctl vm.swappiness vm.vfs_cache_pressure
}

main() {
  parse_args "$@"
  require_root
  check_os

  local ram_mb
  local swap_mb

  ram_mb="$(get_total_ram_mb)"
  swap_mb="$(get_recommended_swap_mb "$ram_mb")"

  log "Detected RAM: ${ram_mb}MB"
  log "Recommended swap size: ${swap_mb}MB"

  if swap_exists; then
    warn "System already has active swap:"
    swapon --show
    echo
    if (( FORCE_RECREATE == 1 || AUTO_YES == 1 )); then
      log "Auto-confirm enabled. Recreating swap..."
    else
      if [[ ! -t 0 ]]; then
        err "Non-interactive shell detected. Re-run with --yes or --force."
        exit 1
      fi

      read -r -p "Do you want to recreate swap using recommended size? [y/N]: " answer
      if [[ ! "${answer,,}" =~ ^y(es)?$ ]]; then
        log "Aborted by user."
        exit 0
      fi
    fi
  fi

  remove_old_swapfile_if_needed
  create_swapfile "$swap_mb"
  persist_swapfile

  log "Applying swap tuning..."
  set_sysctl_value "vm.swappiness" "$SWAPPINESS"
  set_sysctl_value "vm.vfs_cache_pressure" "$VFS_CACHE_PRESSURE"

  show_result
}

main "$@"