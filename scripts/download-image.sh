#!/bin/bash
set -Eeuo pipefail

BASE="/opt/pi-recovery"
IMAGE="$BASE/images/raspios-lite-arm64.img.xz"
SHA_FILE="$BASE/backup/system/image.sha256"
URL="https://downloads.raspberrypi.com/raspios_lite_arm64_latest"
EXPECTED_SHA=""
LOCAL_FILE=""

usage() {
    cat <<'EOF'
Usage:
  sudo ./scripts/download-image.sh --sha256 SHA256
  sudo ./scripts/download-image.sh --file IMAGE.img.xz --sha256 SHA256
  sudo ./scripts/download-image.sh --url URL --sha256 SHA256

Le SHA-256 doit être obtenu depuis une source officielle Raspberry Pi.
EOF
}

fail() {
    printf '[FAIL] %s\n' "$1" >&2
    exit 1
}

ok() {
    printf '[ OK ] %s\n' "$1"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sha256)
            EXPECTED_SHA="${2:-}"
            shift 2
            ;;
        --file)
            LOCAL_FILE="${2:-}"
            shift 2
            ;;
        --url)
            URL="${2:-}"
            shift 2
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
[[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] \
    || fail "SHA-256 valide obligatoire (--sha256)."

EXPECTED_SHA="${EXPECTED_SHA,,}"

mkdir -p "$BASE/images" "$BASE/backup/system"

TMP="${IMAGE}.tmp"
rm -f "$TMP"

if [[ -n "$LOCAL_FILE" ]]; then
    [[ -s "$LOCAL_FILE" ]] || fail "Image locale introuvable : $LOCAL_FILE"
    cp "$LOCAL_FILE" "$TMP"
else
    command -v curl >/dev/null 2>&1 || {
        apt-get update
        apt-get install -y curl ca-certificates
    }

    echo "Téléchargement : $URL"
    curl -fL --retry 3 --progress-bar "$URL" -o "$TMP"
fi

xz -t "$TMP" || {
    rm -f "$TMP"
    fail "Archive XZ invalide."
}

ACTUAL_SHA="$(sha256sum "$TMP" | awk '{print $1}')"

if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
    rm -f "$TMP"
    fail "SHA-256 incorrect. Attendu: $EXPECTED_SHA / obtenu: $ACTUAL_SHA"
fi

mv "$TMP" "$IMAGE"
printf '%s\n' "$EXPECTED_SHA" > "$SHA_FILE"

chmod 644 "$IMAGE" "$SHA_FILE"
sync

ok "Image installée : $IMAGE"
ok "SHA-256 : $EXPECTED_SHA"
