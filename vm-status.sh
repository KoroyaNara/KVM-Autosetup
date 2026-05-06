#!/usr/bin/env bash
# ============================================================
#  KVM AutoSetup — VM Inventory & Status Tool
#  Usage: sudo bash vm-status.sh [--json]
# ============================================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; RESET='\033[0m'

JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

get_vm_ip() {
  local name="$1"
  # Try qemu-guest-agent first
  local ip
  ip=$(virsh domifaddr "$name" --source agent 2>/dev/null \
    | awk '/ipv4/{print $4}' | cut -d'/' -f1 | head -1)
  [[ -z "$ip" ]] && ip=$(virsh domifaddr "$name" 2>/dev/null \
    | awk '/ipv4/{print $4}' | cut -d'/' -f1 | head -1)
  echo "${ip:--}"
}

get_vm_info() {
  local name="$1"
  local state; state=$(virsh domstate "$name" 2>/dev/null | tr -d '[:space:]')
  local info; info=$(virsh dominfo "$name" 2>/dev/null)
  local ram;  ram=$(echo "$info"  | awk '/Max memory/{print $3}')
  local cpu;  cpu=$(echo "$info"  | awk '/CPU\(s\)/{print $2}')
  local ip;   ip=$(get_vm_ip "$name")
  echo "$state|$ram|$cpu|$ip"
}

if $JSON_MODE; then
  echo "{"
  echo "  \"vms\": ["
  first=true
  while IFS= read -r name; do
    IFS='|' read -r state ram cpu ip <<< "$(get_vm_info "$name")"
    $first || echo ","
    printf '    {"name":"%s","state":"%s","ram_kb":%s,"vcpus":%s,"ip":"%s"}' \
      "$name" "$state" "${ram:-0}" "${cpu:-0}" "$ip"
    first=false
  done < <(virsh list --all --name 2>/dev/null | grep -v '^$')
  echo ""
  echo "  ]"
  echo "}"
  exit 0
fi

# Pretty table
echo
echo -e "${CYAN}${BOLD}  KVM VM Inventory${RESET}"
echo -e "${DIM}  Generated: $(date '+%F %T')${RESET}"
echo
printf "  ${BOLD}%-24s %-12s %-10s %-6s %-16s${RESET}\n" \
  "VM Name" "State" "RAM (MB)" "vCPU" "IP Address"
echo "  $(printf '─%.0s' {1..68})"

while IFS= read -r name; do
  [[ -z "$name" ]] && continue
  IFS='|' read -r state ram cpu ip <<< "$(get_vm_info "$name")"
  local_ram=$(( ${ram:-0} / 1024 ))
  case "$state" in
    running) color="$GREEN" ;;
    shut*|off) color="$RED" ;;
    *) color="$YELLOW" ;;
  esac
  printf "  %-24s ${color}%-12s${RESET} %-10s %-6s %-16s\n" \
    "$name" "$state" "${local_ram}M" "${cpu:-?}" "${ip:--}"
done < <(virsh list --all --name 2>/dev/null | grep -v '^$')

echo
echo -e "  ${DIM}Quick commands:${RESET}"
echo -e "  ${DIM}Start VM  : virsh start <name>${RESET}"
echo -e "  ${DIM}Stop VM   : virsh shutdown <name>${RESET}"
echo -e "  ${DIM}Console   : virsh console <name>${RESET}"
echo -e "  ${DIM}SSH       : ssh ubuntu@<IP> (pass: ubuntu)${RESET}"
echo
