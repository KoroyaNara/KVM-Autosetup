#!/usr/bin/env bash
# ============================================================
#  KVM AutoSetup — Interactive VM Provisioning System
#  Usage: sudo bash kvm-autosetup.sh
#  v1.1.0 — Added OS detection/selection + flexible VM specs
# ============================================================

set -euo pipefail

# ── Colors ──────────────────────────────────────────────────
RED='\033[0;31m';    GREEN='\033[0;32m';  YELLOW='\033[1;33m'
BLUE='\033[0;34m';   CYAN='\033[0;36m';  BOLD='\033[1m'
DIM='\033[2m';       RESET='\033[0m'

# ── Globals ─────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$SCRIPT_DIR/configs"
CLOUD_INIT_DIR="$SCRIPT_DIR/cloud-init"
ROLES_DIR="$SCRIPT_DIR/roles"
LOG_FILE="$SCRIPT_DIR/kvm-autosetup.log"
BRIDGE_NAME="virbr0"
BASE_IMAGE_DIR="/var/lib/libvirt/images/base"
VM_IMAGE_DIR="/var/lib/libvirt/images/vms"

# ── Default VM Specs ─────────────────────────────────────────
DEFAULT_VCPUS=2
DEFAULT_RAM_GB=2
DEFAULT_DISK_GB=20

# ── OS Target Globals ────────────────────────────────────────
# HOST_OS   : OS yang terdeteksi di host (untuk install deps KVM)
# TARGET_OS : OS yang dipilih user untuk VM guest
HOST_OS=""
TARGET_OS=""
TARGET_OS_LABEL=""
PKG_MANAGER=""      # package manager HOST (apt/pacman/dnf/yum)
OS_VARIANT=""       # untuk virt-install --os-variant
BASE_IMAGE_URL=""
BASE_IMAGE_FILE=""

declare -A VM_CONFIG
declare -a SELECTED_ROLES=()

# ── Logging ─────────────────────────────────────────────────
log()  { echo -e "$(date '+%F %T') [INFO]  $*" | tee -a "$LOG_FILE"; }
warn() { echo -e "$(date '+%F %T') [WARN]  $*" | tee -a "$LOG_FILE"; }
die()  { echo -e "${RED}$(date '+%F %T') [ERROR] $*${RESET}" | tee -a "$LOG_FILE"; exit 1; }

# ── Helpers ─────────────────────────────────────────────────
banner() {
  clear
  echo -e "${CYAN}${BOLD}"
  cat << 'EOF'
  ██╗  ██╗██╗   ██╗███╗   ███╗     █████╗ ██╗   ██╗████████╗ ██████╗
  ██║ ██╔╝██║   ██║████╗ ████║    ██╔══██╗██║   ██║╚══██╔══╝██╔═══██╗
  █████╔╝ ██║   ██║██╔████╔██║    ███████║██║   ██║   ██║   ██║   ██║
  ██╔═██╗ ╚██╗ ██╔╝██║╚██╔╝██║    ██╔══██║██║   ██║   ██║   ██║   ██║
  ██║  ██╗ ╚████╔╝ ██║ ╚═╝ ██║    ██║  ██║╚██████╔╝   ██║   ╚██████╔╝
  ╚═╝  ╚═╝  ╚═══╝  ╚═╝     ╚═╝    ╚═╝  ╚═╝ ╚═════╝    ╚═╝    ╚═════╝
EOF
  echo -e "${RESET}${DIM}  KVM Automated VM Provisioning System  •  v1.0.0${RESET}"
  echo -e "${DIM}  ──────────────────────────────────────────────────────${RESET}"
  echo -e "  ${DIM}by ${RESET}${CYAN}${BOLD}Koroya${RESET}"
  echo
}

section() { echo -e "\n${BLUE}${BOLD}▶  $*${RESET}\n"; }
ok()      { echo -e "  ${GREEN}✔${RESET}  $*"; }
info()    { echo -e "  ${CYAN}ℹ${RESET}  $*"; }
step()    { echo -e "  ${YELLOW}→${RESET}  $*"; }
prompt()  { echo -ne "  ${BOLD}$*${RESET} "; }

ask_yn() {
  local q="$1" def="${2:-y}"
  local hint="[Y/n]"; [[ "$def" == "n" ]] && hint="[y/N]"
  printf "  \033[1m%s %s: \033[0m" "$q" "$hint" > /dev/tty
  local ans
  read -r ans < /dev/tty
  ans="${ans:-$def}"
  [[ "${ans,,}" == "y" ]]
}

pick_one() {
  local p="$1"; shift
  local opts=("$@")
  echo -e "  ${BOLD}$p${RESET}" > /dev/tty
  local i=1
  for o in "${opts[@]}"; do
    echo -e "    ${DIM}$i)${RESET} $o" > /dev/tty
    ((i++))
  done
  local choice
  while true; do
    printf "  ${BOLD}Enter number [1-%s]: ${RESET}" "${#opts[@]}" > /dev/tty
    read -r choice < /dev/tty
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#opts[@]} )); then
      echo "${opts[$((choice-1))]}"
      return
    fi
    echo -e "  ${RED}Invalid choice, try again.${RESET}" > /dev/tty
  done
}

