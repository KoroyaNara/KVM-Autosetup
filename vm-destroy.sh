#!/usr/bin/env bash
# ============================================================
#  KVM AutoSetup — VM Cleanup Tool
#  Usage: sudo bash vm-destroy.sh [vm_name | --all]
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

VM_IMAGE_DIR="/var/lib/libvirt/images/vms"
CLOUD_INIT_DIR="$(dirname "$0")/cloud-init"

[[ $EUID -eq 0 ]] || { echo "Run as root"; exit 1; }

destroy_vm() {
  local name="$1"
  echo -e "\n${YELLOW}→ Destroying: ${BOLD}$name${RESET}"

  # Stop if running
  if virsh domstate "$name" 2>/dev/null | grep -q "running"; then
    virsh destroy "$name" 2>/dev/null && echo "  Stopped" || true
  fi

  # Undefine with snapshots/storage
  virsh undefine "$name" --remove-all-storage --snapshots-metadata 2>/dev/null || \
    virsh undefine "$name" 2>/dev/null || true

  # Remove disk images manually
  rm -f "$VM_IMAGE_DIR/${name}.qcow2"
  rm -f "$VM_IMAGE_DIR/${name}-cloudinit.iso"
  rm -rf "$CLOUD_INIT_DIR/$name"

  echo -e "  ${GREEN}✔ $name removed${RESET}"
}

if [[ "${1:-}" == "--all" ]]; then
  echo -e "${RED}${BOLD}WARNING: Ini akan menghapus SEMUA VM!${RESET}"
  read -rp "Ketik 'yes' untuk konfirmasi: " confirm
  [[ "$confirm" == "yes" ]] || { echo "Dibatalkan."; exit 0; }
  while IFS= read -r vm; do
    [[ -n "$vm" ]] && destroy_vm "$vm"
  done < <(virsh list --all --name 2>/dev/null | grep -v '^$')
elif [[ -n "${1:-}" ]]; then
  destroy_vm "$1"
else
  echo "Usage: $0 <vm_name>   — hapus satu VM"
  echo "       $0 --all       — hapus semua VM (konfirmasi diperlukan)"
  echo
  echo "VM yang tersedia:"
  virsh list --all --name 2>/dev/null | grep -v '^$' | sed 's/^/  /'
fi
