#!/bin/bash
# =============================================================================
# install.sh – Pterodactyl Install Script
# Minecraft Universal Egg powered by MCJars.app
# Läuft einmalig im Pterodactyl-Install-Container
# =============================================================================

set -e

echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Minecraft Universal Installer – Setup           ║"
echo "║  Powered by MCJars.app                           ║"
echo "╚══════════════════════════════════════════════════╝"
echo ""

# -----------------------------------------------------------------------
# 1. Paketmanager erkennen und Abhängigkeiten installieren
# -----------------------------------------------------------------------
if command -v apt-get &>/dev/null; then
  echo "[*] Debian/Ubuntu erkannt – installiere Abhängigkeiten..."
  apt-get update -y
  apt-get install -y curl jq ca-certificates
elif command -v apk &>/dev/null; then
  echo "[*] Alpine erkannt – installiere Abhängigkeiten..."
  apk add --no-cache curl jq ca-certificates
elif command -v yum &>/dev/null; then
  echo "[*] RHEL/CentOS erkannt – installiere Abhängigkeiten..."
  yum install -y curl jq ca-certificates
else
  echo "[!] Kein bekannter Paketmanager gefunden. Bitte curl und jq manuell installieren."
fi

# -----------------------------------------------------------------------
# 2. Verfügbarkeit prüfen
# -----------------------------------------------------------------------
echo ""
echo "[*] Prüfe installierte Tools..."

if ! command -v curl &>/dev/null; then
  echo "[!] FEHLER: curl nicht gefunden!"
  exit 1
fi
echo "    ✓ curl $(curl --version | head -1 | awk '{print $2}')"

if ! command -v jq &>/dev/null; then
  echo "[!] FEHLER: jq nicht gefunden!"
  exit 1
fi
echo "    ✓ jq $(jq --version)"

# -----------------------------------------------------------------------
# 3. entrypoint.sh in den Container kopieren
#    (Das Skript wird vom Egg-System in /mnt/server abgelegt;
#     wir stellen sicher, dass es ausführbar ist.)
# -----------------------------------------------------------------------
TARGET_DIR="/mnt/server"
mkdir -p "$TARGET_DIR"

if [[ -f "/mnt/server/entrypoint.sh" ]]; then
  chmod +x "$TARGET_DIR/entrypoint.sh"
  echo "    ✓ entrypoint.sh gefunden und ausführbar gesetzt"
else
  echo "[!] WARNUNG: entrypoint.sh nicht unter /mnt/server gefunden."
  echo "    Stelle sicher, dass entrypoint.sh im Egg-Paket enthalten ist."
fi

# -----------------------------------------------------------------------
# 4. MCJars API erreichbar?
# -----------------------------------------------------------------------
echo ""
echo "[*] Prüfe MCJars API-Verbindung..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://mcjars.app/api/v2/builds/VANILLA" || true)
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "    ✓ MCJars API erreichbar (HTTP $HTTP_CODE)"
else
  echo "    [!] MCJars API meldet HTTP $HTTP_CODE – Verbindung beim ersten Start prüfen."
fi

# -----------------------------------------------------------------------
# 5. Fertig
# -----------------------------------------------------------------------
echo ""
echo "╔══════════════════════════════════════════════════╗"
echo "║  Installation abgeschlossen!                     ║"
echo "║  Der Setup-Wizard startet beim ersten Serverstart║"
echo "╚══════════════════════════════════════════════════╝"
echo ""