pick_many() {
  local p="$1"; shift
  local opts=("$@")
  echo -e "  ${BOLD}$p${RESET}" > /dev/tty
  local i=1
  for o in "${opts[@]}"; do
    echo -e "    ${DIM}$i)${RESET} $o" > /dev/tty
    ((i++))
  done
  echo -e "    ${DIM}Enter numbers separated by space, e.g: 1 3 5${RESET}" > /dev/tty
  local choices
  while true; do
    printf "  ${BOLD}Your selection: ${RESET}" > /dev/tty
    read -ra choices < /dev/tty
    local valid=1 result=()
    for c in "${choices[@]}"; do
      if [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#opts[@]} )); then
        result+=("${opts[$((c-1))]}")
      else
        valid=0; break
      fi
    done
    if (( valid && ${#result[@]} > 0 )); then
      echo "${result[*]}"
      return
    fi
    echo -e "  ${RED}Invalid selection, try again.${RESET}" > /dev/tty
  done
}

require_root() {
  [[ $EUID -eq 0 ]] || die "Script harus dijalankan sebagai root. Gunakan: sudo bash $0"
}

# ════════════════════════════════════════════════════════════
#  STEP 0: DETEKSI HOST OS & PEMILIHAN OS TARGET VM
# ════════════════════════════════════════════════════════════

_detect_host_os() {
  # Baca /etc/os-release untuk menentukan distro host
  if [[ -f /etc/os-release ]]; then
    local id_lower id_like_lower
    id_lower=$(grep -oP '(?<=^ID=)[^\n"]+' /etc/os-release | tr '[:upper:]' '[:lower:]' || echo "")
    id_like_lower=$(grep -oP '(?<=^ID_LIKE=)[^\n"]+' /etc/os-release | tr '[:upper:]' '[:lower:]' || echo "")

    case "$id_lower" in
      ubuntu|debian|linuxmint|pop|elementary|kali|zorin)
        HOST_OS="debian" ;;
      arch|cachyos|manjaro|endeavouros|artix|garuda)
        HOST_OS="arch" ;;
      fedora|rhel|centos|rocky|almalinux|ol|oracle)
        HOST_OS="rhel" ;;
      *)
        case "$id_like_lower" in
          *debian*|*ubuntu*) HOST_OS="debian" ;;
          *arch*)            HOST_OS="arch"   ;;
          *rhel*|*fedora*)   HOST_OS="rhel"   ;;
          *)                 HOST_OS="unknown" ;;
        esac
        ;;
    esac
  else
    HOST_OS="unknown"
  fi
}

_set_host_pkg_manager() {
  case "$HOST_OS" in
    debian) PKG_MANAGER="apt" ;;
    arch)   PKG_MANAGER="pacman" ;;
    rhel)
      if command -v dnf &>/dev/null; then
        PKG_MANAGER="dnf"
      else
        PKG_MANAGER="yum"
      fi
      ;;
    *)
      # Fallback: detect dari binary
      if   command -v apt-get  &>/dev/null; then PKG_MANAGER="apt"
      elif command -v pacman   &>/dev/null; then PKG_MANAGER="pacman"
      elif command -v dnf      &>/dev/null; then PKG_MANAGER="dnf"
      elif command -v yum      &>/dev/null; then PKG_MANAGER="yum"
      else die "Tidak dapat menentukan package manager. Install dependensi KVM secara manual."
      fi
      ;;
  esac
}

_install_deps_by_pm() {
  step "Menginstall dependensi KVM via ${PKG_MANAGER}..."
  case "$PKG_MANAGER" in
    apt)
      apt-get update -qq
      apt-get install -y -qq \
        qemu-kvm libvirt-daemon-system libvirt-clients \
        virtinst bridge-utils cloud-image-utils \
        genisoimage wget curl
      ;;
    pacman)
      pacman -Sy --noconfirm \
        qemu-full libvirt virt-install \
        bridge-utils cloud-image-utils \
        cdrtools wget curl
      systemctl enable --now libvirtd 2>/dev/null || true
      ;;
    dnf|yum)
      "$PKG_MANAGER" install -y -q \
        qemu-kvm libvirt libvirt-client virt-install \
        bridge-utils cloud-utils-growpart \
        genisoimage wget curl
      systemctl enable --now libvirtd 2>/dev/null || true
      ;;
  esac
}

