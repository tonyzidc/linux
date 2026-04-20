# Linux helpers (Debian)

Repo gom script tien ich cho Debian: khoi tao server (`auto-init-server.sh`) va tao swap (`auto-create-swap.sh`).

---

## auto-init-server.sh (Debian 11 / 12)

Script **root**, chay **mot lan** tren may moi: nang cap OS day du, swap bang RAM, Docker day du, fail2ban, roi **reboot** (SSH se ngat ket noi).

### Chay nhanh tu GitHub (project public)

```bash
curl -fsSL "https://raw.githubusercontent.com/tonyzidc/linux/main/auto-init-server.sh" | sudo bash
```

### Chay local

```bash
chmod +x auto-init-server.sh
sudo ./auto-init-server.sh
```

### Script lam gi?

1. **Nang cap OS**: `DEBIAN_FRONTEND=noninteractive`, `apt-get full-upgrade` (co the nang kernel), `autoremove --purge`, `clean`; giu cau hinh cu khi apt hoi (`--force-confdef` / `--force-confold`). Dat `NEEDRESTART_MODE=a` neu co `needrestart`.
2. **Swap = RAM**: doc `MemTotal` tu `/proc/meminfo`, tao `/swapfile` dung bang RAM (`fallocate`, fallback `dd`), `mkswap`, `swapon`, them `/etc/fstab`; neu da co `/swapfile` thi `swapoff`, xoa dong fstab cu, tao lai. Ghi `/etc/sysctl.d/99-swap-tuning.conf` (`vm.swappiness=10`, `vm.vfs_cache_pressure=50`).
3. **Docker**: them repo Docker chinh thuc, cai `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, `systemctl enable` + `restart docker`.
4. **fail2ban**: cai goi, ghi `/etc/fail2ban/jail.d/local.conf` (DEFAULT + `sshd` bat), `enable` + `restart fail2ban`.
5. **Reboot**: sau 5 giay chay `systemctl reboot` (co the Ctrl+C truoc khi reboot).

Chi chay tren **Debian** voi **VERSION_ID** 11 hoac 12; cac OS khac script se thoat.

### Luu y

- File script can **ket thuc dong LF** khi chay tren Linux; neu sua tren Windows, doi CRLF -> LF (vd. `sed -i 's/\r$//' auto-init-server.sh` tren may Linux).

---

## auto-create-swap.sh

Script tao va cau hinh swapfile tu dong theo dung luong RAM, kem tuning `vm.swappiness` va `vm.vfs_cache_pressure`.

### Chay nhanh tu GitHub (project public)

```bash
curl -fsSL "https://raw.githubusercontent.com/tonyzidc/linux/main/auto-create-swap.sh" | sudo bash -s -- --yes
```

Neu muon ep tao lai `/swapfile` ngay ca khi da co swap dang active:

```bash
curl -fsSL "https://raw.githubusercontent.com/tonyzidc/linux/main/auto-create-swap.sh" | sudo bash -s -- --force
```

### Chay local

```bash
chmod +x auto-create-swap.sh
sudo ./auto-create-swap.sh
```

### Options (auto-create-swap)

- `-y`, `--yes`: chay non-interactive, tu dong xac nhan prompt.
- `-f`, `--force`: recreate `/swapfile` ma khong hoi.
- `-h`, `--help`: hien thi huong dan.

### auto-create-swap se lam gi?

- Detect tong RAM tu `/proc/meminfo`.
- Tinh kich thuoc swap de xuat theo RAM.
- Tao `/swapfile`, `chmod 600`, `mkswap`, `swapon`.
- Them vao `/etc/fstab` de tu khoi dong lai van con swap.
- Ghi tuning vao `/etc/sysctl.d/99-swap-tuning.conf`:
  - `vm.swappiness=10`
  - `vm.vfs_cache_pressure=50`

### Kiem tra sau khi chay (auto-create-swap)

```bash
free -h
swapon --show
sysctl vm.swappiness vm.vfs_cache_pressure
```
