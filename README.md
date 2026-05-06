# KVM AutoSetup — v1.0.0

> Sistem provisioning VM berbasis KVM yang interaktif dan otomatis.

---

## Apa yang ada di v1.0.0

### 1. Deteksi & Pemilihan OS
- **Auto-deteksi OS host** — script membaca `/etc/os-release` dan menentukan package manager yang digunakan untuk install dependensi KVM di host
- **Pilih OS target VM** secara interaktif di awal proses
- **Package manager adaptif** — setiap perintah install menyesuaikan distro target:
  - Ubuntu / Debian → `apt`
  - Arch Linux / CachyOS → `pacman`
  - AlmaLinux / Rocky Linux → `dnf`

OS yang didukung sebagai target VM:

| OS | Variant | Cloud Image |
|----|---------|-------------|
| Ubuntu 22.04 LTS (Jammy) | `ubuntu22.04` | cloud-images.ubuntu.com |
| Ubuntu 24.04 LTS (Noble) | `ubuntu24.04` | cloud-images.ubuntu.com |
| Debian 12 (Bookworm) | `debian12` | cloud.debian.org |
| Arch Linux (rolling) | `archlinux` | pkgbuild.com mirror |
| CachyOS (Arch-based) | `archlinux` | Arch base + manual repo |
| AlmaLinux 9 | `almalinux9` | repo.almalinux.org |
| Rocky Linux 9 | `rocky9` | download.rockylinux.org |

### 2. Spesifikasi VM Fleksibel
Untuk setiap role VM, user sekarang dapat memilih:
- Gunakan **default** (2 vCPU, 2 GB RAM, 20 GB Disk), atau
- Tentukan **custom spec** sendiri:
  - **vCPU**: 1–64 core
  - **RAM**: 1–256 GB
  - **Disk**: 5–2000 GB

Tabel review sekarang menampilkan kolom spesifikasi dengan satuan yang jelas (GB).

---

## Cara Penggunaan

```bash
sudo bash kvm-autosetup.sh
```

### Alur Interaktif

```
Langkah 0 — Deteksi host OS + pilih OS target VM
Langkah 1 — Pilih role VM (Frontend / Backend / DB / ...)
Langkah 2 — Konfigurasi per-role:
             • Nama VM
             • Spesifikasi (default atau custom)
             • IP / DHCP
             • Mode (kosong / Docker / stack langsung)
Langkah 3 — Review & konfirmasi
Langkah 4 — Download base image OS yang dipilih
Langkah 5 — Buat VM (cloud-init + virt-install)
Langkah 6 — Ringkasan hasil
```

---

## Script Lainnya

| Script | Fungsi |
|--------|--------|
| `vm-status.sh` | Lihat status semua VM (`--json` untuk output JSON) |
| `vm-destroy.sh <nama>` | Hapus satu VM beserta disk-nya |
| `vm-destroy.sh --all` | Hapus semua VM (konfirmasi diperlukan) |
| `generate-compose.sh` | Generate template Docker Compose per role |

---

## Persyaratan Host

- OS Linux (Ubuntu/Debian, Arch, RHEL/Fedora based)
- CPU dengan dukungan virtualisasi (VT-x / AMD-V)
- RAM minimal 4 GB (untuk menjalankan VM)
- Jalankan sebagai `root` / `sudo`

---

## Default Specs VM

| Parameter | Default |
|-----------|---------|
| vCPU | 2 core |
| RAM | 2 GB |
| Disk | 20 GB |
| Network | DHCP via `virbr0` |
| Bridge | `virbr0` |
