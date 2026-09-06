#!/bin/bash
set -Eeuo pipefail

INSTALL_PATH="/usr/local/sbin/recovery"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/scripts/recovery"

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

ok() {
    printf '[ OK ] %s\n' "$1"
}

[[ "$EUID" -eq 0 ]] || fail "Lance ce script avec sudo."
[[ -f "$SOURCE" ]] || fail "Script recovery introuvable : $SOURCE"

MODEL="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
[[ "$MODEL" == *"Raspberry Pi 5"* ]] || fail "Ce projet est prévu pour Raspberry Pi 5."

ROOT_DEVICE="$(findmnt -no SOURCE /)"
ROOT_DISK="$(lsblk -no PKNAME "$ROOT_DEVICE" 2>/dev/null | head -n1 || true)"

[[ "$ROOT_DISK" == nvme* ]] \
    || fail "Le système principal ne semble pas tourner sur un NVMe : $ROOT_DEVICE"

command -v vcmailbox >/dev/null 2>&1 \
    || fail "vcmailbox est absent."

install -o root -g root -m 750 "$SOURCE" "$INSTALL_PATH"

ok "Commande installée : $INSTALL_PATH"

BOOT_ORDER="$(
    rpi-eeprom-config 2>/dev/null |
    awk -F= '$1=="BOOT_ORDER"{print $2}' |
    tail -n1
)"

if [[ "$BOOT_ORDER" == "0xf416" ]]; then
    ok "BOOT_ORDER : 0xf416"
else
    printf '[WARN] BOOT_ORDER actuel : %s\n' "${BOOT_ORDER:-inconnu}"
    printf '[WARN] Ce projet a été testé avec BOOT_ORDER=0xf416.\n'
fi

echo
echo "Test sans reboot :"
echo "  sudo recovery --check"
echo
echo "Passage au Recovery :"
echo "  sudo recovery"
