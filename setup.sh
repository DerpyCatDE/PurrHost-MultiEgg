#!/bin/bash
# ============================================================
#   Minecraft Multi-Egg — Console Setup Wizard
#   Nur curl + jq (kein python3 benötigt)
# ============================================================

R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; M='\033[0;35m'
W='\033[1;37m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

CONFIG_FILE="/home/container/.mce_config"
INSTALL_LOCK="/home/container/.mce_installed"
USE_RUN_SH=false

# ─── jq sicherstellen ────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "jq nicht gefunden — wird installiert..."
  if command -v apt-get &>/dev/null; then
    apt-get update -qq && apt-get install -y -qq jq 2>/dev/null || true
  elif command -v apk &>/dev/null; then
    apk add --no-cache jq 2>/dev/null || true
  fi
  # Falls apt/apk nicht verfügbar oder fehlgeschlagen: jq-Binary direkt laden
  if ! command -v jq &>/dev/null; then
    curl -sSL "https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64" \
      -o /usr/local/bin/jq 2>/dev/null && chmod +x /usr/local/bin/jq 2>/dev/null || true
  fi
fi

SERVER_MEMORY="${MC_MEMORY:-1024}"
EXTRA_JVM_FLAGS="${EXTRA_JVM_FLAGS:-}"
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"
EULA="${MC_EULA:-false}"
CURSEFORGE_API_KEY="${CURSEFORGE_API_KEY:-}"

W_PLATFORM=""; W_CATEGORY=""; W_DIST=""
W_VERSION="latest"; W_BUILD="latest"
W_CF_INPUT=""; W_MR_INPUT=""; W_CF_KEY=""
W_EULA=false

# ════════════════════════════════════════════════════════════
#  UI
# ════════════════════════════════════════════════════════════
clear_screen() { printf '\033[2J\033[H'; }

header() {
  echo ""
  echo -e "${B}${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${B}${BOLD}  ║       🎮  Minecraft Multi-Egg  •  Setup Wizard       ║${NC}"
  echo -e "${B}${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
}

breadcrumb() { echo -e "  ${DIM}Pfad: ${C}$1${NC}"; echo ""; }
section()    { echo -e "  ${W}${BOLD}$1${NC}"; echo -e "  ${DIM}$(printf '─%.0s' {1..52})${NC}"; }
opt()        { [ -n "$3" ] && echo -e "    ${C}[$1]${NC}  ${W}$2${NC}  ${DIM}— $3${NC}" || echo -e "    ${C}[$1]${NC}  ${W}$2${NC}"; }
ok()         { echo -e "  ${G}✔${NC}  $1"; }
info()       { echo -e "  ${B}ℹ${NC}  $1"; }
warn()       { echo -e "  ${Y}⚠${NC}  $1"; }
err()        { echo -e "  ${R}✖${NC}  $1"; }
step()       { echo -e "  ${M}→${NC}  $1"; }

prompt() {
  local question="$1" min="$2" max="$3"
  echo ""; echo -e "  ${Y}❯${NC}  ${W}${question}${NC}  ${DIM}(${min}–${max})${NC}"; echo -ne "  ${Y}»${NC} "
  CHOICE=""
  while IFS= read -r CHOICE; do
    [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge "$min" ] && [ "$CHOICE" -le "$max" ] && break
    echo -e "  ${R}Ungültig.${NC} Bitte ${min}–${max} eingeben."; echo -ne "  ${Y}»${NC} "
  done
}

prompt_text() {
  local question="$1" default="${2:-}"
  echo ""
  [ -n "$default" ] && echo -e "  ${Y}❯${NC}  ${W}${question}${NC}  ${DIM}(Standard: ${default})${NC}" \
                     || echo -e "  ${Y}❯${NC}  ${W}${question}${NC}"
  echo -ne "  ${Y}»${NC} "; TEXT_INPUT=""; IFS= read -r TEXT_INPUT
  [ -z "$TEXT_INPUT" ] && TEXT_INPUT="$default"
}

prompt_yesno() {
  echo ""; echo -e "  ${Y}❯${NC}  ${W}$1${NC}  ${DIM}(j / n)${NC}"; echo -ne "  ${Y}»${NC} "
  local ans; IFS= read -r ans
  [[ "$ans" =~ ^(j|J|ja|yes|y|Y|1)$ ]] && YESNO=true || YESNO=false
}

save_config() {
  cat > "$CONFIG_FILE" << EOF
MC_DISTRIBUTION="${MC_DISTRIBUTION}"
MC_VERSION="${MC_VERSION}"
MC_BUILD="${MC_BUILD}"
CURSEFORGE_MODPACK="${CURSEFORGE_MODPACK}"
MODRINTH_MODPACK="${MODRINTH_MODPACK}"
CURSEFORGE_API_KEY="${CURSEFORGE_API_KEY}"
SERVER_MEMORY="${SERVER_MEMORY}"
EXTRA_JVM_FLAGS="${EXTRA_JVM_FLAGS}"
EULA="${EULA}"
EOF
}

