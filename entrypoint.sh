#!/bin/bash
# =============================================================================
# entrypoint.sh – Minecraft Universal Startup Script
# Powered by MCJars.app API v2
# Pterodactyl Egg – Startet bei jedem Serverstart
# =============================================================================

# -----------------------------------------------------------------------
# BLOCK A – Farben & Hilfsfunktionen
# -----------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

# HTTP-GET mit Fehlerprüfung
api_get() {
  local url="$1"
  local response
  local http_code
  response=$(curl -s -w "\n%{http_code}" "$url" 2>/dev/null)
  http_code=$(echo "$response" | tail -1)
  body=$(echo "$response" | head -n -1)
  if [[ "$http_code" != "200" ]]; then
    return 1
  fi
  echo "$body"
  return 0
}

# Versionen einer Distribution von MCJars holen
get_versions() {
  local type="$1"
  local json
  if ! json=$(api_get "https://mcjars.app/api/v2/builds/${type}"); then
    return 1
  fi
  echo "$json" | jq -r '.versions | keys[]' 2>/dev/null | sort -Vr | head -30
}

# Download-URL des neuesten Builds ermitteln
get_download_url() {
  local type="$1"
  local version="$2"
  local json
  if ! json=$(api_get "https://mcjars.app/api/v2/builds/${type}/${version}"); then
    return 1
  fi

  # Primär: downloads.server.url
  local url
  url=$(echo "$json" | jq -r '.builds[0].downloads.server.url // empty' 2>/dev/null)

  # Fallback: erstes verfügbares download-Objekt
  if [[ -z "$url" ]]; then
    url=$(echo "$json" | jq -r '.builds[0].downloads | to_entries[0].value.url // empty' 2>/dev/null)
  fi

  echo "$url"
}

# -----------------------------------------------------------------------
# BLOCK B – Willkommensbanner & Sprachauswahl
# -----------------------------------------------------------------------
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║   Minecraft Universal Installer                  ║${RESET}"
echo -e "${BOLD}║   Powered by MCJars.app                          ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  [1] ${BOLD}Deutsch${RESET} (Standard)"
echo -e "  [2] English"
echo ""
read -r -p "  Sprache / Language [1/2] (Standard: 1): " LANG_CHOICE
LANG_CHOICE=${LANG_CHOICE:-1}

if [[ "$LANG_CHOICE" == "2" ]]; then
  LANG="en"
else
  LANG="de"
fi

# -----------------------------------------------------------------------
# Mehrsprachige UI-Texte
# -----------------------------------------------------------------------
if [[ "$LANG" == "de" ]]; then
  TXT_WELCOME="Willkommen beim Minecraft Server Setup!"
  TXT_SELECT_DIST="Wähle eine Server-Distribution:"
  TXT_SELECT_VER="Wähle eine Minecraft-Version:"
  TXT_LOADING="Lade Versionen von MCJars..."
  TXT_CONFIRM="Bestätigen? [j/n]: "
  TXT_CONFIRM_YES="j"
  TXT_DOWNLOADING="Lade Server-JAR herunter..."
  TXT_DONE="Setup abgeschlossen! Server wird gestartet..."
  TXT_EULA="Ich akzeptiere die Minecraft EULA (https://aka.ms/MinecraftEULA) [j/n]: "
  TXT_EULA_ABORT="EULA nicht akzeptiert. Server wird nicht gestartet."
  TXT_LATEST="(Neueste)"
  TXT_CAT_VANILLA="── Vanilla ──"
  TXT_CAT_PLUGIN="── Plugin-Server ──"
  TXT_CAT_PROXY="── Proxy ──"
  TXT_CAT_MOD="── Mod-Server ──"
  TXT_CAT_HYBRID="── Hybrid ──"
  TXT_INVALID="Ungültige Eingabe, bitte erneut versuchen."
  TXT_NO_VERSIONS="Keine Versionen für diese Distribution gefunden."
  TXT_DL_ERROR="Download fehlgeschlagen. Bitte Verbindung prüfen."
  TXT_API_ERROR="API-Fehler. Bitte erneut versuchen."
  TXT_DISTRIBUTION="Distribution:"
  TXT_VERSION="Version:     "
  TXT_URL="URL:         "
  TXT_CANCELLED="Abgebrochen."
  TXT_DL_SUCCESS="server.jar erfolgreich heruntergeladen"
  TXT_START_INFO="Starte Server mit"
  TXT_RAM="RAM"
  TXT_ALREADY_INSTALLED="server.jar gefunden – überspringe Setup-Wizard."
  TXT_INSTALLED_INFO="Installierte Distribution:"
  TXT_RESTARTING="Server wird (neu-)gestartet..."
  TXT_INSTALLER_RUNNING="Forge/NeoForge Installer wird ausgeführt..."
  TXT_INSTALLER_DONE="Installer abgeschlossen. Server wird gestartet..."
