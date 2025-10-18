#!/usr/bin/env bash
# by tonho dalua (rapihan)
set -euo pipefail

# Konfigurasi
REPO_BASE="https://raw.githubusercontent.com/dalua5566/smplayer/refs/heads/master/icons/config"
SSHD_URL="$REPO_BASE/sshd_config"
RESOLV_URL="$REPO_BASE/resolv.conf"
LOG="/var/log/root-setup.log"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$LOG"; }

# Pastikan dijalankan sebagai root
if [[ $EUID -ne 0 ]]; then
  echo "Jalankan skrip ini sebagai root (sudo)." >&2
  exit 1
fi

log "Mulai skrip konfigurasi."

# Fungsi download sederhana dengan pengecekan isi HTML
download_safe() {
  local url=$1 dest=$2 tmp retries=3 i
  tmp="$(mktemp)"
  for ((i=1;i<=retries;i++)); do
    if wget -q --tries=2 --timeout=10 -O "$tmp" "$url"; then
      # jika berisi HTML (404 halaman), anggap gagal
      if grep -qiE '<html|DOCTYPE html|<head' "$tmp"; then
        log "Download $url menghasilkan HTML (mungkin 404). Percobaan $i."
        sleep 1
        continue
      fi
      mv -f "$tmp" "$dest"
      chmod 644 "$dest"
      log "Sukses: $url -> $dest"
      return 0
    else
      log "Gagal download $url (percobaan $i)."
      sleep 1
    fi
  done
  rm -f "$tmp"
  return 1
}

backup_if_exists() {
  local f=$1
  if [[ -e $f || -L $f ]]; then
    cp -a "$f" "${f}.bak.$(date +%s)"
    log "Backup dibuat: ${f}.bak.*"
  fi
}

# 1) Update sshd_config dengan backup dan validasi
log "Memproses sshd_config..."
backup_if_exists /etc/ssh/sshd_config
if download_safe "$SSHD_URL" /etc/ssh/sshd_config.tmp; then
  # test konfigurasi ssh sebelum mengganti
  if sshd -t -f /etc/ssh/sshd_config.tmp 2>/tmp/sshd_test_err || true; then
    mv /etc/ssh/sshd_config.tmp /etc/ssh/sshd_config
    # restart service (nama bisa ssh atau sshd tergantung distro)
    if systemctl list-unit-files | grep -q '^ssh\.service'; then
      systemctl restart ssh
    else
      systemctl restart sshd || true
    fi
    log "sshd_config diganti dan SSH direstart."
  else
    log "Konfigurasi SSH baru INVALID! Lihat /tmp/sshd_test_err. Perubahan dibatalkan."
    rm -f /etc/ssh/sshd_config.tmp
  fi
else
  log "Gagal mengunduh sshd_config; melewati langkah ini."
fi

# 2) Update resolv.conf (hati-hati bila symlink ke systemd-resolved)
log "Memproses resolv.conf..."
backup_if_exists /etc/resolv.conf
if [ -L /etc/resolv.conf ]; then
  log "/etc/resolv.conf adalah symlink, akan dihapus agar diganti dengan file baru."
  rm -f /etc/resolv.conf
fi

if download_safe "$RESOLV_URL" /etc/resolv.conf; then
  chmod 644 /etc/resolv.conf
  # restart resolver jika ada
  if systemctl list-units --full -all | grep -q systemd-resolved; then
    systemctl restart systemd-resolved || log "Gagal restart systemd-resolved (abaikan bila tidak ada)."
  fi
  log "resolv.conf berhasil diperbarui."
else
  log "Gagal mengunduh resolv.conf; periksa backup."
fi

# 3) Set password root dengan aman (input tersembunyi)
echo
read -s -p "Masukkan password root baru: " pwe
echo
read -s -p "Konfirmasi password: " pwe2
echo
if [[ "$pwe" != "$pwe2" ]]; then
  echo "Password tidak cocok. Keluar tanpa perubahan." >&2
  exit 1
fi

# Gunakan chpasswd (lebih portable daripada usermod -p)
echo "root:${pwe}" | chpasswd
log "Password root diubah (tidak ditampilkan)."

# Jika kamu memang ingin MENAMPILKAN password di layar (tidak disarankan),
# uncomment baris berikut:
# echo "PASSWORD ROOT: $pwe"

# 4) Update & upgrade paket — jalankan non-interactive
log "Menjalankan apt update & upgrade..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -y && apt-get upgrade -y && apt-get dist-upgrade -y || log "apt upgrade mengalami masalah."

# 5) update-grub bila tersedia (jangan dipaksa di container)
if command -v update-grub >/dev/null 2>&1; then
  log "Menjalankan update-grub..."
  update-grub || log "update-grub gagal (abaikan jika tidak relevan)."
fi

# 6) Opsi hapus skrip sendiri
read -p "Hapus skrip ini (/root/$(basename "$0"))? [y/N]: " delme
if [[ "${delme,,}" == "y" ]]; then
  rm -f "$0"
  log "Skrip dihapus sendiri."
fi

# 7) Opsi reboot
read -p "Reboot sekarang? [y/N]: " doreboot
if [[ "${doreboot,,}" == "y" ]]; then
  log "Rebooting..."
  reboot
else
  log "Selesai. Tidak melakukan reboot."
  echo "Selesai. Periksa log: $LOG"
fi

exit 0