load_config() { [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"; }
accept_eula() { echo "eula=true" > /home/container/eula.txt; ok "EULA akzeptiert."; }

# ════════════════════════════════════════════════════════════
#  DOWNLOAD
# ════════════════════════════════════════════════════════════
download_file() {
  local url="$1" dest="$2" desc="${3:-Datei}"
  step "Lade ${desc} herunter..."
  curl -sSL --retry 3 --retry-delay 5 -o "$dest" "$url"
  if [ -f "$dest" ] && [ -s "$dest" ]; then
    ok "${desc} heruntergeladen."
  else
    err "Download fehlgeschlagen: ${url}"; exit 1
  fi
}

get_latest_mc_version() {
  curl -sSL "https://launchermeta.mojang.com/mc/game/version_manifest.json" \
    | jq -r '.latest.release'
}

get_mc_server_url() {
  local mc_ver="$1"
  local version_url
  version_url=$(curl -sSL "https://launchermeta.mojang.com/mc/game/version_manifest.json" \
    | jq -r --arg v "$mc_ver" '.versions[] | select(.id==$v) | .url')
  [ -z "$version_url" ] && { err "MC Version ${mc_ver} nicht gefunden!"; exit 1; }
  curl -sSL "$version_url" | jq -r '.downloads.server.url'
}

# ════════════════════════════════════════════════════════════
#  WIZARD
# ════════════════════════════════════════════════════════════
wizard_platform() {
  clear_screen; header
  section "Schritt 1 von 5  —  Platform auswählen"; echo ""
  opt 1 "Minecraft: Java Edition"    "Plugin-, Mod-, Proxy- und Vanilla-Server"
  opt 2 "Minecraft: Bedrock Edition" "PocketMine, Nukkit, WaterdogPE"
  echo ""; prompt "Wähle die Platform" 1 2
  case "$CHOICE" in 1) W_PLATFORM="java" ;; 2) W_PLATFORM="bedrock" ;; esac
}

wizard_java_category() {
  clear_screen; header; breadcrumb "Java Edition"
  section "Schritt 2 von 5  —  Server-Kategorie"; echo ""
  opt 1 "Proxy"         "Velocity, Waterfall, BungeeCord"
  opt 2 "Vanilla"       "Offizieller Mojang Server"
  opt 3 "Plugin-Server" "Paper, Purpur, Spigot, Folia, Leaves, Pufferfish"
  opt 4 "Mod-Server"    "Forge, NeoForge, Fabric, Quilt, Sponge"
  opt 5 "Hybrid-Server" "Mohist, Arclight, CatServer"
  opt 6 "Modpack"       "CurseForge oder Modrinth"
  echo ""; prompt "Wähle die Kategorie" 1 6
  case "$CHOICE" in
    1) W_CATEGORY="proxy"   ;; 2) W_CATEGORY="vanilla" ;;
    3) W_CATEGORY="plugin"  ;; 4) W_CATEGORY="modded"  ;;
    5) W_CATEGORY="hybrid"  ;; 6) W_CATEGORY="modpack" ;;
  esac
}

wizard_bedrock_category() {
  clear_screen; header; breadcrumb "Bedrock Edition"
  section "Schritt 2 von 5  —  Bedrock Server-Software"; echo ""
  opt 1 "PocketMine-MP" "PHP-basierter Bedrock-Server"
  opt 2 "Nukkit"        "Java-basierter Bedrock-Server"
  opt 3 "PowerNukkit"   "Erweiterter Nukkit-Fork"
  opt 4 "WaterdogPE"    "Bedrock Proxy-Server"
  echo ""; prompt "Wähle die Server-Software" 1 4
  case "$CHOICE" in
    1) W_CATEGORY="bedrock"; W_DIST="pocketmine"  ;;
    2) W_CATEGORY="bedrock"; W_DIST="nukkit"      ;;
    3) W_CATEGORY="bedrock"; W_DIST="powernukkit" ;;
    4) W_CATEGORY="bedrock"; W_DIST="waterdogpe"  ;;
  esac
}

wizard_distribution() {
  clear_screen; header
  case "$W_CATEGORY" in
    proxy)
      breadcrumb "Java Edition > Proxy"
      section "Schritt 3 von 5  —  Proxy-Software"; echo ""
      opt 1 "Velocity"   "Moderner, hochperformanter Proxy — empfohlen"
      opt 2 "Waterfall"  "Stabiler Paper-Fork von BungeeCord"
      opt 3 "BungeeCord" "Der klassische Minecraft-Proxy"
      echo ""; prompt "Wähle den Proxy" 1 3
      case "$CHOICE" in 1) W_DIST="velocity" ;; 2) W_DIST="waterfall" ;; 3) W_DIST="bungeecord" ;; esac
      ;;
    plugin)
      breadcrumb "Java Edition > Plugin-Server"
      section "Schritt 3 von 5  —  Plugin-Server"; echo ""
      opt 1 "Paper"      "Schnellster Spigot-Fork — empfohlen"
      opt 2 "Purpur"     "Paper-Fork mit Extra-Konfigurationen"
      opt 3 "Pufferfish" "Hochoptimierter Paper-Fork"
      opt 4 "Folia"      "Paper mit Multithreading (experimentell)"
      opt 5 "Leaves"     "Feature-reicher Paper-Fork"
      opt 6 "Spigot"     "Klassischer Plugin-Server (BuildTools)"
      echo ""; prompt "Wähle den Plugin-Server" 1 6
      case "$CHOICE" in
        1) W_DIST="paper"      ;; 2) W_DIST="purpur"     ;;
        3) W_DIST="pufferfish" ;; 4) W_DIST="folia"      ;;
        5) W_DIST="leaves"     ;; 6) W_DIST="spigot"     ;;
      esac
      ;;
    modded)
      breadcrumb "Java Edition > Mod-Server"
      section "Schritt 3 von 5  —  Mod-Loader"; echo ""
      opt 1 "NeoForge" "Moderner Forge-Fork — empfohlen für 1.20+"
      opt 2 "Forge"    "Der klassische Mod-Loader"
      opt 3 "Fabric"   "Leichtgewichtig, schnelle Updates"
      opt 4 "Quilt"    "Community-Fork von Fabric"
      opt 5 "Sponge"   "SpongeVanilla"
      echo ""; prompt "Wähle den Mod-Loader" 1 5
      case "$CHOICE" in
        1) W_DIST="neoforge" ;; 2) W_DIST="forge"  ;;
        3) W_DIST="fabric"   ;; 4) W_DIST="quilt"  ;;
        5) W_DIST="sponge"   ;;
      esac
      ;;
    hybrid)
      breadcrumb "Java Edition > Hybrid-Server"
      section "Schritt 3 von 5  —  Hybrid-Software"; echo ""
      opt 1 "Mohist"    "Forge + Bukkit-API"
      opt 2 "Arclight"  "Forge/Fabric + Bukkit, aktiv entwickelt"
      opt 3 "CatServer" "Forge + Bukkit (ältere MC-Versionen)"
      echo ""; prompt "Wähle den Hybrid-Server" 1 3
      case "$CHOICE" in 1) W_DIST="mohist" ;; 2) W_DIST="arclight" ;; 3) W_DIST="catserver" ;; esac
      ;;
    modpack)
      breadcrumb "Java Edition > Modpack"
      section "Schritt 3 von 5  —  Modpack-Quelle"; echo ""
      opt 1 "CurseForge" "Modpack von CurseForge"
      opt 2 "Modrinth"   "Modpack von Modrinth (.mrpack)"
      echo ""; prompt "Wähle die Modpack-Quelle" 1 2
      case "$CHOICE" in 1) W_DIST="curseforge" ;; 2) W_DIST="modrinth" ;; esac
      ;;
  esac
}