step_detect_and_select_os() {
  section "Langkah 0: Deteksi Host OS & Pemilihan OS Target VM"

  # 1. Deteksi host
  _detect_host_os
  _set_host_pkg_manager

  local host_pretty="Unknown"
  if [[ -f /etc/os-release ]]; then
    host_pretty=$(grep -oP '(?<=^PRETTY_NAME=")[^"]+' /etc/os-release 2>/dev/null || echo "$HOST_OS")
  fi

  info "Host OS terdeteksi  : ${CYAN}${BOLD}${host_pretty}${RESET}"
  info "Package manager host: ${CYAN}${BOLD}${PKG_MANAGER}${RESET}"
  echo
  echo -e "  ${DIM}(Package manager di atas digunakan untuk install dependensi KVM di host)${RESET}"
  echo

  # 2. Pilih OS target VM (guest)
  info "Pilih OS untuk Guest VM yang akan dibuat:"
  echo

  local os_choices=(
    "Ubuntu 22.04 LTS (Jammy)      — Direkomendasikan, stabil, cloud image resmi"
    "Ubuntu 24.04 LTS (Noble)      — Ubuntu terbaru, LTS"
    "Debian 12 (Bookworm)          — Ringan, stabil, cloud image resmi"
    "Arch Linux (rolling)          — Rolling release, pacman, minimal"
    "CachyOS (Arch-based)          — Arch + optimisasi performa"
    "AlmaLinux 9 (RHEL-compatible) — Enterprise grade, dnf"
    "Rocky Linux 9 (RHEL-compatible)— Alternatif RHEL, dnf"
  )

  local chosen_os
  chosen_os=$(pick_one "Target OS untuk VM:" "${os_choices[@]}")

  case "$chosen_os" in
    "Ubuntu 22.04"*)
      TARGET_OS="ubuntu"; TARGET_OS_LABEL="Ubuntu 22.04 LTS (Jammy)"
      OS_VARIANT="ubuntu22.04"
      BASE_IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
      BASE_IMAGE_FILE="ubuntu-22.04-base.img"
      ;;
    "Ubuntu 24.04"*)
      TARGET_OS="ubuntu"; TARGET_OS_LABEL="Ubuntu 24.04 LTS (Noble)"
      OS_VARIANT="ubuntu24.04"
      BASE_IMAGE_URL="https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
      BASE_IMAGE_FILE="ubuntu-24.04-base.img"
      ;;
    "Debian 12"*)
      TARGET_OS="debian"; TARGET_OS_LABEL="Debian 12 (Bookworm)"
      OS_VARIANT="debian12"
      BASE_IMAGE_URL="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-genericcloud-amd64.qcow2"
      BASE_IMAGE_FILE="debian-12-base.qcow2"
      ;;
    "Arch Linux"*)
      TARGET_OS="arch"; TARGET_OS_LABEL="Arch Linux (rolling)"
      OS_VARIANT="archlinux"
      BASE_IMAGE_URL="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
      BASE_IMAGE_FILE="arch-linux-base.qcow2"
      ;;
    "CachyOS"*)
      TARGET_OS="arch"; TARGET_OS_LABEL="CachyOS (Arch-based)"
      OS_VARIANT="archlinux"
      BASE_IMAGE_URL="https://geo.mirror.pkgbuild.com/images/latest/Arch-Linux-x86_64-cloudimg.qcow2"
      BASE_IMAGE_FILE="arch-linux-base.qcow2"
      warn "CachyOS tidak memiliki official cloud image. Menggunakan Arch Linux base."
      warn "Tambahkan CachyOS repo secara manual setelah VM berjalan."
      ;;
    "AlmaLinux 9"*)
      TARGET_OS="rhel"; TARGET_OS_LABEL="AlmaLinux 9"
      OS_VARIANT="almalinux9"
      BASE_IMAGE_URL="https://repo.almalinux.org/almalinux/9/cloud/x86_64/images/AlmaLinux-9-GenericCloud-latest.x86_64.qcow2"
      BASE_IMAGE_FILE="almalinux-9-base.qcow2"
      ;;
    "Rocky Linux 9"*)
      TARGET_OS="rhel"; TARGET_OS_LABEL="Rocky Linux 9"
      OS_VARIANT="rocky9"
      BASE_IMAGE_URL="https://download.rockylinux.org/pub/rocky/9/images/x86_64/Rocky-9-GenericCloud-Base.latest.x86_64.qcow2"
      BASE_IMAGE_FILE="rocky-9-base.qcow2"
      ;;
  esac

  echo
  ok "Target OS VM       : ${CYAN}${BOLD}${TARGET_OS_LABEL}${RESET}"
  ok "OS Variant         : ${DIM}${OS_VARIANT}${RESET}"
  ok "Package mgr di VM  : ${CYAN}$(_guest_pm_label)${RESET}"
  echo
}

_guest_pm_label() {
  case "$TARGET_OS" in
    ubuntu|debian) echo "apt" ;;
    arch)          echo "pacman" ;;
    rhel)          echo "dnf" ;;
    *)             echo "apt" ;;
  esac
}

_guest_pm() {
  _guest_pm_label
}

