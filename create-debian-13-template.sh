#!/usr/bin/env bash
# ==============================================================================
# Proxmox Debian Cloud-Init VM Template Creator (made with claude.ai)
# ==============================================================================
# Erstellt ein Debian Cloud-Image Template in Proxmox VE.
# Getestet mit Proxmox VE 7.x / 8.x und Debian 13 (Trixie).
#
# Voraussetzungen:
#   - Dieses Script muss direkt auf dem Proxmox-Host als root ausgeführt werden
#   - libguestfs-tools muss installiert sein (wird ggf. automatisch installiert)
#
# Verwendung:
#   chmod +x create-debian-template.sh
#   ./create-debian-template.sh
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# KONFIGURATION – hier anpassen
# ------------------------------------------------------------------------------
VMID=9000                          # Template VM-ID (muss eindeutig sein)
TEMPLATE_NAME="debian-13-template" # Name des Templates
STORAGE="local-zfs"                # Ziel-Storage für Disk & Cloud-Init (z. B. local-lvm, local-zfs, ceph-pool)
MEMORY=2048                        # RAM in MB
CORES=2                            # CPU-Kerne
DISK_SIZE="20G"                    # Disk-Größe (nach Import)
BRIDGE="vmbr0"                     # Netzwerk-Bridge
SNIPPET_STORAGE="local"            # Storage für Cloud-Init Snippets (muss "Snippets" erlauben)

# Temporäres Verzeichnis für den Image-Download
IMAGE_TMPDIR="/tmp"

# Debian 13 Trixie Generic Cloud Image
IMAGE_URL="https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2"
IMAGE_FILE="debian-13-genericcloud-amd64.qcow2"

# Cloud-Init Standardwerte
CI_USER="debian"                   # Standard-Benutzer
CI_PASSWORD=""                     # Leer lassen → nur SSH-Key-Login
CI_SEARCHDOMAIN="local"
CI_NAMESERVER="1.1.1.1,1.0.0.1"

# SSH Public Key (leer lassen, falls nicht gewünscht)
SSH_KEY_FILE=""                    # z. B. "/root/.ssh/id_rsa.pub"