wizard_version() {
  clear_screen; header
  case "$W_DIST" in
    bungeecord|pocketmine|nukkit|powernukkit|waterdogpe)
      W_VERSION="latest"; W_BUILD="latest"; return ;;
    curseforge|modrinth)
      wizard_modpack_input; return ;;
  esac

  breadcrumb "Java Edition > ${W_DIST^}"
  section "Schritt 4 von 5  —  Minecraft-Version"; echo ""
  info "Bekannte Versionen: 1.21.4  •  1.21.1  •  1.20.4  •  1.20.1  •  1.19.4  •  1.16.5"
  echo -e "  ${DIM}Eingabe ${C}latest${DIM} für die neueste Version.${NC}"; echo ""
  prompt_text "Minecraft-Version" "latest"
  W_VERSION="$TEXT_INPUT"

  case "$W_DIST" in
    paper|folia|waterfall|velocity|leaves)
      clear_screen; header; breadcrumb "Java Edition > ${W_DIST^} > MC ${W_VERSION}"
      section "Schritt 4b von 5  —  Build-Nummer"; echo ""
      info "Eingabe ${C}latest${NC} für den aktuellen Build."; echo ""
      prompt_text "Build-Nummer" "latest"; W_BUILD="$TEXT_INPUT" ;;
    forge|neoforge)
      clear_screen; header; breadcrumb "Java Edition > ${W_DIST^} > MC ${W_VERSION}"
      section "Schritt 4b von 5  —  ${W_DIST^}-Version"; echo ""
      info "Eingabe ${C}latest${NC} für die empfohlene Version."; echo ""
      prompt_text "${W_DIST^}-Version" "latest"; W_BUILD="$TEXT_INPUT" ;;
    fabric|quilt)
      clear_screen; header; breadcrumb "Java Edition > ${W_DIST^} > MC ${W_VERSION}"
      section "Schritt 4b von 5  —  Loader-Version"; echo ""
      info "Eingabe ${C}latest${NC} für die neueste Version."; echo ""
      prompt_text "${W_DIST^} Loader-Version" "latest"; W_BUILD="$TEXT_INPUT" ;;
    *) W_BUILD="latest" ;;
  esac
}

wizard_modpack_input() {
  clear_screen; header
  if [ "$W_DIST" = "curseforge" ]; then
    breadcrumb "Java Edition > Modpack > CurseForge"
    section "Schritt 4 von 5  —  CurseForge Modpack"; echo ""
    info "Download-URL zur .zip  oder  projektID:dateiID"; echo ""
    prompt_text "CurseForge URL oder 'projektID:dateiID'"; W_CF_INPUT="$TEXT_INPUT"; echo ""
    info "API Key von console.curseforge.com (optional)"; echo ""
    prompt_text "CurseForge API Key (Enter zum Überspringen)"; W_CF_KEY="$TEXT_INPUT"
  else
    breadcrumb "Java Edition > Modpack > Modrinth"
    section "Schritt 4 von 5  —  Modrinth Modpack"; echo ""
    info "Slug oder 'slug@version'  (z.B. adrenaserver oder adrenaserver@1.2.0)"; echo ""
    prompt_text "Modrinth Slug"; W_MR_INPUT="$TEXT_INPUT"
  fi
  W_VERSION="auto"; W_BUILD="auto"
}