# ── check_deps ───────────────────────────────────────────────
check_deps() {
  section "Memeriksa dependensi sistem (host)"
  local missing=()
  for cmd in virsh virt-install qemu-img wget; do
    if command -v "$cmd" &>/dev/null; then
      ok "$cmd tersedia"
    else
      missing+=("$cmd")
      echo -e "  ${RED}✘${RESET}  $cmd tidak ditemukan"
    fi
  done

  if command -v cloud-localds &>/dev/null || command -v genisoimage &>/dev/null; then
    ok "cloud-init tools tersedia"
  else
    missing+=("cloud-localds/genisoimage")
    echo -e "  ${RED}✘${RESET}  cloud-localds / genisoimage tidak ditemukan"
  fi

  if (( ${#missing[@]} > 0 )); then
    warn "Komponen kurang: ${missing[*]}"
    if ask_yn "Install dependensi KVM via ${PKG_MANAGER} sekarang?"; then
      _install_deps_by_pm
      ok "Dependensi berhasil diinstall"
    else
      die "Dependensi tidak lengkap. Abort."
    fi
  fi

  mkdir -p "$BASE_IMAGE_DIR" "$VM_IMAGE_DIR" "$CONFIG_DIR" "$CLOUD_INIT_DIR"
}

# ── Role definitions ─────────────────────────────────────────
declare -A ROLE_LABELS=(
  [fe]="Frontend"
  [be]="Backend"
  [db]="Database"
  [monitoring]="Monitoring (Wazuh/Grafana)"
  [lb]="Load Balancer / Nginx"
  [client]="Client / Admin"
)

# ── Step 1: Pilih roles ──────────────────────────────────────
step_select_roles() {
  section "Langkah 1: Pilih Role VM"
  info "Role yang tersedia:"
  echo
  local role_list=("Frontend" "Backend" "Database" "Monitoring (Wazuh/Grafana)" "Load Balancer / Nginx" "Client / Admin")
  local role_keys=("fe" "be" "db" "monitoring" "lb" "client")

  local chosen
  chosen=$(pick_many "Pilih role VM yang ingin dibuat:" "${role_list[@]}")
  SELECTED_ROLES=()

  for label in $chosen; do
    for i in "${!role_list[@]}"; do
      # shellcheck disable=SC2053
      if [[ "${role_list[$i]}" == "$label" ]]; then
        SELECTED_ROLES+=("${role_keys[$i]}")
      fi
    done
  done

  echo
  ok "Role terpilih: ${SELECTED_ROLES[*]}"
}

# ════════════════════════════════════════════════════════════
#  STEP 2: KONFIGURASI PER-ROLE — Spesifikasi Fleksibel
# ════════════════════════════════════════════════════════════

# Validasi input angka dalam range
_ask_number() {
  local label="$1" default="$2" min="$3" max="$4" unit="$5"
  local val
  while true; do
    printf "  \033[1m%s [default: %s %s] (%s-%s): \033[0m" "$label" "$default" "$unit" "$min" "$max" > /dev/tty
    read -r val < /dev/tty
    val="${val:-$default}"
    if [[ "$val" =~ ^[0-9]+$ ]] && (( val >= min && val <= max )); then
      echo "$val"
      return
    fi
    printf "  \033[0;31mNilai tidak valid. Masukkan angka %s–%s.\033[0m\n" "$min" "$max" > /dev/tty
  done
}

_ask_vm_specs() {
  local role="$1"
  echo
  echo -e "  ${BOLD}Spesifikasi VM — ${ROLE_LABELS[$role]}${RESET}"
  echo -e "  ${DIM}Nilai default: ${DEFAULT_VCPUS} vCPU  |  ${DEFAULT_RAM_GB} GB RAM  |  ${DEFAULT_DISK_GB} GB Disk${RESET}"
  echo

  if ask_yn "  Gunakan spesifikasi default?" "y"; then
    VM_CONFIG["${role}_cpu"]="$DEFAULT_VCPUS"
    VM_CONFIG["${role}_ram_gb"]="$DEFAULT_RAM_GB"
    VM_CONFIG["${role}_ram"]="$(( DEFAULT_RAM_GB * 1024 ))"
    VM_CONFIG["${role}_disk"]="$DEFAULT_DISK_GB"
    info "Menggunakan default: ${DEFAULT_VCPUS} vCPU | ${DEFAULT_RAM_GB} GB RAM | ${DEFAULT_DISK_GB} GB Disk"
  else
    echo
    local cpu ram_gb disk_gb
    cpu=$(_ask_number    "  Jumlah vCPU / Core" "$DEFAULT_VCPUS"   1    64   "core")
    ram_gb=$(_ask_number "  RAM"                "$DEFAULT_RAM_GB"  1   256   "GB")
    disk_gb=$(_ask_number "  Storage"           "$DEFAULT_DISK_GB" 5  2000   "GB")

    VM_CONFIG["${role}_cpu"]="$cpu"
    VM_CONFIG["${role}_ram_gb"]="$ram_gb"
    VM_CONFIG["${role}_ram"]="$(( ram_gb * 1024 ))"
    VM_CONFIG["${role}_disk"]="$disk_gb"
    echo
    ok "Custom spec: ${cpu} vCPU | ${ram_gb} GB RAM | ${disk_gb} GB Disk"
  fi
}

step_configure_roles() {
  section "Langkah 2: Konfigurasi Per-Role"

  for role in "${SELECTED_ROLES[@]}"; do
    echo -e "\n  ${YELLOW}${BOLD}━━━ Konfigurasi: ${ROLE_LABELS[$role]} ━━━${RESET}"

    printf "  \\033[1mNama VM untuk %s [default: vm-%s]: \\033[0m" "${ROLE_LABELS[$role]}" "$role" > /dev/tty
    read -r vname < /dev/tty; vname="${vname:-vm-${role}}"
    VM_CONFIG["${role}_name"]="$vname"

    # Spesifikasi fleksibel (fitur baru)
    _ask_vm_specs "$role"

    printf "  \\033[1mIP Address statis (kosongkan untuk DHCP) [contoh: 192.168.122.10]: \\033[0m" > /dev/tty
    read -r ip < /dev/tty
    VM_CONFIG["${role}_ip"]="${ip:-dhcp}"

    local mode
    mode=$(pick_one "Mode setup VM:" \
      "VM kosong (fresh install)" \
      "VM dengan Docker saja" \
      "VM dengan stack langsung ter-install")
    VM_CONFIG["${role}_mode"]="$mode"

    if [[ "$mode" != "VM kosong (fresh install)" ]]; then
      _select_stack "$role"
    fi

    ok "Konfigurasi ${ROLE_LABELS[$role]} selesai"
  done
}

_select_stack() {
  local role="$1"
  case "$role" in
    fe)
      local tech
      tech=$(pick_one "Pilih teknologi Frontend:" "React" "Vue" "Angular" "Next.js" "Nuxt.js" "Static HTML/Nginx")
      VM_CONFIG["fe_tech"]="$tech"
      if [[ "$tech" != "Static HTML/Nginx" ]]; then
        ask_yn "Gunakan Docker untuk $tech?" && VM_CONFIG["fe_docker"]="true" || VM_CONFIG["fe_docker"]="false"
      fi
      ;;
    be)
      local tech
      tech=$(pick_one "Pilih teknologi Backend:" "Node.js (Express)" "Node.js (NestJS)" "Laravel (PHP)" "Django (Python)" "FastAPI (Python)" "Spring Boot (Java)" "Go (Gin)")
      VM_CONFIG["be_tech"]="$tech"
      ask_yn "Gunakan Docker untuk $tech?" && VM_CONFIG["be_docker"]="true" || VM_CONFIG["be_docker"]="false"
      ;;
    db)
      local tech
      tech=$(pick_one "Pilih Database:" "MySQL 8" "PostgreSQL 16" "MongoDB" "MariaDB" "Redis" "MongoDB + Redis")
      VM_CONFIG["db_tech"]="$tech"
      ask_yn "Gunakan Docker untuk $tech?" && VM_CONFIG["db_docker"]="true" || VM_CONFIG["db_docker"]="false"
      printf "  \\033[1mPassword root/admin DB [default: Admin1234!]: \\033[0m" > /dev/tty
      read -r dbpass < /dev/tty; dbpass="${dbpass:-Admin1234!}"
      VM_CONFIG["db_pass"]="$dbpass"
      ;;
    monitoring)
      local tech
      tech=$(pick_one "Pilih stack Monitoring:" "Wazuh (SIEM)" "Grafana + Prometheus" "Zabbix" "Netdata")
      VM_CONFIG["monitoring_tech"]="$tech"
      ask_yn "Gunakan Docker untuk $tech?" && VM_CONFIG["monitoring_docker"]="true" || VM_CONFIG["monitoring_docker"]="false"
      ;;
    lb)
      local tech
      tech=$(pick_one "Pilih Load Balancer:" "Nginx" "HAProxy" "Traefik" "Caddy")
      VM_CONFIG["lb_tech"]="$tech"
      ask_yn "Gunakan Docker untuk $tech?" && VM_CONFIG["lb_docker"]="true" || VM_CONFIG["lb_docker"]="false"
      ;;
    client)
      local tech
      tech=$(pick_one "Pilih kebutuhan Client/Admin:" "Desktop GUI (xfce4)" "CLI tools only" "Cockpit (Web UI)" "Portainer (Docker UI)")
      VM_CONFIG["client_tech"]="$tech"
      ;;
  esac
}

