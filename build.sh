#!/usr/bin/env bash
# Prepare a bootable Debian USB drive for ZyXEL NSA320/Kirkwood devices.

set -euo pipefail

SERVER="${SERVER:-192.168.1.20}"
REMOTE_USER="${REMOTE_USER:-root}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/server}"
WORKDIR="${WORKDIR:-$HOME/debian-nsa}"
ROOTFS_URL="${ROOTFS_URL:-https://www.dropbox.com/scl/fi/ckm7zamfvyw0aa1utyo3y/Debian-5.6.7-kirkwood-tld-1-rootfs-bodhi.tar.bz2?rlkey=5a7rc973197it5vj0cjo36t9j&dl=1}"
UBOOT_URL="${UBOOT_URL:-}"
ROOTFS_FILE="${ROOTFS_FILE:-$WORKDIR/rootfs.tar.bz2}"
UBOOT_FILE="${UBOOT_FILE:-$WORKDIR/u-boot.kwb}"
DEVICE=""
ASSUME_YES=0
WRITE_UBOOT=0

usage() {
	cat <<'EOF'
Použití:
  ./build.sh --device /dev/sdX [volby]

Povinné:
  --device PATH       Cílový USB disk na vzdáleném serveru (např. /dev/sdb)

Volby:
  --server HOST       SSH server (výchozí: $SERVER)
  --user USER         SSH uživatel (výchozí: $REMOTE_USER)
  --ssh-key PATH      SSH privátní klíč (výchozí: $SSH_KEY)
  --workdir PATH      Pracovní adresář (výchozí: $WORKDIR)
  --rootfs PATH       Lokální rootfs archiv
  --uboot PATH        Lokální U-Boot obraz
  --yes               Přeskočit potvrzení smazání cílového disku
  --write-uboot       Zapsat dodaný U-Boot do sektoru 1 cílového disku
  -h, --help          Zobrazit tuto nápovědu

URL pro stažení lze změnit přes ROOTFS_URL a UBOOT_URL. Existující lokální
soubory se znovu nestahují.
EOF
}

die() {
	printf 'Chyba: %s\n' "$*" >&2
	exit 1
}

require_command() {
	command -v "$1" >/dev/null 2>&1 || die "Chybí příkaz '$1'."
}