wizard_confirm() {
  clear_screen; header
  section "Schritt 5 von 5  —  Zusammenfassung & Bestätigung"; echo ""
  echo -e "  ${W}${BOLD}Deine Konfiguration:${NC}"; echo ""
  echo -e "    ${DIM}Platform     :${NC}  ${W}${W_PLATFORM^}${NC}"
  [ -n "$W_CATEGORY" ] && echo -e "    ${DIM}Kategorie    :${NC}  ${W}${W_CATEGORY^}${NC}"
  echo -e "    ${DIM}Distribution :${NC}  ${W}${W_DIST^}${NC}"
  [ "$W_VERSION" != "auto" ] && echo -e "    ${DIM}MC-Version   :${NC}  ${W}${W_VERSION}${NC}"
  [ "$W_BUILD" != "latest" ] && [ "$W_BUILD" != "auto" ] && echo -e "    ${DIM}Build/Loader :${NC}  ${W}${W_BUILD}${NC}"
  [ -n "$W_CF_INPUT" ] && echo -e "    ${DIM}CurseForge   :${NC}  ${W}${W_CF_INPUT}${NC}"
  [ -n "$W_MR_INPUT" ] && echo -e "    ${DIM}Modrinth     :${NC}  ${W}${W_MR_INPUT}${NC}"
  echo -e "    ${DIM}RAM          :${NC}  ${W}${SERVER_MEMORY} MB${NC}"; echo ""

  local needs_eula=true
  case "$W_DIST" in velocity|waterfall|bungeecord|waterdogpe) needs_eula=false ;; esac

  if $needs_eula && [ "$EULA" != "true" ]; then
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"; echo ""
    warn "Du musst die Mojang EULA akzeptieren."
    info "EULA: ${C}https://aka.ms/MinecraftEULA${NC}"
    prompt_yesno "Akzeptierst du die Mojang EULA?"
    W_EULA=$YESNO
    $W_EULA || { err "EULA nicht akzeptiert."; exit 1; }
  else
    W_EULA=true
  fi

  echo ""; echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  prompt_yesno "Konfiguration bestätigen und Installation starten?"
  $YESNO || { warn "Abgebrochen."; exit 0; }
}

# ════════════════════════════════════════════════════════════
#  INSTALLER  (nur curl + jq)
# ════════════════════════════════════════════════════════════

install_vanilla() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && W_VERSION=$(get_latest_mc_version)
  info "Vanilla ${W_VERSION}"
  download_file "$(get_mc_server_url "$W_VERSION")" "/home/container/server.jar" "Vanilla ${W_VERSION}"
}

install_paper() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && \
    W_VERSION=$(curl -sSL "https://api.papermc.io/v2/projects/paper" | jq -r '.versions[-1]')
  ( [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] ) && \
    W_BUILD=$(curl -sSL "https://api.papermc.io/v2/projects/paper/versions/${W_VERSION}" | jq -r '.builds[-1]')
  info "Paper ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.papermc.io/v2/projects/paper/versions/${W_VERSION}/builds/${W_BUILD}/downloads/paper-${W_VERSION}-${W_BUILD}.jar" \
    "/home/container/server.jar" "Paper"
}

install_purpur() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && \
    W_VERSION=$(curl -sSL "https://api.purpurmc.org/v2/purpur" | jq -r '.versions[-1]')
  info "Purpur ${W_VERSION}"
  download_file "https://api.purpurmc.org/v2/purpur/${W_VERSION}/latest/download" \
    "/home/container/server.jar" "Purpur ${W_VERSION}"
}

install_folia() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && \
    W_VERSION=$(curl -sSL "https://api.papermc.io/v2/projects/folia" | jq -r '.versions[-1]')
  ( [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] ) && \
    W_BUILD=$(curl -sSL "https://api.papermc.io/v2/projects/folia/versions/${W_VERSION}" | jq -r '.builds[-1]')
  info "Folia ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.papermc.io/v2/projects/folia/versions/${W_VERSION}/builds/${W_BUILD}/downloads/folia-${W_VERSION}-${W_BUILD}.jar" \
    "/home/container/server.jar" "Folia"
}

install_pufferfish() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && W_VERSION=$(get_latest_mc_version)
  info "Pufferfish ${W_VERSION}"
  local ci_base="https://ci.pufferfish.host/job/Pufferfish-${W_VERSION}/lastSuccessfulBuild/artifact/build/libs/"
  local jar_file
  jar_file=$(curl -sSL "$ci_base" | grep -oP 'href="[^"]*pufferfish[^"]*\.jar"' | head -1 | tr -d '"' | sed 's/href=//')
  if [ -n "$jar_file" ]; then
    download_file "${ci_base}${jar_file}" "/home/container/server.jar" "Pufferfish ${W_VERSION}"
  else
    warn "Pufferfish CI nicht erreichbar — Paper als Fallback."
    install_paper
  fi
}

install_leaves() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && \
    W_VERSION=$(curl -sSL "https://api.leavesmc.org/v2/projects/leaves" | jq -r '.versions[-1]' 2>/dev/null || echo "1.21")
  ( [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] ) && \
    W_BUILD=$(curl -sSL "https://api.leavesmc.org/v2/projects/leaves/versions/${W_VERSION}" | jq -r '.builds[-1]' 2>/dev/null || echo "latest")
  info "Leaves ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.leavesmc.org/v2/projects/leaves/versions/${W_VERSION}/builds/${W_BUILD}/downloads/leaves-${W_VERSION}-${W_BUILD}.jar" \
    "/home/container/server.jar" "Leaves"
}

install_spigot() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && W_VERSION=$(get_latest_mc_version)
  info "Baue Spigot ${W_VERSION} via BuildTools..."
  mkdir -p /tmp/spigot_build && cd /tmp/spigot_build
  download_file "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" "BuildTools.jar" "BuildTools"
  java -Xmx1G -jar BuildTools.jar --rev "$W_VERSION" --output-dir /home/container 2>&1 | tail -5
  local jar; jar=$(find /home/container -name "spigot-*.jar" | head -1)
  [ -n "$jar" ] && mv "$jar" /home/container/server.jar || { err "Spigot Build fehlgeschlagen!"; exit 1; }
  cd /home/container && rm -rf /tmp/spigot_build
}

