# Auto Create Swap (Debian/Linux)

Script tao va cau hinh swapfile tu dong theo dung luong RAM, kem tuning `vm.swappiness` va `vm.vfs_cache_pressure`.

## Chay nhanh tu GitHub (project public)

```bash
curl -fsSL "https://raw.githubusercontent.com/tonyzidc/linux/main/auto-create-swap.sh" | sudo bash -s -- --yes
```

Neu muon ep tao lai `/swapfile` ngay ca khi da co swap dang active:

```bash
curl -fsSL "https://raw.githubusercontent.com/tonyzidc/linux/main/auto-create-swap.sh" | sudo bash -s -- --force
```

## Chay local

```bash
chmod +x auto-create-swap.sh
sudo ./auto-create-swap.sh
```

## Options

- `-y`, `--yes`: chay non-interactive, tu dong xac nhan prompt.
- `-f`, `--force`: recreate `/swapfile` ma khong hoi.
- `-h`, `--help`: hien thi huong dan.

## Script se lam gi?

- Detect tong RAM tu `/proc/meminfo`.
- Tinh kich thuoc swap de xuat theo RAM.
- Tao `/swapfile`, `chmod 600`, `mkswap`, `swapon`.
- Them vao `/etc/fstab` de tu khoi dong lai van con swap.
- Ghi tuning vao `/etc/sysctl.d/99-swap-tuning.conf`:
  - `vm.swappiness=10`
  - `vm.vfs_cache_pressure=50`

## Kiem tra sau khi chay

```bash
free -h
swapon --show
sysctl vm.swappiness vm.vfs_cache_pressure
```
