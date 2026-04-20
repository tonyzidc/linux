# Linux Helpers (Debian/Ubuntu)

This repository provides utility scripts for Debian/Ubuntu: server bootstrap (`auto-init-server.sh`) and swap setup (`auto-create-swap.sh`).

---

## 1) auto-init-server.sh (Debian 11/12, Ubuntu 22.04/24.04)

Run this script as **root**. It is designed to be executed **once** on a fresh server for fast initial setup.

### Quick run from GitHub (public)

```bash
curl -fsSL "https://raw.githubusercontent.com/tonyzidc/linux/main/auto-init-server.sh" | sudo bash
```

### Run locally

```bash
chmod +x auto-init-server.sh
sudo ./auto-init-server.sh
```

### What the script does

1. **OS upgrade**: sets `DEBIAN_FRONTEND=noninteractive`, runs `apt-get full-upgrade`, `autoremove --purge`, and `clean`; keeps existing config when apt prompts (`--force-confdef` / `--force-confold`). Sets `NEEDRESTART_MODE=a` when `needrestart` is present.
2. **Swap = RAM**: reads `MemTotal` from `/proc/meminfo`, creates `/swapfile` equal to RAM (`fallocate`, fallback `dd`), runs `mkswap` and `swapon`, and updates `/etc/fstab`; if `/swapfile` already exists, it disables old swap and recreates it.
3. **Swap tuning**: writes `/etc/sysctl.d/99-swap-tuning.conf` with `vm.swappiness=10` and `vm.vfs_cache_pressure=50`.
4. **Docker**: adds the official Docker repository based on detected OS, installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, then enables and restarts Docker.
5. **fail2ban**: installs package, writes `/etc/fail2ban/jail.d/local.conf` (enables `sshd` jail), then enables and restarts service.
6. **VPS benchmark**: runs YABS via `bash <(curl -fsSL https://yabs.sh) -f` to test CPU/RAM/disk/network.
7. **Streaming IP check**: first tries `bash <(curl -L -s media.ispvps.com)`; if it fails, falls back to RegionRestrictionCheck `bash <(curl -fsSL https://raw.githubusercontent.com/lmc999/RegionRestrictionCheck/main/check.sh)`.

### Supported operating systems

- **Debian**: 11, 12
- **Ubuntu**: 22.04, 24.04

Other OSes/versions are rejected by the script.

### Notes

- The script currently **does not reboot the server automatically**.
- Save shell scripts with **LF** line endings when running on Linux. If edited on Windows, convert CRLF -> LF (example: `sed -i 's/\r$//' auto-init-server.sh`).

---

## 2) auto-create-swap.sh (Debian 11/12, Ubuntu 22.04/24.04)

This script automatically creates and configures a swapfile based on RAM size, including `vm.swappiness` and `vm.vfs_cache_pressure` tuning.

### Quick run from GitHub (public)

```bash
curl -fsSL "https://raw.githubusercontent.com/tonyzidc/linux/main/auto-create-swap.sh" | sudo bash -s -- --yes
```

Force recreate `/swapfile` even when swap is already active:

```bash
curl -fsSL "https://raw.githubusercontent.com/tonyzidc/linux/main/auto-create-swap.sh" | sudo bash -s -- --force
```

### Run locally

```bash
chmod +x auto-create-swap.sh
sudo ./auto-create-swap.sh
```

### Options

- `-y`, `--yes`: non-interactive mode, auto-confirms prompts.
- `-f`, `--force`: recreates `/swapfile` without asking.
- `-h`, `--help`: shows usage help.

### What the script does

- Detects total RAM from `/proc/meminfo`.
- Calculates recommended swap size.
- Creates `/swapfile`, applies `chmod 600`, runs `mkswap` and `swapon`.
- Persists swap entry in `/etc/fstab`.
- Writes tuning values to `/etc/sysctl.d/99-swap-tuning.conf`:
  - `vm.swappiness=10`
  - `vm.vfs_cache_pressure=50`

### Verify after running

```bash
free -h
swapon --show
sysctl vm.swappiness vm.vfs_cache_pressure
```