install_velocity() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && \
    W_VERSION=$(curl -sSL "https://api.papermc.io/v2/projects/velocity" | jq -r '.versions[-1]')
  ( [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] ) && \
    W_BUILD=$(curl -sSL "https://api.papermc.io/v2/projects/velocity/versions/${W_VERSION}" | jq -r '.builds[-1]')
  info "Velocity ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.papermc.io/v2/projects/velocity/versions/${W_VERSION}/builds/${W_BUILD}/downloads/velocity-${W_VERSION}-${W_BUILD}.jar" \
    "/home/container/server.jar" "Velocity"
}

install_waterfall() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && \
    W_VERSION=$(curl -sSL "https://api.papermc.io/v2/projects/waterfall" | jq -r '.versions[-1]')
  ( [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] ) && \
    W_BUILD=$(curl -sSL "https://api.papermc.io/v2/projects/waterfall/versions/${W_VERSION}" | jq -r '.builds[-1]')
  info "Waterfall ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.papermc.io/v2/projects/waterfall/versions/${W_VERSION}/builds/${W_BUILD}/downloads/waterfall-${W_VERSION}-${W_BUILD}.jar" \
    "/home/container/server.jar" "Waterfall"
}

install_bungeecord() {
  info "BungeeCord (latest)"
  download_file "https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/artifact/bootstrap/target/BungeeCord.jar" \
    "/home/container/server.jar" "BungeeCord"
}

install_forge() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && W_VERSION=$(get_latest_mc_version)
  local forge_ver="$W_BUILD"
  if [ "$forge_ver" = "latest" ] || [ -z "$forge_ver" ]; then
    forge_ver=$(curl -sSL "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json" \
      | jq -r --arg v "$W_VERSION" '.promos[$v+"-recommended"] // .promos[$v+"-latest"] // ""')
  fi
  [ -z "$forge_ver" ] && { err "Keine Forge-Version für MC ${W_VERSION} gefunden!"; exit 1; }
  info "Forge ${W_VERSION}-${forge_ver}"
  download_file "https://maven.minecraftforge.net/net/minecraftforge/forge/${W_VERSION}-${forge_ver}/forge-${W_VERSION}-${forge_ver}-installer.jar" \
    "/home/container/forge-installer.jar" "Forge Installer"
  step "Installiere Forge (bitte warten)..."
  cd /home/container
  java -Xmx1G -jar forge-installer.jar --installServer 2>&1 | tail -10
  rm -f forge-installer.jar
  if [ -f "/home/container/run.sh" ]; then
    USE_RUN_SH=true; ok "Forge installiert. run.sh wird genutzt."
  else
    local jar; jar=$(find /home/container -name "forge-*.jar" | grep -v installer | head -1)
    [ -n "$jar" ] && cp "$jar" /home/container/server.jar || { err "Forge fehlgeschlagen!"; exit 1; }
  fi
}

install_neoforge() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && W_VERSION=$(get_latest_mc_version)
  local neo_mc="${W_VERSION#1.}"
  local neo_ver="$W_BUILD"
  if [ "$neo_ver" = "latest" ] || [ -z "$neo_ver" ]; then
    neo_ver=$(curl -sSL "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" \
      | grep -oP '<version>\K[^<]+' | grep "^${neo_mc}\." | tail -1)
  fi
  [ -z "$neo_ver" ] && { err "Keine NeoForge-Version für MC ${W_VERSION}!"; exit 1; }
  info "NeoForge ${neo_ver}"
  download_file "https://maven.neoforged.net/releases/net/neoforged/neoforge/${neo_ver}/neoforge-${neo_ver}-installer.jar" \
    "/home/container/neoforge-installer.jar" "NeoForge Installer"
  step "Installiere NeoForge (bitte warten)..."
  cd /home/container
  java -Xmx1G -jar neoforge-installer.jar --install-server /home/container 2>&1 | tail -10
  rm -f neoforge-installer.jar
  if [ -f "/home/container/run.sh" ]; then
    USE_RUN_SH=true; ok "NeoForge installiert. run.sh wird genutzt."
  else
    local jar; jar=$(find /home/container -name "neoforge-*.jar" | grep -v installer | head -1)
    [ -n "$jar" ] && cp "$jar" /home/container/server.jar
  fi
}

install_fabric() {
  if [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ]; then
    W_VERSION=$(curl -sSL "https://meta.fabricmc.net/v2/versions/game" \
      | jq -r '[.[] | select(.stable==true)][0].version')
  fi
  local lv="$W_BUILD"
  ( [ "$lv" = "latest" ] || [ -z "$lv" ] ) && lv=$(curl -sSL "https://meta.fabricmc.net/v2/versions/loader" | jq -r '.[0].version')
  local iv; iv=$(curl -sSL "https://meta.fabricmc.net/v2/versions/installer" | jq -r '.[0].version')
  info "Fabric MC ${W_VERSION} Loader ${lv}"
  download_file "https://meta.fabricmc.net/v2/versions/loader/${W_VERSION}/${lv}/${iv}/server/jar" \
    "/home/container/server.jar" "Fabric Server"
}

install_quilt() {
  if [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ]; then
    W_VERSION=$(curl -sSL "https://meta.quiltmc.org/v3/versions/game" \
      | jq -r '[.[] | select(.stable==true)][0].version // .[0].version')
  fi
  local lv="$W_BUILD"
  ( [ "$lv" = "latest" ] || [ -z "$lv" ] ) && lv=$(curl -sSL "https://meta.quiltmc.org/v3/versions/quilt-loader" | jq -r '.[0].version')
  info "Quilt MC ${W_VERSION} Loader ${lv}"
  download_file "https://quiltmc.org/api/v1/download-latest-installer/java-universal" "/home/container/quilt-installer.jar" "Quilt Installer"
  java -jar /home/container/quilt-installer.jar install server "$W_VERSION" "$lv" --download-server --install-dir=/home/container 2>&1 | tail -5
  rm -f /home/container/quilt-installer.jar
  local jar; jar=$(find /home/container -name "quilt-server-launch.jar" -o -name "quilt*.jar" 2>/dev/null | grep -v installer | head -1)
  [ -n "$jar" ] && cp "$jar" /home/container/server.jar 2>/dev/null || true
  ok "Quilt installiert."
}