else
  TXT_WELCOME="Welcome to the Minecraft Server Setup!"
  TXT_SELECT_DIST="Select a server distribution:"
  TXT_SELECT_VER="Select a Minecraft version:"
  TXT_LOADING="Loading versions from MCJars..."
  TXT_CONFIRM="Confirm? [y/n]: "
  TXT_CONFIRM_YES="y"
  TXT_DOWNLOADING="Downloading server JAR..."
  TXT_DONE="Setup complete! Starting server..."
  TXT_EULA="I accept the Minecraft EULA (https://aka.ms/MinecraftEULA) [y/n]: "
  TXT_EULA_ABORT="EULA not accepted. Server will not start."
  TXT_LATEST="(Latest)"
  TXT_CAT_VANILLA="── Vanilla ──"
  TXT_CAT_PLUGIN="── Plugin Servers ──"
  TXT_CAT_PROXY="── Proxy ──"
  TXT_CAT_MOD="── Mod Servers ──"
  TXT_CAT_HYBRID="── Hybrid ──"
  TXT_INVALID="Invalid input, please try again."
  TXT_NO_VERSIONS="No versions found for this distribution."
  TXT_DL_ERROR="Download failed. Please check your connection."
  TXT_API_ERROR="API error. Please try again."
  TXT_DISTRIBUTION="Distribution:"
  TXT_VERSION="Version:     "
  TXT_URL="URL:         "
  TXT_CANCELLED="Cancelled."
  TXT_DL_SUCCESS="server.jar downloaded successfully"
  TXT_START_INFO="Starting server with"
  TXT_RAM="RAM"
  TXT_ALREADY_INSTALLED="server.jar found – skipping setup wizard."
  TXT_INSTALLED_INFO="Installed distribution:"
  TXT_RESTARTING="(Re)starting server..."
  TXT_INSTALLER_RUNNING="Running Forge/NeoForge installer..."
  TXT_INSTALLER_DONE="Installer complete. Starting server..."
fi

# -----------------------------------------------------------------------
# BLOCK C – Prüfung: server.jar vorhanden?
# -----------------------------------------------------------------------
if [[ -f "server.jar" && -s "server.jar" ]]; then
  echo ""
  echo -e "  ${GREEN}✓ ${TXT_ALREADY_INSTALLED}${RESET}"

  # Installationsinfos anzeigen falls vorhanden
  if [[ -f ".mcjars-config" ]]; then
    source .mcjars-config 2>/dev/null || true
    echo -e "  ${TXT_INSTALLED_INFO} ${BOLD}${TYPE}${RESET} ${VERSION}"
  fi

  echo ""
  echo -e "  ${CYAN}${TXT_RESTARTING}${RESET}"
  echo ""

  # Direkt zu BLOCK H (Server starten)
  SKIP_WIZARD=true
else
  SKIP_WIZARD=false
fi