# ------------------------------------------------------------------------------
# FARBEN & HILFSFUNKTIONEN
# ------------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC}  $*"; }
success() { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${BOLD}==> $*${NC}"; }

# ------------------------------------------------------------------------------
# VORAUSSETZUNGEN PRÜFEN
# ------------------------------------------------------------------------------
step "Voraussetzungen prüfen"

[[ $EUID -ne 0 ]] && error "Dieses Script muss als root ausgeführt werden."

command -v pvesh &>/dev/null || error "pvesh nicht gefunden – bitte auf einem Proxmox-Host ausführen."
command -v qm    &>/dev/null || error "qm nicht gefunden – bitte auf einem Proxmox-Host ausführen."

# libguestfs-tools installieren (für virt-customize)
if ! command -v virt-customize &>/dev/null; then
  warn "virt-customize nicht gefunden. Installiere libguestfs-tools..."
  apt-get update -qq && apt-get install -y libguestfs-tools
fi

# Prüfen ob VM-ID bereits existiert
if qm status "$VMID" &>/dev/null; then
  warn "VM mit ID $VMID existiert bereits."
  read -rp "  Bestehende VM löschen und neu erstellen? [j/N] " confirm
  [[ "${confirm,,}" == "j" ]] || error "Abgebrochen."
  qm destroy "$VMID" --purge
  success "Alte VM $VMID gelöscht."
fi

success "Alle Voraussetzungen erfüllt."

# ------------------------------------------------------------------------------
# CLOUD-IMAGE HERUNTERLADEN
# ------------------------------------------------------------------------------
step "Debian Cloud-Image herunterladen"

WORKDIR="$IMAGE_TMPDIR"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

if [[ -f "$IMAGE_FILE" ]]; then
  info "Image bereits vorhanden: $WORKDIR/$IMAGE_FILE"
  read -rp "  Neu herunterladen? [j/N] " redownload
  if [[ "${redownload,,}" == "j" ]]; then
    rm -f "$IMAGE_FILE"
    wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_FILE"
    success "Image heruntergeladen."
  else
    info "Bestehendes Image wird verwendet."
  fi
else
  wget -q --show-progress "$IMAGE_URL" -O "$IMAGE_FILE"
  success "Image heruntergeladen: $IMAGE_FILE"
fi

# ------------------------------------------------------------------------------
# IMAGE ANPASSEN (qemu-guest-agent vorinstallieren)
# ------------------------------------------------------------------------------
step "Image anpassen (qemu-guest-agent + cloud-init)"

virt-customize \
  -a "$IMAGE_FILE" \
  --install qemu-guest-agent,cloud-init,cloud-initramfs-growroot \
  --run-command "systemctl enable qemu-guest-agent" \
  --run-command "apt-get clean" \
  --truncate /etc/machine-id \
  --truncate /etc/hostname

success "Image erfolgreich angepasst."

# ------------------------------------------------------------------------------
# VM ERSTELLEN
# ------------------------------------------------------------------------------
step "Proxmox VM erstellen (ID: $VMID)"

qm create "$VMID" \
  --name "$TEMPLATE_NAME" \
  --memory "$MEMORY" \
  --cores "$CORES" \
  --net0 "virtio,bridge=${BRIDGE}" \
  --ostype l26 \
  --machine q35 \
  --cpu host \
  --scsihw virtio-scsi-pci \
  --agent enabled=1 \
  --tablet 0 \
  --boot c \
  --bootdisk scsi0

success "VM $VMID angelegt."

# ------------------------------------------------------------------------------
# DISK IMPORTIEREN
# ------------------------------------------------------------------------------
step "Disk-Image importieren nach Storage: $STORAGE"

qm importdisk "$VMID" "$IMAGE_FILE" "$STORAGE"

# Importierte Disk als SCSI0 anhängen
qm set "$VMID" --scsi0 "${STORAGE}:vm-${VMID}-disk-0,discard=on"

# Disk auf gewünschte Größe erweitern
qm disk resize "$VMID" scsi0 "$DISK_SIZE"

# CloudInit-Drive hinzufügen
qm set "$VMID" --ide2 "${STORAGE}:cloudinit"

# Serielle Konsole (für Cloud-Init Output)
qm set "$VMID" --serial0 socket --vga serial0

success "Disk importiert und konfiguriert."

# ------------------------------------------------------------------------------
# CLOUD-INIT KONFIGURIEREN
# ------------------------------------------------------------------------------
step "Cloud-Init konfigurieren"

qm set "$VMID" \
  --ciuser  "$CI_USER" \
  --searchdomain "$CI_SEARCHDOMAIN" \
  --nameserver "$CI_NAMESERVER" \
  --ipconfig0 "ip=dhcp"

if [[ -n "$CI_PASSWORD" ]]; then
  qm set "$VMID" --cipassword "$CI_PASSWORD"
  info "Passwort für Benutzer '$CI_USER' gesetzt."
fi

if [[ -n "$SSH_KEY_FILE" && -f "$SSH_KEY_FILE" ]]; then
  qm set "$VMID" --sshkeys "$SSH_KEY_FILE"
  success "SSH Public Key aus '$SSH_KEY_FILE' hinzugefügt."
else
  warn "Kein SSH Key konfiguriert – SSH_KEY_FILE setzen für schlüsselbasierten Login."
fi

success "Cloud-Init konfiguriert."

# ------------------------------------------------------------------------------
# ZU TEMPLATE KONVERTIEREN
# ------------------------------------------------------------------------------
step "VM zu Template konvertieren"

qm template "$VMID"

success "Template '$TEMPLATE_NAME' (ID: $VMID) erfolgreich erstellt!"

# ------------------------------------------------------------------------------
# ZUSAMMENFASSUNG
# ------------------------------------------------------------------------------
echo ""
echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}${BOLD}║          Template erfolgreich erstellt!              ║${NC}"
echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  Template-Name : ${BOLD}${TEMPLATE_NAME}${NC} (Debian 13 Trixie)"
echo -e "  VM-ID         : ${BOLD}${VMID}${NC}"
echo -e "  Storage       : ${BOLD}${STORAGE}${NC}"
echo -e "  RAM           : ${BOLD}${MEMORY} MB${NC}"
echo -e "  Kerne         : ${BOLD}${CORES}${NC}"
echo -e "  Disk          : ${BOLD}${DISK_SIZE}${NC}"
echo -e "  Cloud-User    : ${BOLD}${CI_USER}${NC}"
echo ""
echo -e "${BLUE}Neue VM aus Template klonen:${NC}"
echo -e "  qm clone ${VMID} <NEUE-ID> --name <name> --full"
echo -e "  qm set   <NEUE-ID> --ipconfig0 ip=<IP>/24,gw=<GW>"
echo -e "  qm start <NEUE-ID>"
echo ""