install_sponge() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && W_VERSION=$(get_latest_mc_version)
  info "SpongeVanilla ${W_VERSION}"
  local dl_url
  dl_url=$(curl -sSL "https://dl-api.spongepowered.org/v2/groups/org.spongepowered/artifacts/spongevanilla/versions?tags=minecraft:${W_VERSION}&limit=1" \
    | jq -r '.artifacts[0].assets[]? | select(.extension=="jar") | .downloadUrl' 2>/dev/null | head -1)
  [ -z "$dl_url" ] && dl_url="https://repo.spongepowered.org/repository/sponge-releases/org/spongepowered/spongevanilla/${W_VERSION}-SNAPSHOT/spongevanilla-${W_VERSION}-SNAPSHOT-universal.jar"
  download_file "$dl_url" "/home/container/server.jar" "SpongeVanilla"
}

install_mohist() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && \
    W_VERSION=$(curl -sSL "https://mohistmc.com/api/v2/projects/mohist" | jq -r '.versions[-1]' 2>/dev/null || echo "1.20.1")
  local build
  build=$(curl -sSL "https://mohistmc.com/api/v2/projects/mohist/${W_VERSION}/builds" | jq -r '.builds[-1].number' 2>/dev/null || echo "latest")
  info "Mohist ${W_VERSION} Build ${build}"
  download_file "https://mohistmc.com/api/v2/projects/mohist/${W_VERSION}/builds/${build}/download" \
    "/home/container/server.jar" "Mohist"
}

install_arclight() {
  ( [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] ) && W_VERSION="1.20.1"
  info "Arclight ${W_VERSION}"
  local dl_url
  dl_url=$(curl -sSL "https://api.github.com/repos/IzzelAliz/Arclight/releases/latest" \
    | jq -r --arg v "$W_VERSION" '.assets[] | select(.name | contains($v)) | select(.name | endswith(".jar")) | .browser_download_url' | head -1)
  [ -z "$dl_url" ] && { err "Arclight JAR für ${W_VERSION} nicht gefunden!"; exit 1; }
  download_file "$dl_url" "/home/container/server.jar" "Arclight"
}

install_catserver() {
  info "CatServer (latest)"
  local dl_url
  dl_url=$(curl -sSL "https://api.github.com/repos/Luohuayu/CatServer/releases/latest" \
    | jq -r '.assets[] | select(.name | endswith(".jar")) | .browser_download_url' | head -1)
  [ -z "$dl_url" ] && dl_url="https://catmc.org/download/universal"
  download_file "$dl_url" "/home/container/server.jar" "CatServer"
}

install_pocketmine() {
  info "PocketMine-MP (latest)"
  download_file "https://github.com/pmmp/PocketMine-MP/releases/latest/download/PocketMine-MP.phar" \
    "/home/container/server.phar" "PocketMine-MP"
  echo "POCKETMINE=true" >> "$CONFIG_FILE"
}

install_nukkit() {
  info "Nukkit (latest)"
  download_file "https://ci.opencollab.dev/job/NukkitX/job/Nukkit/job/master/lastSuccessfulBuild/artifact/target/nukkit-1.0-SNAPSHOT.jar" \
    "/home/container/server.jar" "Nukkit"
}

install_powernukkit() {
  info "PowerNukkit (latest)"
  local dl_url
  dl_url=$(curl -sSL "https://api.github.com/repos/PowerNukkit/PowerNukkit/releases/latest" \
    | jq -r '.assets[] | select(.name | endswith(".jar")) | select(.name | contains("shaded")) | .browser_download_url' | head -1)
  [ -z "$dl_url" ] && { err "PowerNukkit Download nicht gefunden!"; exit 1; }
  download_file "$dl_url" "/home/container/server.jar" "PowerNukkit"
}

install_waterdogpe() {
  info "WaterdogPE (latest)"
  download_file "https://jenkins.waterdog.dev/job/Waterdog/job/WaterdogPE/lastSuccessfulBuild/artifact/target/Waterdog.jar" \
    "/home/container/server.jar" "WaterdogPE"
}

