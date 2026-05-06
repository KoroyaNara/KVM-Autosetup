# KVM AutoSetup — Interactive VM Provisioning System

```
  ██╗  ██╗██╗   ██╗███╗   ███╗     █████╗ ██╗   ██╗████████╗ ██████╗
  ██║ ██╔╝██║   ██║████╗ ████║    ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗
  █████╔╝ ██║   ██║██╔████╔██║    ███████║██║   ██║   ██║   ██║   ██║
  ██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║    ██╔══██║██║   ██║   ██║   ██║   ██║
  ██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║    ██║  ██║╚██████╔╝   ██║   ╚██████╔╝
  ╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚═╝    ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝
```

> **Automated KVM VM Provisioning** — Provisioning VM interaktif berbasis cloud-init, multi-distro host & guest, dengan dukungan Docker Compose stack siap pakai.

**Versi:** v1.0.0 | **Author:** Koroya

---

## Daftar Isi

- [Fitur](#fitur)
- [Persyaratan](#persyaratan)
- [Instalasi & Penggunaan](#instalasi--penggunaan)
- [Alur Interaktif](#alur-interaktif)
- [Role VM yang Tersedia](#role-vm-yang-tersedia)
- [OS Guest yang Didukung](#os-guest-yang-didukung)
- [Stack Teknologi](#stack-teknologi)
- [Struktur Direktori](#struktur-direktori)
- [Konfigurasi Jaringan](#konfigurasi-jaringan)
- [Setelah VM Berjalan](#setelah-vm-berjalan)
- [Troubleshooting](#troubleshooting)

---

## Fitur

- **Multi-distro host** — berjalan di Debian/Ubuntu, Arch Linux, dan RHEL/Fedora; mendeteksi package manager host secara otomatis (`apt` / `pacman` / `dnf` / `yum`)
- **Multi-distro guest** — pilih OS target VM secara interaktif (Ubuntu, Debian, Arch, AlmaLinux, Rocky Linux)
- **Provisioning berbasis cloud-init** — user-data, meta-data, dan network-config di-generate otomatis per VM
- **Role-based provisioning** — setiap VM punya role (frontend, backend, database, monitoring, dll.)
- **Spesifikasi fleksibel** — konfigurasi vCPU, RAM, dan disk per VM, atau gunakan default
- **IP statis atau DHCP** — pilih per VM
- **Docker Compose ready** — stack langsung di-deploy via cloud-init; `docker-compose.yml` tersedia di dalam VM setelah boot
- **SSH key injection** — kunci publik host di-inject otomatis ke VM
- **Auto-install dependensi** — KVM, libvirt, cloud-init tools diinstall otomatis bila belum ada

---

## Persyaratan

### Host

| Komponen | Keterangan |
|---|---|
| CPU | Mendukung virtualisasi hardware (Intel VT-x / AMD-V) |
| OS | Debian/Ubuntu, Arch Linux, atau RHEL/Fedora/AlmaLinux/Rocky |
| RAM | Minimal 4 GB (rekomendasi ≥ 8 GB) |
| Disk | Ruang kosong sesuai total disk VM yang dibuat |
| Akses | `root` atau `sudo` |

### Dependensi (auto-install)

```
qemu-kvm  libvirt  virt-install  bridge-utils  cloud-image-utils  wget  curl  genisoimage
```

---

## Instalasi & Penggunaan

```bash
# Clone atau download skrip
git clone https://github.com/koroya/kvm-autosetup.git
cd kvm-autosetup

# Jalankan sebagai root
sudo bash kvm-autosetup.sh
```

> **Catatan:** Skrip harus dijalankan dengan `sudo` atau sebagai `root`. Bila tidak, skrip akan berhenti otomatis.

---

## Alur Interaktif

Skrip berjalan dalam 7 langkah terurut:

```
Langkah 0  →  Deteksi host OS & pemilihan OS target VM
Langkah 1  →  Pilih role VM
Langkah 2  →  Konfigurasi per-role (nama, spek, IP, mode, stack)
Langkah 3  →  Review & konfirmasi sebelum eksekusi
Langkah 4  →  Download base image cloud (skip jika sudah ada)
Langkah 5  →  Build cloud-init ISO & buat VM via virt-install
Langkah 6  →  Tampilkan ringkasan hasil
```

### Default Spesifikasi VM

| Parameter | Default |
|---|---|
| vCPU | 2 core |
| RAM | 2 GB |
| Disk | 20 GB |

---

## Role VM yang Tersedia

Pilih satu atau lebih role dalam satu sesi:

| Key | Role | Keterangan |
|---|---|---|
| `fe` | Frontend | React, Vue, Angular, Next.js, Nuxt.js, Static HTML/Nginx |
| `be` | Backend | Node.js, Laravel, Django, FastAPI, Spring Boot, Go |
| `febe` | Frontend + Backend | Kedua service dalam 1 VM via Docker Compose |
| `db` | Database | MySQL 8, PostgreSQL 16, MongoDB, MariaDB, Redis |
| `monitoring` | Monitoring | Wazuh SIEM, Grafana + Prometheus, Zabbix, Netdata |
| `lb` | Load Balancer | Nginx, HAProxy, Traefik, Caddy |
| `client` | Client / Admin | Desktop GUI (XFCE4), CLI tools, Cockpit, Portainer |

---

## OS Guest yang Didukung

| OS | Variant | Package Manager | Cloud Image |
|---|---|---|---|
| Ubuntu 22.04 LTS (Jammy) | `ubuntu22.04` | apt | Official |
| Ubuntu 24.04 LTS (Noble) | `ubuntu24.04` | apt | Official |
| Debian 12 (Bookworm) | `debian12` | apt | Official |
| Arch Linux (rolling) | `archlinux` | pacman | Official |
| CachyOS (Arch-based) | `archlinux` | pacman | Arch base* |
| AlmaLinux 9 | `almalinux9` | dnf | Official |
| Rocky Linux 9 | `rocky9` | dnf | Official |

> \* CachyOS tidak memiliki official cloud image. Menggunakan Arch Linux base; repo CachyOS dapat ditambahkan manual setelah VM berjalan.

### Default User per OS

| OS | Default User |
|---|---|
| Ubuntu | `ubuntu` |
| Debian | `debian` |
| Arch / CachyOS | `arch` |
| AlmaLinux / Rocky | `cloud-user` |

**Password default:** `ubuntu` (berlaku untuk semua OS guest)

---

## Stack Teknologi

### Mode Provisioning

Setiap role (kecuali `febe`) dapat dipilih salah satu dari tiga mode:

| Mode | Keterangan |
|---|---|
| **VM kosong** | Fresh install tanpa stack tambahan |
| **Docker saja** | Hanya install Docker & Docker Compose |
| **VM dengan stack langsung ter-install** | Install & aktifkan stack sesuai pilihan |

### Docker Compose Stack Built-in

Stack berikut sudah disertakan `docker-compose.yml`-nya dan akan ditulis otomatis ke dalam VM via cloud-init:

| Role | Stack | Compose Path di VM |
|---|---|---|
| `monitoring` | Wazuh SIEM | `~/monitoring/docker-compose.yml` |
| `monitoring` | Grafana + Prometheus | `~/monitoring/docker-compose.yml` + `prometheus.yml` |
| `monitoring` | Zabbix | `~/monitoring/docker-compose.yml` |
| `febe` | Frontend + Backend | `~/febe/docker-compose.yml` |

### Port Default Docker Compose

| Service | Port |
|---|---|
| Wazuh Manager | 1514, 1515, 55000 |
| Wazuh Indexer (OpenSearch) | 9200 |
| Wazuh Dashboard | 443 |
| Grafana | 3000 |
| Prometheus | 9090 |
| Node Exporter | 9100 |
| Zabbix Web | 80, 443 |
| Zabbix Server | 10051 |
| Frontend (febe) | 3000 |
| Backend (febe) | 5000 / 8000 / 8080 |

---

## Struktur Direktori

```
kvm-autosetup/
├── kvm-autosetup.sh          # Skrip utama
├── kvm-autosetup.log         # Log eksekusi (auto-generated)
├── configs/                  # Konfigurasi tambahan (auto-generated)
├── cloud-init/               # Cloud-init config per VM (auto-generated)
│   └── <vm-name>/
│       ├── user-data
│       ├── meta-data
│       └── network-config
└── roles/                    # Direktori roles (reserved)

/var/lib/libvirt/images/
├── base/                     # Base image cloud (hasil download)
│   ├── ubuntu-22.04-base.img
│   ├── ubuntu-24.04-base.img
│   ├── debian-12-base.qcow2
│   ├── arch-linux-base.qcow2
│   ├── almalinux-9-base.qcow2
│   └── rocky-9-base.qcow2
└── vms/                      # Disk image per VM
    ├── <vm-name>.qcow2
    └── <vm-name>-cloudinit.iso
```

---

## Konfigurasi Jaringan

- **Bridge default:** `virbr0` (libvirt NAT bridge)
- **Model NIC:** `virtio`
- **DHCP:** opsi default, IP assign otomatis oleh libvirt
- **IP Statis:** masukkan IP dalam format `192.168.x.x`; gateway di-generate otomatis (`192.168.x.1`), DNS: `8.8.8.8` dan `1.1.1.1`

---

## Setelah VM Berjalan

### Cek status VM

```bash
sudo bash vm-status.sh
```

### SSH ke VM

```bash
ssh <default-user>@<IP_VM>
# Contoh:
ssh ubuntu@192.168.122.10
```

### Jalankan Docker Compose (jika pakai stack Docker)

```bash
# Setelah SSH masuk ke VM
cd ~/monitoring        # atau ~/febe, ~/backend, dst.
docker compose up -d
```

### Lihat log provisioning

```bash
# Di host
tail -f /path/to/kvm-autosetup.log

# Di dalam VM (setelah boot)
cat /var/log/cloud-init-custom.log
```

### Autostart VM

Semua VM yang dibuat otomatis di-set `autostart` — akan hidup kembali saat host reboot.

---

## Troubleshooting

**Dependensi tidak ditemukan setelah install**
Restart `libvirtd` secara manual:
```bash
systemctl restart libvirtd
```

**VM sudah terdaftar / disk sudah ada**
Skrip akan skip otomatis tanpa error. Untuk membuat ulang, hapus dulu dengan:
```bash
sudo bash vm-destroy.sh
```

**Base image gagal diunduh**
Periksa koneksi internet dan URL di log. Anda juga bisa download manual dan letakkan di `/var/lib/libvirt/images/base/` dengan nama file yang sesuai.

**CachyOS tidak tersedia sebagai cloud image**
Gunakan Arch Linux base (dipilih otomatis). Tambahkan repo CachyOS secara manual di dalam VM setelah boot pertama.

**IP tidak muncul setelah VM start**
Tunggu beberapa detik, lalu cek via:
```bash
sudo bash vm-status.sh
```

---

## Lisensi

Proyek ini bebas digunakan dan dimodifikasi. Kontribusi dan feedback sangat disambut.
