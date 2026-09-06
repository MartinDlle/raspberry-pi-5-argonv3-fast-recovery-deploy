#!/bin/bash
set -Eeuo pipefail

BASE="/opt/pi-recovery"
BACKUP="$BASE/backup"
IMAGES="$BASE/images"
SCRIPTS="$BASE/scripts"
TARGET="/dev/nvme0n1"
SOURCE_USER=""
SKIP_ARGON=0

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

usage() {
    cat <<'EOF'
Usage:
  sudo ./install-recovery.sh --source-user USER [--skip-argon]

Exemple:
  sudo ./install-recovery.sh --source-user martin
EOF
}

ok() {
    printf '[ OK ] %s\n' "$1"
}

warn() {
    printf '[WARN] %s\n' "$1"
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source-user)
            SOURCE_USER="${2:-}"
            shift 2
            ;;
        --skip-argon)
            SKIP_ARGON=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "Argument inconnu : $1"
            ;;
    esac
done

[[ "$EUID" -eq 0 ]] || fail "Lance ce script avec sudo."
[[ "$SOURCE_USER" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] \
    || fail "Utilisateur source invalide ou absent. Utilise --source-user."

MODEL_PI="$(tr -d '\0' </proc/device-tree/model 2>/dev/null || true)"
[[ "$MODEL_PI" == *"Raspberry Pi 5"* ]] || fail "Raspberry Pi 5 requis."

ROOT_DEVICE="$(findmnt -no SOURCE /)"
ROOT_DISK="$(lsblk -no PKNAME "$ROOT_DEVICE" 2>/dev/null | head -n1 || true)"
[[ "$ROOT_DISK" == "mmcblk0" ]] \
    || fail "Ce script doit être lancé depuis la microSD Recovery. Racine : $ROOT_DEVICE"

[[ -b "$TARGET" ]] || fail "$TARGET introuvable."
[[ -b "${TARGET}p2" ]] || fail "${TARGET}p2 introuvable."

[[ -s "$IMAGES/raspios-lite-arm64.img.xz" ]] \
    || fail "Image absente. Lance d'abord scripts/download-image.sh."
[[ -s "$BACKUP/system/image.sha256" ]] \
    || fail "SHA-256 absent. Lance d'abord scripts/download-image.sh."

EXPECTED_SHA="$(tr -d '[:space:]' < "$BACKUP/system/image.sha256")"
echo "$EXPECTED_SHA  $IMAGES/raspios-lite-arm64.img.xz" | sha256sum -c - >/dev/null \
    || fail "Le SHA-256 de l'image n'est pas valide."
ok "Image Raspberry Pi OS vérifiée"

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y \
    curl ca-certificates xz-utils rsync parted gdisk \
    python3-yaml e2fsprogs util-linux

mkdir -p \
    "$BACKUP/ssh/hostkeys" \
    "$BACKUP/user" \
    "$BACKUP/system" \
    "$BACKUP/argon" \
    "$IMAGES" \
    "$SCRIPTS"

chmod 700 "$BACKUP"

install -o root -g root -m 750 \
    "$SCRIPT_DIR/scripts/reset-pi" \
    /usr/local/sbin/reset-pi

install -o root -g root -m 750 \
    "$SCRIPT_DIR/scripts/reset-pi" \
    "$SCRIPTS/reset-pi"

install -o root -g root -m 750 \
    "$SCRIPT_DIR/scripts/recovery" \
    "$SCRIPTS/recovery"

# Télécharger une copie locale du script Argon officiel.
curl -fsSL https://download.argon40.com/argon1.sh \
    -o "$SCRIPTS/argon1.sh"
chmod 700 "$SCRIPTS/argon1.sh"

if (( SKIP_ARGON == 0 )); then
    echo
    echo "Installation Argon ONE V3 sur le Recovery..."
    mkdir -p /lib/systemd/system-shutdown
    bash "$SCRIPTS/argon1.sh"
    systemctl daemon-reload || true
    systemctl enable argononed.service 2>/dev/null || true
    systemctl restart argononed.service 2>/dev/null || true

    if systemctl is-active --quiet argononed.service; then
        ok "argononed.service actif"
    else
        warn "argononed.service n'est pas actif. Vérifie l'installation Argon."
    fi
fi

MOUNTPOINT="/mnt/pi-recovery-source"
mkdir -p "$MOUNTPOINT"

cleanup() {
    mountpoint -q "$MOUNTPOINT" && umount "$MOUNTPOINT" || true
}
trap cleanup EXIT

# Enlever d'éventuels montages précédents de la partition source.
while findmnt -rn -S "${TARGET}p2" >/dev/null 2>&1; do
    MP="$(findmnt -rn -S "${TARGET}p2" -o TARGET | head -n1)"
    umount "$MP"
done

mount -o ro "${TARGET}p2" "$MOUNTPOINT"

[[ -d "$MOUNTPOINT/home/$SOURCE_USER" ]] \
    || fail "Utilisateur $SOURCE_USER introuvable sur le NVMe."

[[ -s "$MOUNTPOINT/home/$SOURCE_USER/.ssh/authorized_keys" ]] \
    || fail "authorized_keys absent pour $SOURCE_USER."

cp -a \
    "$MOUNTPOINT/home/$SOURCE_USER/.ssh/authorized_keys" \
    "$BACKUP/ssh/authorized_keys"

rm -rf "$BACKUP/ssh/hostkeys"
mkdir -p "$BACKUP/ssh/hostkeys"
cp -a "$MOUNTPOINT/etc/ssh/ssh_host_"* "$BACKUP/ssh/hostkeys/"

awk -F: -v u="$SOURCE_USER" '$1==u{print $2}' \
    "$MOUNTPOINT/etc/shadow" > "$BACKUP/user/user.passwd-hash"

awk -F: -v u="$SOURCE_USER" '$1==u{print $3 ":" $4}' \
    "$MOUNTPOINT/etc/passwd" > "$BACKUP/user/user.uidgid"

printf '%s\n' "$SOURCE_USER" > "$BACKUP/system/default_username"

cp "$MOUNTPOINT/etc/hostname" "$BACKUP/system/hostname"

if [[ -s "$MOUNTPOINT/etc/timezone" ]]; then
    cp "$MOUNTPOINT/etc/timezone" "$BACKUP/system/timezone"
else
    printf 'Europe/Paris\n' > "$BACKUP/system/timezone"
    warn "Timezone source absente : Europe/Paris utilisée par défaut."
fi

NVME_MODEL="$(lsblk -dn -o MODEL "$TARGET" | xargs)"
NVME_SERIAL="$(lsblk -dn -o SERIAL "$TARGET" | xargs)"
NVME_SIZE="$(lsblk -bdn -o SIZE "$TARGET" | xargs)"

[[ -n "$NVME_MODEL" ]] || fail "Impossible de lire le modèle NVMe."
[[ -n "$NVME_SERIAL" ]] || fail "Impossible de lire le numéro de série NVMe."
[[ "$NVME_SIZE" =~ ^[0-9]+$ ]] || fail "Taille NVMe invalide."

printf '%s\n' "$NVME_MODEL" > "$BACKUP/system/nvme.model"
printf '%s\n' "$NVME_SERIAL" > "$BACKUP/system/nvme.serial"
printf '%s\n' "$NVME_SIZE" > "$BACKUP/system/nvme.size_bytes"

if [[ -s "$MOUNTPOINT/etc/argononed.conf" ]]; then
    cp "$MOUNTPOINT/etc/argononed.conf" "$BACKUP/argon/argononed.conf"
elif [[ -s /etc/argononed.conf ]]; then
    cp /etc/argononed.conf "$BACKUP/argon/argononed.conf"
    warn "Configuration Argon du NVMe absente : configuration du Recovery utilisée."
else
    printf '55=10\n60=55\n65=100\n' > "$BACKUP/argon/argononed.conf"
    warn "Aucune configuration Argon trouvée : configuration minimale créée."
fi

chmod -R go-rwx "$BACKUP"
chmod 644 "$BACKUP/system/"{hostname,timezone,default_username,nvme.model,nvme.size_bytes,image.sha256}
chmod 600 "$BACKUP/system/nvme.serial" "$BACKUP/user/"*
chmod 600 "$BACKUP/argon/argononed.conf"

sync

ok "Coffre Recovery créé"
ok "NVMe mémorisé : $NVME_MODEL"
ok "Utilisateur source : $SOURCE_USER"
ok "Hostname : $(tr -d '[:space:]' < "$BACKUP/system/hostname")"

echo
echo "Vérifie maintenant :"
echo "  sudo reset-pi --check"