install_curseforge_modpack() {
  local input="$W_CF_INPUT" api_key="$W_CF_KEY"
  mkdir -p /home/container/tmp_cf && cd /home/container/tmp_cf
  if [[ "$input" =~ ^https?:// ]]; then
    download_file "$input" "modpack.zip" "CurseForge Modpack"
  elif [[ "$input" =~ ^[0-9]+:[0-9]+$ ]]; then
    local pid="${input%%:*}" fid="${input##*:}"
    [ -z "$api_key" ] && { err "API Key erforderlich!"; exit 1; }
    local dl_url
    dl_url=$(curl -sSL -H "x-api-key: ${api_key}" "https://api.curseforge.com/v1/mods/${pid}/files/${fid}/download-url" | jq -r '.data')
    download_file "$dl_url" "modpack.zip" "CurseForge Modpack"
  else
    err "Ungültige CurseForge-Eingabe!"; exit 1
  fi
  step "Entpacke Modpack..."
  unzip -q modpack.zip -d content/
  local manifest; manifest=$(find content -name "manifest.json" | head -1)
  [ -z "$manifest" ] && { err "manifest.json nicht gefunden!"; exit 1; }
  local mc_ver loader_id
  mc_ver=$(jq -r '.minecraft.version' "$manifest")
  loader_id=$(jq -r '.minecraft.modLoaders[0].id // "forge"' "$manifest")
  info "MC ${mc_ver} / Loader ${loader_id}"
  W_VERSION="$mc_ver"; W_BUILD="latest"
  case "${loader_id%%[-_]*}" in
    forge) install_forge ;; neoforge) install_neoforge ;;
    fabric) install_fabric ;; quilt) install_quilt ;; *) install_vanilla ;;
  esac
  local overrides; overrides=$(find /home/container/tmp_cf/content -type d -name "overrides" | head -1)
  [ -n "$overrides" ] && cp -r "${overrides}/." /home/container/ && ok "Overrides kopiert."
  if [ -n "$api_key" ]; then
    step "Lade Mods herunter..."
    local total; total=$(jq '.files | length' "$manifest")
    local i=0
    while IFS= read -r line; do
      local pid fid
      pid=$(echo "$line" | jq -r '.projectID')
      fid=$(echo "$line" | jq -r '.fileID')
      i=$((i+1))
      local url
      url=$(curl -sSL -H "x-api-key: ${api_key}" "https://api.curseforge.com/v1/mods/${pid}/files/${fid}/download-url" | jq -r '.data // ""')
      if [ -n "$url" ]; then
        local fname; fname=$(basename "$url")
        [ ! -f "/home/container/mods/${fname}" ] && \
          curl -sSL -o "/home/container/mods/${fname}" "$url" && \
          echo "  [${i}/${total}] ${fname}"
      fi
    done < <(jq -c '.files[]' "$manifest")
    mkdir -p /home/container/mods
  else
    warn "Kein API Key — Mods manuell in /home/container/mods/ platzieren."
  fi
  cd /home/container && rm -rf /home/container/tmp_cf
}

install_modrinth_modpack() {
  local input="$W_MR_INPUT"
  local slug version
  [[ "$input" == *@* ]] && { slug="${input%%@*}"; version="${input##*@}"; } || { slug="$input"; version="latest"; }
  step "Hole Modrinth Projektinfos..."
  local project_title
  project_title=$(curl -sSL "https://api.modrinth.com/v2/project/${slug}" | jq -r '.title')
  info "Projekt: ${project_title}"
  local version_data
  if [ "$version" = "latest" ]; then
    version_data=$(curl -sSL "https://api.modrinth.com/v2/project/${slug}/version" | jq -c '.[0]')
  else
    version_data=$(curl -sSL "https://api.modrinth.com/v2/version/${version}")
  fi
  local file_url mc_ver loader
  file_url=$(echo "$version_data" | jq -r '.files[] | select(.primary==true or (.filename | endswith(".mrpack"))) | .url' | head -1)
  mc_ver=$(echo "$version_data" | jq -r '.game_versions[-1]')
  loader=$(echo "$version_data" | jq -r '.loaders[0]')
  info "MC ${mc_ver} / Loader ${loader}"
  mkdir -p /home/container/tmp_mr && cd /home/container/tmp_mr
  download_file "$file_url" "modpack.mrpack" "${project_title}"
  step "Entpacke .mrpack..."
  unzip -q modpack.mrpack -d content/ 2>/dev/null || true
  W_VERSION="$mc_ver"; W_BUILD="latest"
  case "$loader" in
    forge) install_forge ;; neoforge) install_neoforge ;;
    fabric) install_fabric ;; quilt) install_quilt ;; *) install_vanilla ;;
  esac
  if [ -f "/home/container/tmp_mr/content/modrinth.index.json" ]; then
    step "Lade Mods herunter..."
    local total; total=$(jq '.files | length' /home/container/tmp_mr/content/modrinth.index.json)
    local i=0
    while IFS= read -r line; do
      local path url
      path=$(echo "$line" | jq -r '.path')
      url=$(echo "$line" | jq -r '.downloads[0]')
      i=$((i+1))
      local dest="/home/container/${path}"
      mkdir -p "$(dirname "$dest")"
      [ ! -f "$dest" ] && curl -sSL -H "User-Agent: MultiEgg/2.0" -o "$dest" "$url" && \
        echo "  [${i}/${total}] $(basename "$path")"
    done < <(jq -c '.files[]' /home/container/tmp_mr/content/modrinth.index.json)
  fi
  for od in "overrides" "server-overrides"; do
    [ -d "/home/container/tmp_mr/content/${od}" ] && cp -r "/home/container/tmp_mr/content/${od}/." /home/container/
  done
  cd /home/container && rm -rf /home/container/tmp_mr
  ok "${project_title} installiert."
}

# ════════════════════════════════════════════════════════════
#  SERVER STARTEN
# ════════════════════════════════════════════════════════════
build_jvm_flags() {
  local mem="$SERVER_MEMORY"
  echo "-Xms${mem}M -Xmx${mem}M \
-XX:+UseG1GC -XX:+ParallelRefProcEnabled -XX:MaxGCPauseMillis=200 \
-XX:+UnlockExperimentalVMOptions -XX:+DisableExplicitGC -XX:+AlwaysPreTouch \
-XX:G1NewSizePercent=30 -XX:G1MaxNewSizePercent=40 -XX:G1HeapRegionSize=8M \
-XX:G1ReservePercent=20 -XX:G1HeapWastePercent=5 -XX:G1MixedGCCountTarget=4 \
-XX:InitiatingHeapOccupancyPercent=15 -XX:G1MixedGCLiveThresholdPercent=90 \
-XX:G1RSetUpdatingPauseTimePercent=5 -XX:SurvivorRatio=32 \
-XX:+PerfDisableSharedMem -XX:MaxTenuringThreshold=1 \
-Dusing.aikars.flags=https://mcflags.emc.gs -Daikars.new.flags=true \
${EXTRA_JVM_FLAGS}"
}