# -----------------------------------------------------------------------
# SETUP-WIZARD (nur wenn keine server.jar vorhanden)
# -----------------------------------------------------------------------
if [[ "$SKIP_WIZARD" == "false" ]]; then

  echo ""
  echo -e "  ${BOLD}${TXT_WELCOME}${RESET}"
  echo ""

  # -----------------------------------------------------------------------
  # BLOCK D – Distributions-Auswahl
  # -----------------------------------------------------------------------
  echo -e "${CYAN}  ${TXT_SELECT_DIST}${RESET}"
  echo ""
  echo -e "  ${BOLD}${TXT_CAT_VANILLA}${RESET}"
  echo -e "   [1]  Vanilla"
  echo ""
  echo -e "  ${BOLD}${TXT_CAT_PLUGIN}${RESET}"
  echo -e "   [2]  Paper        ${GREEN}★ Empfohlen / Recommended${RESET}"
  echo -e "   [3]  Purpur"
  echo -e "   [4]  Pufferfish"
  echo -e "   [5]  Spigot"
  echo -e "   [6]  Folia"
  echo -e "   [7]  Leaves"
  echo ""
  echo -e "  ${BOLD}${TXT_CAT_PROXY}${RESET}"
  echo -e "   [8]  Velocity"
  echo -e "   [9]  Waterfall"
  echo -e "   [10] BungeeCord"
  echo ""
  echo -e "  ${BOLD}${TXT_CAT_MOD}${RESET}"
  echo -e "   [11] Fabric"
  echo -e "   [12] Quilt"
  echo -e "   [13] Forge"
  echo -e "   [14] NeoForge"
  echo -e "   [15] SpongeVanilla"
  echo -e "   [16] Canvas"
  echo ""
  echo -e "  ${BOLD}${TXT_CAT_HYBRID}${RESET}"
  echo -e "   [17] Mohist        ${YELLOW}(Forge + Bukkit)${RESET}"
  echo -e "   [18] Arclight      ${YELLOW}(Forge/Fabric + Bukkit)${RESET}"
  echo ""

  # Mapping: Nummer → API-Typ
  declare -A DIST_MAP=(
    [1]="VANILLA"    [2]="PAPER"       [3]="PURPUR"
    [4]="PUFFERFISH" [5]="SPIGOT"      [6]="FOLIA"
    [7]="LEAVES"     [8]="VELOCITY"    [9]="WATERFALL"
    [10]="BUNGEECORD" [11]="FABRIC"    [12]="QUILT"
    [13]="FORGE"     [14]="NEOFORGE"   [15]="SPONGE"
    [16]="CANVAS"    [17]="MOHIST"     [18]="ARCLIGHT"
  )

  while true; do
    read -r -p "  > " DIST_CHOICE
    if [[ -n "${DIST_MAP[$DIST_CHOICE]+_}" ]]; then
      SELECTED_TYPE="${DIST_MAP[$DIST_CHOICE]}"
      break
    else
      echo -e "  ${RED}${TXT_INVALID}${RESET}"
    fi
  done

  # -----------------------------------------------------------------------
  # BLOCK E – Versions-Auswahl (live von MCJars API)
  # -----------------------------------------------------------------------
  echo ""
  echo -e "  ${CYAN}${TXT_LOADING}${RESET}"

  VERSIONS_RAW=$(get_versions "$SELECTED_TYPE") || true
  mapfile -t VERSIONS <<< "$VERSIONS_RAW"

  # Leere Einträge filtern
  VERSIONS=("${VERSIONS[@]//[[:space:]]/}")
  VERSIONS=("${VERSIONS[@]/#/}")
  VALID_VERSIONS=()
  for v in "${VERSIONS[@]}"; do
    [[ -n "$v" ]] && VALID_VERSIONS+=("$v")
  done
  VERSIONS=("${VALID_VERSIONS[@]}")

  if [[ ${#VERSIONS[@]} -eq 0 ]]; then
    echo -e "  ${RED}${TXT_NO_VERSIONS}${RESET}"
    exit 1
  fi

  echo ""
  echo -e "  ${CYAN}${TXT_SELECT_VER}${RESET}"
  echo ""

  for i in "${!VERSIONS[@]}"; do
    NUM=$((i + 1))
    VER="${VERSIONS[$i]}"
    if [[ $i -eq 0 ]]; then
      echo -e "   [${NUM}]  ${VER}  ${GREEN}${TXT_LATEST}${RESET}"
    else
      printf "   [%-3s]  %s\n" "$NUM" "$VER"
    fi
  done
  echo ""

  while true; do
    read -r -p "  > " VER_CHOICE
    if [[ "$VER_CHOICE" =~ ^[0-9]+$ ]] \
        && [[ "$VER_CHOICE" -ge 1 ]] \
        && [[ "$VER_CHOICE" -le ${#VERSIONS[@]} ]]; then
      SELECTED_VERSION="${VERSIONS[$((VER_CHOICE - 1))]}"
      break
    else
      echo -e "  ${RED}${TXT_INVALID}${RESET}"
    fi
  done

  # -----------------------------------------------------------------------
  # BLOCK F – Download-URL ermitteln & Bestätigung
  # -----------------------------------------------------------------------
  echo ""
  echo -e "  ${CYAN}${TXT_LOADING}${RESET}"

  DOWNLOAD_URL=$(get_download_url "$SELECTED_TYPE" "$SELECTED_VERSION") || true

  if [[ -z "$DOWNLOAD_URL" ]]; then
    echo -e "  ${RED}${TXT_API_ERROR}${RESET}"
    exit 1
  fi

  echo ""
  echo -e "  ┌─────────────────────────────────────────────────┐"
  echo -e "  │  ${BOLD}${TXT_DISTRIBUTION}${RESET} ${SELECTED_TYPE}"
  echo -e "  │  ${BOLD}${TXT_VERSION}${RESET} ${SELECTED_VERSION}"
  echo -e "  │  ${BOLD}${TXT_URL}${RESET} ${DOWNLOAD_URL:0:48}"
  echo -e "  └─────────────────────────────────────────────────┘"
  echo ""

  while true; do
    read -r -p "  ${TXT_CONFIRM}" CONFIRM
    CONFIRM_LC=$(echo "$CONFIRM" | tr '[:upper:]' '[:lower:]')
    if [[ "$LANG" == "de" ]]; then
      [[ "$CONFIRM_LC" == "j" ]] && break
      [[ "$CONFIRM_LC" == "n" ]] && echo "  ${TXT_CANCELLED}" && exit 0
    else
      [[ "$CONFIRM_LC" == "y" ]] && break
      [[ "$CONFIRM_LC" == "n" ]] && echo "  ${TXT_CANCELLED}" && exit 0
    fi
    echo -e "  ${RED}${TXT_INVALID}${RESET}"
  done

  echo ""
  echo -e "  ${CYAN}${TXT_DOWNLOADING}${RESET}"
  curl -L --progress-bar -o server.jar "$DOWNLOAD_URL"

  # Download prüfen
  if [[ ! -f "server.jar" ]] || [[ ! -s "server.jar" ]]; then
    echo -e "  ${RED}${TXT_DL_ERROR}${RESET}"
    rm -f server.jar
    exit 1
  fi

  # -----------------------------------------------------------------------
  # Forge / NeoForge Sonderbehandlung
  # Falls eine installer.jar heruntergeladen wurde, Installer ausführen
  # -----------------------------------------------------------------------
  IS_INSTALLER=false
  if [[ "$SELECTED_TYPE" == "FORGE" ]] || [[ "$SELECTED_TYPE" == "NEOFORGE" ]]; then
    FILE_TYPE=$(file server.jar 2>/dev/null | grep -i "jar\|zip" || true)
    # MCJars liefert für Forge einen server-starter.jar, der den Installer enthält
    # Prüfen ob es ein Installer ist (enthält install-Klassen)
    if unzip -l server.jar 2>/dev/null | grep -q "install"; then
      IS_INSTALLER=true
      echo ""
      echo -e "  ${YELLOW}${TXT_INSTALLER_RUNNING}${RESET}"
      mv server.jar forge-installer.jar
      java -jar forge-installer.jar --installServer 2>&1 | tail -5
      rm -f forge-installer.jar

      # Nach Installer: server.jar oder run.sh suchen
      if [[ -f "run.sh" ]]; then
        chmod +x run.sh
        echo -e "  ${GREEN}${TXT_INSTALLER_DONE}${RESET}"
      elif [[ ! -f "server.jar" ]]; then
        # Neueste .jar suchen (außer installer)
        FOUND_JAR=$(ls -1t *.jar 2>/dev/null | grep -v installer | head -1)
        if [[ -n "$FOUND_JAR" ]]; then
          cp "$FOUND_JAR" server.jar
        fi
      fi
    fi
  fi

  # -----------------------------------------------------------------------
  # Konfiguration speichern
  # -----------------------------------------------------------------------
  cat > .mcjars-config <<EOF
TYPE=${SELECTED_TYPE}
VERSION=${SELECTED_VERSION}
DOWNLOAD_URL=${DOWNLOAD_URL}
INSTALLED=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
EOF

  echo ""
  echo -e "  ${GREEN}✓ ${TXT_DL_SUCCESS}${RESET}"

  # -----------------------------------------------------------------------
  # BLOCK G – EULA (nur für Nicht-Proxy-Server)
  # -----------------------------------------------------------------------
  PROXY_TYPES=("VELOCITY" "WATERFALL" "BUNGEECORD")
  IS_PROXY=false
  for pt in "${PROXY_TYPES[@]}"; do
    [[ "$SELECTED_TYPE" == "$pt" ]] && IS_PROXY=true && break
  done

  if [[ "$IS_PROXY" == "false" ]]; then
    echo ""
    echo -e "  ${YELLOW}${TXT_EULA}${RESET}"
    read -r -p "  > " EULA_ACCEPT
    EULA_LC=$(echo "$EULA_ACCEPT" | tr '[:upper:]' '[:lower:]')

    ACCEPTED=false
    if [[ "$LANG" == "de" ]]; then
      [[ "$EULA_LC" == "j" ]] && ACCEPTED=true
    else
      [[ "$EULA_LC" == "y" ]] && ACCEPTED=true
    fi

    if [[ "$ACCEPTED" == "false" ]]; then
      echo ""
      echo -e "  ${RED}${TXT_EULA_ABORT}${RESET}"
      rm -f server.jar
      exit 1
    fi

    echo "eula=true" > eula.txt
    echo -e "  ${GREEN}✓ eula.txt erstellt / created${RESET}"
  fi

  # -----------------------------------------------------------------------
  # server.properties anlegen (nur für Nicht-Proxy-Server)
  # -----------------------------------------------------------------------
  if [[ "$IS_PROXY" == "false" ]] && [[ ! -f "server.properties" ]]; then
    cat > server.properties <<EOF
server-port=${SERVER_PORT:-25565}
online-mode=${ONLINE_MODE:-true}
max-players=${MAX_PLAYERS:-20}
view-distance=${VIEW_DISTANCE:-10}
motd=A Minecraft Server (MCJars Universal Egg)
EOF
    echo -e "  ${GREEN}✓ server.properties angelegt / created${RESET}"
  fi

  echo ""
  echo -e "${GREEN}  ${TXT_DONE}${RESET}"
  echo ""

fi  # Ende SKIP_WIZARD

# -----------------------------------------------------------------------
# BLOCK H – Server starten
# -----------------------------------------------------------------------

# Forge run.sh bevorzugen wenn vorhanden
if [[ -f "run.sh" ]] && ( [[ "$TYPE" == "FORGE" ]] || [[ "$TYPE" == "NEOFORGE" ]] || [[ "$SELECTED_TYPE" == "FORGE" ]] || [[ "$SELECTED_TYPE" == "NEOFORGE" ]] ); then
  echo -e "  ${CYAN}Starte über run.sh (Forge/NeoForge)...${RESET}"
  exec bash run.sh --nogui
fi

# Standard Java-Start
JAVA_ARGS="${JAVA_FLAGS:--XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 -XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch -XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M -XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 -XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 -XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 -XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1}"
MEMORY="${SERVER_MEMORY:-1024}"

echo -e "  ${CYAN}${TXT_START_INFO} ${MEMORY}M ${TXT_RAM}...${RESET}"
echo ""

exec java \
  -Xms128M \
  "-Xmx${MEMORY}M" \
  ${JAVA_ARGS} \
  -jar server.jar \
  --nogui