# ── Step 3: Review & Confirm ─────────────────────────────────
step_review() {
  section "Langkah 3: Review Konfigurasi"
  echo
  echo -e "  ${CYAN}${BOLD}OS Target VM : ${TARGET_OS_LABEL}${RESET}  ${DIM}(${OS_VARIANT} | pkg: $(_guest_pm_label))${RESET}"
  echo -e "  ${DIM}Host OS      : ${HOST_OS} (pkg mgr: ${PKG_MANAGER})${RESET}"
  echo
  printf "  ${BOLD}%-18s %-20s %-6s %-8s %-8s %-12s %-16s${RESET}\n" \
    "Role" "Nama VM" "vCPU" "RAM" "Disk" "IP" "Mode"
  echo "  $(printf '─%.0s' {1..92})"

  for role in "${SELECTED_ROLES[@]}"; do
    local name="${VM_CONFIG[${role}_name]}"
    local cpu="${VM_CONFIG[${role}_cpu]}"
    local ram_gb="${VM_CONFIG[${role}_ram_gb]}"
    local disk="${VM_CONFIG[${role}_disk]}"
    local ip="${VM_CONFIG[${role}_ip]}"
    local mode="${VM_CONFIG[${role}_mode]:-VM kosong}"
    local short_mode; short_mode=$(echo "$mode" | cut -c1-16)
    printf "  %-18s %-20s %-6s %-8s %-8s %-12s %-16s\n" \
      "${ROLE_LABELS[$role]}" "$name" "${cpu}c" "${ram_gb} GB" "${disk} GB" "$ip" "$short_mode"
  done
  echo
  ask_yn "Lanjutkan pembuatan VM?" || { info "Dibatalkan oleh user."; exit 0; }
}

# ── Step 4: Download base image ──────────────────────────────
step_get_base_image() {
  section "Langkah 4: Persiapan Base Image — ${TARGET_OS_LABEL}"
  local img="$BASE_IMAGE_DIR/$BASE_IMAGE_FILE"
  if [[ -f "$img" ]]; then
    ok "Base image sudah ada: $img"
  else
    info "Mengunduh ${TARGET_OS_LABEL} cloud image..."
    info "URL: ${DIM}${BASE_IMAGE_URL}${RESET}"
    wget -q --show-progress -O "$img" "$BASE_IMAGE_URL" \
      || die "Gagal mengunduh base image. Cek koneksi atau URL."
    ok "Base image berhasil diunduh: $img"
  fi
}

# ── Step 5: Build cloud-init & create VMs ───────────────────
step_create_vms() {
  section "Langkah 5: Membuat VM"
  for role in "${SELECTED_ROLES[@]}"; do
    local name="${VM_CONFIG[${role}_name]}"
    echo
    step "Membuat VM: ${BOLD}$name${RESET} (${ROLE_LABELS[$role]}) — ${TARGET_OS_LABEL}"
    _create_single_vm "$role"
    ok "VM '$name' berhasil dibuat dan distart"
    log "VM created: name=$name role=$role os=${TARGET_OS_LABEL} ip=${VM_CONFIG[${role}_ip]} cpu=${VM_CONFIG[${role}_cpu]} ram=${VM_CONFIG[${role}_ram_gb]}GB disk=${VM_CONFIG[${role}_disk]}GB"
  done
}

_create_single_vm() {
  local role="$1"
  local name="${VM_CONFIG[${role}_name]}"
  local ram="${VM_CONFIG[${role}_ram]}"       # MB untuk virt-install
  local cpu="${VM_CONFIG[${role}_cpu]}"
  local disk_gb="${VM_CONFIG[${role}_disk]}"
  local ip="${VM_CONFIG[${role}_ip]}"
  local mode="${VM_CONFIG[${role}_mode]:-VM kosong (fresh install)}"

  local vm_disk="$VM_IMAGE_DIR/${name}.qcow2"
  local ci_dir="$CLOUD_INIT_DIR/$name"
  mkdir -p "$ci_dir"

  # 1. Clone base image
  if [[ -f "$vm_disk" ]]; then
    warn "Disk '$vm_disk' sudah ada, skip clone."
  else
    qemu-img create -f qcow2 -F qcow2 \
      -b "$BASE_IMAGE_DIR/$BASE_IMAGE_FILE" \
      "$vm_disk" "${disk_gb}G" -q
    ok "  Disk image dibuat: $vm_disk (${disk_gb}G)"
  fi

  # 2. Generate cloud-init configs
  _generate_user_data "$role" "$ci_dir"
  _generate_network_config "$role" "$ci_dir"

  # 3. Build cloud-init ISO
  local ci_iso="$VM_IMAGE_DIR/${name}-cloudinit.iso"
  if command -v cloud-localds &>/dev/null; then
    cloud-localds -v "$ci_iso" \
      "$ci_dir/user-data" "$ci_dir/meta-data" \
      --network-config "$ci_dir/network-config" 2>>"$LOG_FILE"
  else
    genisoimage -output "$ci_iso" -volid cidata -joliet -rock \
      "$ci_dir/user-data" "$ci_dir/meta-data" 2>>"$LOG_FILE"
  fi
  ok "  Cloud-init ISO dibuat"

  # 4. virt-install
  if virsh dominfo "$name" &>/dev/null 2>&1; then
    warn "  VM '$name' sudah terdaftar, skip virt-install."
    return
  fi

  virt-install \
    --name "$name" \
    --ram "$ram" \
    --vcpus "$cpu" \
    --disk "path=$vm_disk,format=qcow2" \
    --disk "path=$ci_iso,device=cdrom" \
    --os-variant "$OS_VARIANT" \
    --network "bridge=$BRIDGE_NAME,model=virtio" \
    --graphics none \
    --console "pty,target_type=serial" \
    --noautoconsole \
    --import \
    --boot "hd" \
    >>"$LOG_FILE" 2>&1

  virsh autostart "$name" >>"$LOG_FILE" 2>&1 || true
  ok "  VM diregistrasi ke libvirt dan di-autostart"
}