start_server() {
  load_config
  SERVER_MEMORY="${MC_MEMORY:-${SERVER_MEMORY:-1024}}"
  EULA="${MC_EULA:-${EULA:-false}}"
  echo ""
  echo -e "${G}${BOLD}  ╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${G}${BOLD}  ║         ✅  Server wird gestartet...              ║${NC}"
  printf "${G}${BOLD}  ║  Distribution : %-33s║${NC}\n" "${MC_DISTRIBUTION^^}"
  printf "${G}${BOLD}  ║  Version      : %-33s║${NC}\n" "${MC_VERSION}"
  printf "${G}${BOLD}  ║  RAM          : %-33s║${NC}\n" "${SERVER_MEMORY} MB"
  echo -e "${G}${BOLD}  ╚═══════════════════════════════════════════════════╝${NC}"
  echo ""
  [ "$EULA" = "true" ] && accept_eula
  cd /home/container
  local jvm_flags; jvm_flags=$(build_jvm_flags)
  grep -q "POCKETMINE=true" "$CONFIG_FILE" 2>/dev/null && { php /home/container/server.phar --no-wizard; return; }
  grep -q "USE_RUN_SH=true" "$CONFIG_FILE" 2>/dev/null && [ -f "/home/container/run.sh" ] && {
    chmod +x /home/container/run.sh; bash /home/container/run.sh nogui; return; }
  java ${jvm_flags} -jar /home/container/server.jar nogui
}

# ════════════════════════════════════════════════════════════
#  HAUPT-LOGIK
# ════════════════════════════════════════════════════════════
run_wizard() {
  wizard_platform
  if [ "$W_PLATFORM" = "java" ]; then
    wizard_java_category
    [ "$W_CATEGORY" = "vanilla" ] && W_DIST="vanilla" || wizard_distribution
  else
    wizard_bedrock_category
  fi
  wizard_version
  wizard_confirm
  MC_DISTRIBUTION="$W_DIST"; MC_VERSION="$W_VERSION"; MC_BUILD="$W_BUILD"
  EULA="$( $W_EULA && echo true || echo false )"
  CURSEFORGE_MODPACK="$W_CF_INPUT"; MODRINTH_MODPACK="$W_MR_INPUT"
  [ -n "$W_CF_KEY" ] && CURSEFORGE_API_KEY="$W_CF_KEY"
  save_config
}

run_install() {
  clear_screen; header
  echo -e "  ${M}${BOLD}Installation läuft...${NC}"; echo ""
  case "$MC_DISTRIBUTION" in
    vanilla)     install_vanilla              ;;
    paper)       install_paper               ;;
    purpur)      install_purpur              ;;
    folia)       install_folia               ;;
    pufferfish)  install_pufferfish          ;;
    leaves)      install_leaves              ;;
    spigot)      install_spigot              ;;
    velocity)    install_velocity            ;;
    waterfall)   install_waterfall           ;;
    bungeecord)  install_bungeecord          ;;
    forge)       install_forge               ;;
    neoforge)    install_neoforge            ;;
    fabric)      install_fabric              ;;
    quilt)       install_quilt               ;;
    sponge)      install_sponge              ;;
    mohist)      install_mohist              ;;
    arclight)    install_arclight            ;;
    catserver)   install_catserver           ;;
    curseforge)  install_curseforge_modpack  ;;
    modrinth)    install_modrinth_modpack    ;;
    pocketmine)  install_pocketmine          ;;
    nukkit)      install_nukkit              ;;
    powernukkit) install_powernukkit         ;;
    waterdogpe)  install_waterdogpe          ;;
    *) err "Unbekannte Distribution: '${MC_DISTRIBUTION}'"; exit 1 ;;
  esac
  $USE_RUN_SH && echo "USE_RUN_SH=true" >> "$CONFIG_FILE"
  echo "installed=$(date)"               > "$INSTALL_LOCK"
  echo "distribution=${MC_DISTRIBUTION}" >> "$INSTALL_LOCK"
  echo "mc_version=${MC_VERSION}"        >> "$INSTALL_LOCK"
  echo ""; ok "Installation erfolgreich!"; echo ""
}

main() {
  mkdir -p /home/container
  cd /home/container
  SERVER_MEMORY="${MC_MEMORY:-1024}"
  EULA="${MC_EULA:-false}"

  if [ "$FORCE_REINSTALL" = "true" ]; then
    warn "FORCE_REINSTALL=true — Entferne bestehende Installation..."
    rm -f /home/container/server.jar "$INSTALL_LOCK" "$CONFIG_FILE"
  fi

  if [ -f "$INSTALL_LOCK" ]; then
    load_config; start_server; exit 0
  fi

  clear_screen; header
  echo -e "  ${Y}${BOLD}Willkommen! Dieser Server wurde noch nicht eingerichtet.${NC}"; echo ""
  echo -e "  Antworte mit der ${C}Zahl${NC} der gewünschten Option + ${C}Enter${NC}."; echo ""
  echo -e "  ${DIM}Tipp: Lösche ${C}.mce_installed${DIM} um den Wizard erneut zu starten.${NC}"; echo ""
  prompt_yesno "Setup-Wizard jetzt starten?"
  $YESNO || { warn "Abgebrochen."; exit 0; }

  run_wizard
  run_install
  start_server
}

main