while [[ $# -gt 0 ]]; do
	case "$1" in
		--device)
			[[ $# -ge 2 ]] || die "--device vyžaduje cestu."
			DEVICE="$2"
			shift 2
			;;
		--server)
			[[ $# -ge 2 ]] || die "--server vyžaduje hodnotu."
			SERVER="$2"
			shift 2
			;;
		--user)
			[[ $# -ge 2 ]] || die "--user vyžaduje hodnotu."
			REMOTE_USER="$2"
			shift 2
			;;
		--ssh-key)
			[[ $# -ge 2 ]] || die "--ssh-key vyžaduje cestu."
			SSH_KEY="$2"
			shift 2
			;;
		--workdir)
			[[ $# -ge 2 ]] || die "--workdir vyžaduje cestu."
			WORKDIR="$2"
			ROOTFS_FILE="$WORKDIR/rootfs.tar.bz2"
			UBOOT_FILE="$WORKDIR/u-boot.kwb"
			shift 2
			;;
		--rootfs)
			[[ $# -ge 2 ]] || die "--rootfs vyžaduje cestu."
			ROOTFS_FILE="$2"
			shift 2
			;;
		--uboot)
			[[ $# -ge 2 ]] || die "--uboot vyžaduje cestu."
			UBOOT_FILE="$2"
			shift 2
			;;
		--yes)
			ASSUME_YES=1
			shift
			;;
		--write-uboot)
			WRITE_UBOOT=1
			shift
			;;
		-h|--help)
			usage
			exit 0
			;;
		*)
			die "Neznámý argument '$1'. Použijte --help."
			;;
	esac
done

[[ -n "$DEVICE" ]] || die "Musíte zadat --device. Automatický výběr disku je z bezpečnostních důvodů zakázán."
[[ "$DEVICE" == /dev/* ]] || die "Cílové zařízení musí být absolutní cesta začínající /dev/."
[[ -f "$SSH_KEY" ]] || die "SSH klíč neexistuje: $SSH_KEY"
[[ -r "$SSH_KEY" ]] || die "SSH klíč nelze číst: $SSH_KEY"

for command in ssh scp wget tar; do
	require_command "$command"
done

mkdir -p "$WORKDIR"
if [[ ! -f "$ROOTFS_FILE" ]]; then
	[[ -n "$ROOTFS_URL" ]] || die "Rootfs chybí. Zadejte --rootfs nebo ROOTFS_URL."
	printf '>>> Stahuji Debian rootfs...\n'
	wget -c "$ROOTFS_URL" -O "$ROOTFS_FILE"
fi
if [[ ! -f "$UBOOT_FILE" ]]; then
	[[ "$WRITE_UBOOT" == 0 ]] || [[ -n "$UBOOT_URL" ]] || die "U-Boot chybí. Zadejte --uboot nebo UBOOT_URL."
	[[ "$WRITE_UBOOT" == 0 ]] || {
		printf '>>> Stahuji U-Boot...\n'
		wget -c "$UBOOT_URL" -O "$UBOOT_FILE"
	}
fi
[[ -s "$ROOTFS_FILE" ]] || die "Rootfs archiv je prázdný."
if [[ "$WRITE_UBOOT" == 1 ]]; then
	[[ -s "$UBOOT_FILE" ]] || die "U-Boot obraz je prázdný."
fi
tar -tjf "$ROOTFS_FILE" >/dev/null || die "Rootfs archiv není platný tar.bz2: $ROOTFS_FILE"

SSH_OPTS=(-i "$SSH_KEY" -o ConnectTimeout=5 -o BatchMode=yes)
printf '>>> Ověřuji SSH připojení k %s@%s...\n' "$REMOTE_USER" "$SERVER"
ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$SERVER" true

printf '>>> Nahrávám obrazy na server...\n'
scp "${SSH_OPTS[@]}" "$ROOTFS_FILE" \
	"$REMOTE_USER@$SERVER:/tmp/zyxel-rootfs.tar.bz2"
if [[ "$WRITE_UBOOT" == 1 ]]; then
	scp "${SSH_OPTS[@]}" "$UBOOT_FILE" \
		"$REMOTE_USER@$SERVER:/tmp/zyxel-uboot.kwb"
fi

printf '>>> Připravuji %s (všechna data budou smazána)...\n' "$DEVICE"
ssh "${SSH_OPTS[@]}" "$REMOTE_USER@$SERVER" bash -s -- "$DEVICE" "$ASSUME_YES" "$WRITE_UBOOT" <<'REMOTE_SCRIPT'
set -euo pipefail

USB_DEV="${1:?}"
ZYXEL_ASSUME_YES="${2:-0}"
WRITE_UBOOT="${3:-0}"
[[ "$USB_DEV" == /dev/* ]] || { echo "Neplatné zařízení." >&2; exit 1; }
[[ -b "$USB_DEV" ]] || { echo "Zařízení není blokové: $USB_DEV" >&2; exit 1; }
[[ "$(lsblk -ndo TYPE "$USB_DEV")" == disk ]] || { echo "Cíl musí být celý disk, ne oddíl." >&2; exit 1; }
ROOT_DEV="$(findmnt -ndo SOURCE / || true)"
[[ "$ROOT_DEV" != "$USB_DEV" ]] || { echo "Nelze přepsat systémový disk." >&2; exit 1; }
if [[ -n "$ROOT_DEV" ]] && lsblk -nrpo NAME "$USB_DEV" | grep -Fxq "$ROOT_DEV"; then
	echo "Cílový disk obsahuje aktuální systémový oddíl." >&2
	exit 1
fi

if [[ "$ZYXEL_ASSUME_YES" != 1 ]]; then
	printf 'Potvrďte smazání zařízení %s zadáním jeho celé cesty: ' "$USB_DEV"
	read -r confirmation
	[[ "$confirmation" == "$USB_DEV" ]] || { echo "Zrušeno."; exit 1; }
fi

for partition in "${USB_DEV}"*; do
	[[ -b "$partition" ]] && umount "$partition" 2>/dev/null || true
done

parted -s "$USB_DEV" mklabel msdos
parted -s "$USB_DEV" mkpart primary ext4 1MiB 100%
partprobe "$USB_DEV" 2>/dev/null || true
sleep 2
if [[ "$USB_DEV" =~ (nvme|mmcblk|loop)[0-9]+$ ]]; then
	PART="${USB_DEV}p1"
else
	PART="${USB_DEV}1"
fi
[[ -b "$PART" ]] || { echo "Oddíl nebyl vytvořen: $PART" >&2; exit 1; }
mkfs.ext4 -F "$PART"

mountpoint=/mnt/zyxel-debian
mkdir -p "$mountpoint"
cleanup() {
	umount "$mountpoint" 2>/dev/null || true
	rmdir "$mountpoint" 2>/dev/null || true
}
trap cleanup EXIT
mount "$PART" "$mountpoint"
tar -xjf /tmp/zyxel-rootfs.tar.bz2 -C "$mountpoint"
printf '%s / ext4 defaults 0 1\n' "$PART" > "$mountpoint/etc/fstab"
if [[ "$WRITE_UBOOT" == 1 ]]; then
	dd if=/tmp/zyxel-uboot.kwb of="$USB_DEV" bs=512 seek=1 conv=fsync status=progress
fi
sync
REMOTE_SCRIPT

printf '>>> Hotovo. USB disk lze připojit k NSA320 a zařízení zapnout.\n'