# ════════════════════════════════════════════════════════════
#  CLOUD-INIT GENERATORS — adaptif per OS target
# ════════════════════════════════════════════════════════════

# Nama paket Docker sesuai OS target
_docker_pkg() {
  case "$TARGET_OS" in
    ubuntu|debian) echo "docker.io docker-compose-plugin" ;;
    arch)          echo "docker docker-compose" ;;
    rhel)          echo "docker-ce docker-ce-cli containerd.io docker-compose-plugin" ;;
    *)             echo "docker.io docker-compose-plugin" ;;
  esac
}

# Default user name per OS (cloud-init convention)
_default_user() {
  case "$TARGET_OS" in
    ubuntu)        echo "ubuntu" ;;
    debian)        echo "debian" ;;
    arch)          echo "arch" ;;
    rhel)          echo "cloud-user" ;;
    *)             echo "ubuntu" ;;
  esac
}

# Paket dasar per OS (disesuaikan nama paket di masing-masing distro)
_base_packages() {
  case "$TARGET_OS" in
    ubuntu|debian|rhel)
      printf "  - qemu-guest-agent\n  - curl\n  - wget\n  - git\n  - htop\n  - net-tools\n  - unzip\n"
      ;;
    arch)
      # net-tools tidak tersedia di Arch → ganti iproute2; qemu-guest-agent tersedia
      printf "  - qemu-guest-agent\n  - curl\n  - wget\n  - git\n  - htop\n  - iproute2\n  - unzip\n"
      ;;
    *)
      printf "  - qemu-guest-agent\n  - curl\n  - wget\n  - git\n  - htop\n  - unzip\n"
      ;;
  esac
}

_generate_user_data() {
  local role="$1" ci_dir="$2"
  local name="${VM_CONFIG[${role}_name]}"
  local mode="${VM_CONFIG[${role}_mode]:-VM kosong (fresh install)}"
  local tech="${VM_CONFIG[${role}_tech]:-}"
  local use_docker="${VM_CONFIG[${role}_docker]:-false}"
  local default_user; default_user=$(_default_user)

  local extra_pkgs="" runcmds=()
  case "$mode" in
    *"Docker saja"*)
      extra_pkgs=$(_docker_pkg)
      runcmds+=("systemctl enable --now docker")
      ;;
    *"stack langsung"*)
      _build_stack_cmds "$role"
      extra_pkgs="${_PKG_LIST:-}"
      IFS='|' read -ra runcmds <<< "${_RUN_CMDS:-}"
      ;;
  esac

  # SSH key dari host
  local ssh_key=""
  if [[ -f /root/.ssh/id_rsa.pub ]]; then
    ssh_key=$(cat /root/.ssh/id_rsa.pub)
  elif [[ -f /home/"${SUDO_USER:-}"/.ssh/id_rsa.pub ]]; then
    ssh_key=$(cat /home/"${SUDO_USER:-}"/.ssh/id_rsa.pub)
  fi

  # meta-data
  cat > "$ci_dir/meta-data" <<EOF
instance-id: $name-$(date +%s)
local-hostname: $name
EOF

  # Build YAML lists
  local base_pkgs; base_pkgs=$(_base_packages)
  local extra_pkg_yaml="" runcmd_yaml="" arch_sync=""

  if [[ -n "$extra_pkgs" ]]; then
    for p in $extra_pkgs; do
      extra_pkg_yaml+="  - $p"$'\n'
    done
  fi

  for cmd in "${runcmds[@]}"; do
    [[ -n "$cmd" ]] && runcmd_yaml+="  - $cmd"$'\n'
  done

  # Arch Linux: sync package DB dulu sebelum install
  [[ "$TARGET_OS" == "arch" ]] && arch_sync="  - pacman -Syu --noconfirm"$'\n'

  # Tulis user-data
  cat > "$ci_dir/user-data" <<YAML
#cloud-config
hostname: $name
fqdn: $name.local
manage_etc_hosts: true

users:
  - name: $default_user
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    groups: [sudo, adm$([ "$use_docker" = "true" ] && echo ", docker")]
    lock_passwd: false
    passwd: \$6\$rounds=4096\$saltsalt\$$(echo "ubuntu" | openssl passwd -6 -stdin 2>/dev/null || echo '$6$abc$xyz')
$([ -n "$ssh_key" ] && printf "    ssh_authorized_keys:\n      - %s\n" "$ssh_key")

package_update: true
package_upgrade: false
packages:
$base_pkgs
$extra_pkg_yaml
runcmd:
$arch_sync  - systemctl enable --now qemu-guest-agent
$runcmd_yaml  - echo "VM $name setup completed at \$(date)" >> /var/log/cloud-init-custom.log

final_message: |
  VM $name ($role) siap digunakan!
  OS    : $TARGET_OS_LABEL
  User  : $default_user
  Mode  : $mode
  Stack : ${tech:-minimal}
YAML
}

_PKG_LIST=""
_RUN_CMDS=""

_build_stack_cmds() {
  local role="$1"
  local tech="${VM_CONFIG[${role}_tech]:-}"
  local use_docker="${VM_CONFIG[${role}_docker]:-false}"
  _PKG_LIST=""; _RUN_CMDS=""
  local dpkg; dpkg=$(_docker_pkg)

  case "$role" in
    fe)
      if [[ "$use_docker" == "true" ]]; then
        _PKG_LIST="$dpkg nginx"; _RUN_CMDS="systemctl enable --now docker|systemctl enable --now nginx"
      else
        case "$tech" in
          React*|Vue*|Angular*|"Next.js"*|"Nuxt.js"*)
            _PKG_LIST="nodejs npm"; _RUN_CMDS="npm install -g n|n lts" ;;
          "Static HTML/Nginx")
            _PKG_LIST="nginx"; _RUN_CMDS="systemctl enable --now nginx" ;;
        esac
      fi ;;
    be)
      if [[ "$use_docker" == "true" ]]; then
        _PKG_LIST="$dpkg"; _RUN_CMDS="systemctl enable --now docker"
      else
        case "$tech" in
          "Node.js"*)
            _PKG_LIST="nodejs npm"; _RUN_CMDS="npm install -g pm2" ;;
          "Laravel"*)
            case "$TARGET_OS" in
              arch) _PKG_LIST="php composer nginx" ;;
              rhel) _PKG_LIST="php php-fpm php-mbstring php-xml php-curl composer nginx" ;;
              *)    _PKG_LIST="php8.1 php8.1-fpm php8.1-mbstring php8.1-xml php8.1-curl composer nginx" ;;
            esac
            _RUN_CMDS="systemctl enable --now php-fpm|systemctl enable --now nginx" ;;
          "Django"*|"FastAPI"*)
            case "$TARGET_OS" in
              arch) _PKG_LIST="python python-pip" ;;
              *)    _PKG_LIST="python3 python3-pip python3-venv" ;;
            esac
            _RUN_CMDS="pip3 install uvicorn gunicorn" ;;
          "Spring Boot"*)
            case "$TARGET_OS" in
              arch) _PKG_LIST="jdk-openjdk maven" ;;
              rhel) _PKG_LIST="java-17-openjdk-devel maven" ;;
              *)    _PKG_LIST="openjdk-17-jdk maven" ;;
            esac ;;
          "Go"*)
            _PKG_LIST="go" ;;
        esac
      fi ;;
    db)
      local dbpass="${VM_CONFIG[db_pass]:-Admin1234!}"
      if [[ "$use_docker" == "true" ]]; then
        _PKG_LIST="$dpkg"; _RUN_CMDS="systemctl enable --now docker"
      else
        case "$tech" in
          "MySQL 8")
            case "$TARGET_OS" in
              arch) _PKG_LIST="mysql" ;;
              *)    _PKG_LIST="mysql-server" ;;
            esac
            _RUN_CMDS="systemctl enable --now mysql|mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '$dbpass'; FLUSH PRIVILEGES;\"" ;;
          "PostgreSQL 16")
            case "$TARGET_OS" in
              arch) _PKG_LIST="postgresql" ;;
              rhel) _PKG_LIST="postgresql-server postgresql-contrib" ;;
              *)    _PKG_LIST="postgresql postgresql-contrib" ;;
            esac
            _RUN_CMDS="systemctl enable --now postgresql|sudo -u postgres psql -c \"ALTER USER postgres PASSWORD '$dbpass';\"" ;;
          "MongoDB")
            case "$TARGET_OS" in
              arch)
                _PKG_LIST="mongodb-bin"
                _RUN_CMDS="systemctl enable --now mongodb" ;;
              rhel)
                _RUN_CMDS="echo '[mongodb-org-7.0]
baseurl=https://repo.mongodb.org/yum/redhat/9/mongodb-org/7.0/x86_64/
gpgcheck=0
enabled=1' > /etc/yum.repos.d/mongodb-org.repo|dnf install -y mongodb-org|systemctl enable --now mongod" ;;
              *)
                _PKG_LIST="gnupg"
                _RUN_CMDS="curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | gpg -o /usr/share/keyrings/mongodb-server-7.0.gpg --dearmor|echo 'deb [ arch=amd64 signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu jammy/mongodb-org/7.0 multiverse' > /etc/apt/sources.list.d/mongodb-org-7.0.list|apt-get update -qq|apt-get install -y mongodb-org|systemctl enable --now mongod" ;;
            esac ;;
          "MariaDB")
            _PKG_LIST="mariadb"
            case "$TARGET_OS" in
              arch) _RUN_CMDS="systemctl enable --now mariadb|mariadb-install-db --user=mysql --basedir=/usr --datadir=/var/lib/mysql|mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '$dbpass'; FLUSH PRIVILEGES;\"" ;;
              *)    _RUN_CMDS="systemctl enable --now mariadb|mysql -e \"ALTER USER 'root'@'localhost' IDENTIFIED BY '$dbpass'; FLUSH PRIVILEGES;\"" ;;
            esac ;;
          "Redis")
            _PKG_LIST="redis"; _RUN_CMDS="systemctl enable --now redis" ;;
        esac
      fi ;;
    monitoring)
      if [[ "$use_docker" == "true" ]]; then
        _PKG_LIST="$dpkg"; _RUN_CMDS="systemctl enable --now docker"
      else
        case "$tech" in
          "Wazuh (SIEM)")
            _PKG_LIST="curl"
            _RUN_CMDS="curl -s https://packages.wazuh.com/key/GPG-KEY-WAZUH | gpg --no-default-keyring --keyring gnupg-ring:/usr/share/keyrings/wazuh.gpg --import|chmod 644 /usr/share/keyrings/wazuh.gpg" ;;
          "Grafana + Prometheus")
            _PKG_LIST="prometheus grafana"
            _RUN_CMDS="systemctl enable --now prometheus|systemctl enable --now grafana-server" ;;
          "Netdata")
            _RUN_CMDS="bash <(curl -Ss https://my-netdata.io/kickstart.sh) --dont-wait" ;;
        esac
      fi ;;
    lb)
      if [[ "$use_docker" == "true" ]]; then
        _PKG_LIST="$dpkg"; _RUN_CMDS="systemctl enable --now docker"
      else
        case "$tech" in
          "Nginx")  _PKG_LIST="nginx";   _RUN_CMDS="systemctl enable --now nginx" ;;
          "HAProxy") _PKG_LIST="haproxy"; _RUN_CMDS="systemctl enable --now haproxy" ;;
          "Caddy")
            case "$TARGET_OS" in
              arch) _PKG_LIST="caddy"; _RUN_CMDS="systemctl enable --now caddy" ;;
              rhel) _RUN_CMDS="dnf install -y 'dnf-command(copr)'|dnf copr enable -y @caddy/caddy|dnf install -y caddy|systemctl enable --now caddy" ;;
              *)
                _PKG_LIST="debian-keyring debian-archive-keyring apt-transport-https curl"
                _RUN_CMDS="curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg|apt-get update -qq && apt-get install -y caddy|systemctl enable --now caddy" ;;
            esac ;;
        esac
      fi ;;
    client)
      case "${VM_CONFIG[client_tech]:-}" in
        "Desktop GUI"*)
          case "$TARGET_OS" in
            arch) _PKG_LIST="xfce4 xfce4-terminal tigervnc" ;;
            rhel) _PKG_LIST="@xfce-desktop tigervnc-server" ;;
            *)    _PKG_LIST="xfce4 xfce4-terminal tightvncserver" ;;
          esac ;;
        "Cockpit"*)
          _PKG_LIST="cockpit"; _RUN_CMDS="systemctl enable --now cockpit.socket" ;;
        "Portainer"*)
          _PKG_LIST="$dpkg"
          _RUN_CMDS="systemctl enable --now docker|docker volume create portainer_data|docker run -d -p 9000:9000 --name portainer --restart always -v /var/run/docker.sock:/var/run/docker.sock -v portainer_data:/data portainer/portainer-ce" ;;
      esac ;;
  esac
}

_generate_network_config() {
  local role="$1" ci_dir="$2"
  local ip="${VM_CONFIG[${role}_ip]:-dhcp}"

  if [[ "$ip" == "dhcp" ]]; then
    cat > "$ci_dir/network-config" <<EOF
version: 2
ethernets:
  enp1s0:
    dhcp4: true
EOF
  else
    local gw; gw=$(echo "$ip" | sed 's/\.[0-9]*$/.1/')
    cat > "$ci_dir/network-config" <<EOF
version: 2
ethernets:
  enp1s0:
    dhcp4: false
    addresses:
      - ${ip}/24
    gateway4: ${gw}
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
EOF
  fi
}

# ── Step 6: Summary ──────────────────────────────────────────
step_summary() {
  section "Langkah 6: Ringkasan Hasil"
  echo
  ok "Semua VM berhasil dibuat!"
  echo
  echo -e "  ${CYAN}${BOLD}OS Guest: ${TARGET_OS_LABEL}${RESET}  ${DIM}(user default: $(_default_user))${RESET}"
  echo
  printf "  ${BOLD}%-22s %-16s %-6s %-7s %-8s %-12s %-18s${RESET}\n" \
    "VM Name" "Role" "vCPU" "RAM" "Disk" "IP" "Tech Stack"
  echo "  $(printf '─%.0s' {1..89})"
  for role in "${SELECTED_ROLES[@]}"; do
    printf "  %-22s %-16s %-6s %-7s %-8s %-12s %-18s\n" \
      "${VM_CONFIG[${role}_name]}" \
      "${ROLE_LABELS[$role]}" \
      "${VM_CONFIG[${role}_cpu]}c" \
      "${VM_CONFIG[${role}_ram_gb]} GB" \
      "${VM_CONFIG[${role}_disk]} GB" \
      "${VM_CONFIG[${role}_ip]}" \
      "${VM_CONFIG[${role}_tech]:-minimal}"
  done

  echo
  info "Akses VM:"
  info "  Lihat status     : ${CYAN}virsh list --all${RESET}"
  info "  Console SSH      : ${CYAN}ssh $(_default_user)@<IP_VM>${RESET}  (pass: ubuntu)"
  info "  Log provisioning : ${CYAN}$LOG_FILE${RESET}"
  info "  Cloud-init dir   : ${CYAN}$CLOUD_INIT_DIR/${RESET}"
  echo
}

# ── Main ─────────────────────────────────────────────────────
main() {
  require_root
  banner
  echo

  step_detect_and_select_os  # Step 0: deteksi host OS + pilih OS target
  check_deps                 # install deps via PKG_MANAGER yang sesuai
  step_select_roles          # Step 1
  step_configure_roles       # Step 2: nama, spec fleksibel, IP, mode, stack
  step_review                # Step 3
  step_get_base_image        # Step 4: download image sesuai OS target
  step_create_vms            # Step 5
  step_summary               # Step 6
}

main "$@"
