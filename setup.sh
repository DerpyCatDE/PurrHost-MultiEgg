#!/bin/bash
# ============================================================
#   Minecraft Multi-Egg — Console Setup Wizard
#   Pterodactyl-kompatibel via Konsolen-Befehlszeile (stdin)
# ============================================================

# ─── Farben ─────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
B='\033[0;34m'; C='\033[0;36m'; M='\033[0;35m'
W='\033[1;37m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# ─── Pfade ───────────────────────────────────────────────────
CONFIG_FILE="/home/container/.mce_config"
INSTALL_LOCK="/home/container/.mce_installed"
USE_RUN_SH=false

# ─── Env-Variablen ───────────────────────────────────────────
SERVER_MEMORY="${MC_MEMORY:-1024}"
EXTRA_JVM_FLAGS="${EXTRA_JVM_FLAGS:-}"
FORCE_REINSTALL="${FORCE_REINSTALL:-false}"
EULA="${MC_EULA:-false}"
CURSEFORGE_API_KEY="${CURSEFORGE_API_KEY:-}"

# ─── Wizard-Ergebnis ─────────────────────────────────────────
W_PLATFORM=""; W_CATEGORY=""; W_DIST=""
W_VERSION=""; W_BUILD="latest"
W_CF_INPUT=""; W_MR_INPUT=""; W_CF_KEY=""
W_EULA=false

# ════════════════════════════════════════════════════════════
#  UI HELFER
# ════════════════════════════════════════════════════════════

clear_screen() { printf '\033[2J\033[H'; }

header() {
  echo ""
  echo -e "${B}${BOLD}  ╔══════════════════════════════════════════════════════╗${NC}"
  echo -e "${B}${BOLD}  ║       🎮  Minecraft Multi-Egg  •  Setup Wizard       ║${NC}"
  echo -e "${B}${BOLD}  ╚══════════════════════════════════════════════════════╝${NC}"
  echo ""
}

breadcrumb() {
  echo -e "  ${DIM}Pfad: ${C}$1${NC}"
  echo ""
}

section() {
  echo -e "  ${W}${BOLD}$1${NC}"
  echo -e "  ${DIM}$(printf '─%.0s' {1..52})${NC}"
}

opt() {
  local num="$1" label="$2" desc="${3:-}"
  if [ -n "$desc" ]; then
    echo -e "    ${C}[$num]${NC}  ${W}$label${NC}  ${DIM}— $desc${NC}"
  else
    echo -e "    ${C}[$num]${NC}  ${W}$label${NC}"
  fi
}

prompt() {
  # Setzt $CHOICE
  local question="$1" min="$2" max="$3"
  echo ""
  echo -e "  ${Y}❯${NC}  ${W}${question}${NC}  ${DIM}(${min}–${max})${NC}"
  echo -ne "  ${Y}»${NC} "
  CHOICE=""
  while IFS= read -r CHOICE; do
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge "$min" ] && [ "$CHOICE" -le "$max" ]; then
      break
    fi
    echo -e "  ${R}Ungültig.${NC} Bitte eine Zahl zwischen ${min} und ${max} eingeben."
    echo -ne "  ${Y}»${NC} "
  done
}

prompt_text() {
  # Setzt $TEXT_INPUT
  local question="$1" default="${2:-}"
  echo ""
  if [ -n "$default" ]; then
    echo -e "  ${Y}❯${NC}  ${W}${question}${NC}  ${DIM}(Standard: ${default})${NC}"
  else
    echo -e "  ${Y}❯${NC}  ${W}${question}${NC}"
  fi
  echo -ne "  ${Y}»${NC} "
  TEXT_INPUT=""
  IFS= read -r TEXT_INPUT
  [ -z "$TEXT_INPUT" ] && TEXT_INPUT="$default"
}

prompt_yesno() {
  # Setzt $YESNO (true/false)
  local question="$1"
  echo ""
  echo -e "  ${Y}❯${NC}  ${W}${question}${NC}  ${DIM}(j / n)${NC}"
  echo -ne "  ${Y}»${NC} "
  local ans; IFS= read -r ans
  [[ "$ans" =~ ^(j|J|ja|yes|y|Y|1)$ ]] && YESNO=true || YESNO=false
}

ok()   { echo -e "  ${G}✔${NC}  $1"; }
info() { echo -e "  ${B}ℹ${NC}  $1"; }
warn() { echo -e "  ${Y}⚠${NC}  $1"; }
err()  { echo -e "  ${R}✖${NC}  $1"; }
step() { echo -e "  ${M}→${NC}  $1"; }

# ════════════════════════════════════════════════════════════
#  DOWNLOAD / UTILS
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
    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['latest']['release'])"
}

get_mc_server_url() {
  local mc_ver="$1"
  local version_url
  version_url=$(curl -sSL "https://launchermeta.mojang.com/mc/game/version_manifest.json" | python3 -c "
import json,sys
data=json.load(sys.stdin)
for v in data['versions']:
    if v['id'] == '${mc_ver}':
        print(v['url']); break
")
  [ -z "$version_url" ] && { err "MC Version ${mc_ver} nicht gefunden!"; exit 1; }
  curl -sSL "$version_url" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['downloads']['server']['url'])"
}

accept_eula() {
  echo "eula=true" > /home/container/eula.txt
  ok "EULA akzeptiert."
}

save_config() {
  cat > "$CONFIG_FILE" << EOF
MC_DISTRIBUTION="${MC_DISTRIBUTION}"
MC_VERSION="${MC_VERSION}"
MC_BUILD="${MC_BUILD}"
CURSEFORGE_MODPACK="${CURSEFORGE_MODPACK}"
MODRINTH_MODPACK="${MODRINTH_MODPACK}"
CURSEFORGE_API_KEY="${CURSEFORGE_API_KEY}"
SERVER_MEMORY="${MC_MEMORY:-${SERVER_MEMORY}}"
EXTRA_JVM_FLAGS="${EXTRA_JVM_FLAGS}"
EULA="${MC_EULA:-${EULA}}"
EOF
}

load_config() {
  [ -f "$CONFIG_FILE" ] && source "$CONFIG_FILE"
}

# ════════════════════════════════════════════════════════════
#  WIZARD — STUFEN
# ════════════════════════════════════════════════════════════

# Stufe 1 — Platform
wizard_platform() {
  clear_screen; header
  section "Schritt 1 von 5  —  Platform auswählen"
  echo ""
  opt 1 "Minecraft: Java Edition"    "Plugin-, Mod-, Proxy- und Vanilla-Server"
  opt 2 "Minecraft: Bedrock Edition" "PocketMine, Nukkit, WaterdogPE"
  echo ""
  prompt "Wähle die Platform" 1 2
  case "$CHOICE" in
    1) W_PLATFORM="java"    ;;
    2) W_PLATFORM="bedrock" ;;
  esac
}

# Stufe 2a — Java Kategorien
wizard_java_category() {
  clear_screen; header
  breadcrumb "Java Edition"
  section "Schritt 2 von 5  —  Server-Kategorie"
  echo ""
  opt 1 "Proxy"         "Mehrere Server verbinden (Velocity, Waterfall, BungeeCord)"
  opt 2 "Vanilla"       "Offizieller Mojang Server ohne Mods oder Plugins"
  opt 3 "Plugin-Server" "Bukkit-API: Paper, Purpur, Spigot, Folia, Leaves, Pufferfish"
  opt 4 "Mod-Server"    "Mod-Loader: Forge, NeoForge, Fabric, Quilt, Sponge"
  opt 5 "Hybrid-Server" "Plugins + Mods gleichzeitig: Mohist, Arclight, CatServer"
  opt 6 "Modpack"       "Fertiges Modpack installieren (CurseForge oder Modrinth)"
  echo ""
  prompt "Wähle die Kategorie" 1 6
  case "$CHOICE" in
    1) W_CATEGORY="proxy"   ;;
    2) W_CATEGORY="vanilla" ;;
    3) W_CATEGORY="plugin"  ;;
    4) W_CATEGORY="modded"  ;;
    5) W_CATEGORY="hybrid"  ;;
    6) W_CATEGORY="modpack" ;;
  esac
}

# Stufe 2b — Bedrock Kategorien
wizard_bedrock_category() {
  clear_screen; header
  breadcrumb "Bedrock Edition"
  section "Schritt 2 von 5  —  Bedrock Server-Software"
  echo ""
  opt 1 "PocketMine-MP" "PHP-basierter Bedrock-Server mit Plugin-Unterstützung"
  opt 2 "Nukkit"        "Java-basierter Bedrock-Server mit Plugin-API"
  opt 3 "PowerNukkit"   "Erweiterter Nukkit-Fork mit mehr Block-Support"
  opt 4 "WaterdogPE"    "Bedrock Proxy-Server"
  echo ""
  prompt "Wähle die Server-Software" 1 4
  case "$CHOICE" in
    1) W_CATEGORY="bedrock"; W_DIST="pocketmine"  ;;
    2) W_CATEGORY="bedrock"; W_DIST="nukkit"      ;;
    3) W_CATEGORY="bedrock"; W_DIST="powernukkit" ;;
    4) W_CATEGORY="bedrock"; W_DIST="waterdogpe"  ;;
  esac
}

# Stufe 3 — Distribution
wizard_distribution() {
  clear_screen; header

  case "$W_CATEGORY" in

    proxy)
      breadcrumb "Java Edition > Proxy"
      section "Schritt 3 von 5  —  Proxy-Software"
      echo ""
      opt 1 "Velocity"   "Moderner, hochperformanter Proxy — empfohlen"
      opt 2 "Waterfall"  "Stabiler Paper-Fork von BungeeCord"
      opt 3 "BungeeCord" "Der klassische Minecraft-Proxy"
      echo ""
      prompt "Wähle den Proxy" 1 3
      case "$CHOICE" in
        1) W_DIST="velocity"   ;;
        2) W_DIST="waterfall"  ;;
        3) W_DIST="bungeecord" ;;
      esac
      ;;

    plugin)
      breadcrumb "Java Edition > Plugin-Server"
      section "Schritt 3 von 5  —  Plugin-Server"
      echo ""
      opt 1 "Paper"      "Schnellster Spigot-Fork, größte Community — empfohlen"
      opt 2 "Purpur"     "Paper-Fork mit vielen Extra-Konfigurationsoptionen"
      opt 3 "Pufferfish" "Hochoptimierter Paper-Fork für maximale Performance"
      opt 4 "Folia"      "Paper mit regionalem Multithreading (experimentell)"
      opt 5 "Leaves"     "Feature-reicher Paper-Fork"
      opt 6 "Spigot"     "Klassischer Plugin-Server (Kompilierung via BuildTools)"
      echo ""
      prompt "Wähle den Plugin-Server" 1 6
      case "$CHOICE" in
        1) W_DIST="paper"      ;;
        2) W_DIST="purpur"     ;;
        3) W_DIST="pufferfish" ;;
        4) W_DIST="folia"      ;;
        5) W_DIST="leaves"     ;;
        6) W_DIST="spigot"     ;;
      esac
      ;;

    modded)
      breadcrumb "Java Edition > Mod-Server"
      section "Schritt 3 von 5  —  Mod-Loader"
      echo ""
      opt 1 "NeoForge" "Moderner Forge-Fork, aktiv entwickelt — empfohlen für 1.20+"
      opt 2 "Forge"    "Der klassische und bekannteste Mod-Loader"
      opt 3 "Fabric"   "Leichtgewichtig, sehr schnelle Updates"
      opt 4 "Quilt"    "Community-Fork von Fabric mit erweiterten Features"
      opt 5 "Sponge"   "SpongeAPI auf Vanilla-Basis (SpongeVanilla)"
      echo ""
      prompt "Wähle den Mod-Loader" 1 5
      case "$CHOICE" in
        1) W_DIST="neoforge" ;;
        2) W_DIST="forge"    ;;
        3) W_DIST="fabric"   ;;
        4) W_DIST="quilt"    ;;
        5) W_DIST="sponge"   ;;
      esac
      ;;

    hybrid)
      breadcrumb "Java Edition > Hybrid-Server"
      section "Schritt 3 von 5  —  Hybrid-Software"
      echo ""
      opt 1 "Mohist"    "Forge + Bukkit-API Hybrid"
      opt 2 "Arclight"  "Forge/Fabric + Bukkit, aktiv entwickelt"
      opt 3 "CatServer" "Forge + Bukkit Hybrid (ältere MC-Versionen)"
      echo ""
      prompt "Wähle den Hybrid-Server" 1 3
      case "$CHOICE" in
        1) W_DIST="mohist"    ;;
        2) W_DIST="arclight"  ;;
        3) W_DIST="catserver" ;;
      esac
      ;;

    modpack)
      breadcrumb "Java Edition > Modpack"
      section "Schritt 3 von 5  —  Modpack-Quelle"
      echo ""
      opt 1 "CurseForge" "Modpack von CurseForge installieren"
      opt 2 "Modrinth"   "Modpack von Modrinth installieren (.mrpack)"
      echo ""
      prompt "Wähle die Modpack-Quelle" 1 2
      case "$CHOICE" in
        1) W_DIST="curseforge" ;;
        2) W_DIST="modrinth"   ;;
      esac
      ;;

  esac
}

# Stufe 4a — Version
wizard_version() {
  clear_screen; header

  # Kein Versions-Input nötig
  case "$W_DIST" in
    bungeecord|pocketmine|nukkit|powernukkit|waterdogpe)
      W_VERSION="latest"; W_BUILD="latest"; return ;;
    curseforge|modrinth)
      wizard_modpack_input; return ;;
  esac

  local bc="Java Edition > ${W_DIST^}"
  breadcrumb "$bc"
  section "Schritt 4 von 5  —  Minecraft-Version"
  echo ""
  info "Gib die gewünschte Minecraft-Version ein."
  echo ""
  echo -e "    ${DIM}Aktuelle Versionen:${NC}"
  echo -e "    ${DIM}  1.21.4  •  1.21.1  •  1.20.6  •  1.20.4  •  1.20.1${NC}"
  echo -e "    ${DIM}  1.19.4  •  1.18.2  •  1.17.1  •  1.16.5  •  1.12.2${NC}"
  echo ""
  echo -e "    ${DIM}Eingabe ${C}latest${DIM} für die neueste stabile Version.${NC}"
  echo ""
  prompt_text "Minecraft-Version" "latest"
  W_VERSION="$TEXT_INPUT"

  # Build/Loader-Version
  case "$W_DIST" in
    paper|folia|waterfall|velocity|leaves)
      clear_screen; header
      breadcrumb "Java Edition > ${W_DIST^} > MC ${W_VERSION}"
      section "Schritt 4b von 5  —  Build-Nummer"
      echo ""
      info "Paper, Folia, Velocity und Waterfall veröffentlichen nummerierte Builds."
      info "Eingabe ${C}latest${NC} für den aktuellen Build."
      echo ""
      prompt_text "Build-Nummer" "latest"
      W_BUILD="$TEXT_INPUT"
      ;;
    forge|neoforge)
      clear_screen; header
      breadcrumb "Java Edition > ${W_DIST^} > MC ${W_VERSION}"
      section "Schritt 4b von 5  —  ${W_DIST^}-Version"
      echo ""
      info "Gewünschte ${W_DIST^}-Loader-Version."
      info "Beispiel Forge: ${C}47.3.0${NC}  •  Beispiel NeoForge: ${C}21.4.10${NC}"
      info "Eingabe ${C}latest${NC} für die empfohlene Version."
      echo ""
      prompt_text "${W_DIST^}-Version" "latest"
      W_BUILD="$TEXT_INPUT"
      ;;
    fabric|quilt)
      clear_screen; header
      breadcrumb "Java Edition > ${W_DIST^} > MC ${W_VERSION}"
      section "Schritt 4b von 5  —  Loader-Version"
      echo ""
      info "${W_DIST^} Loader-Version (z.B. ${C}0.16.9${NC})."
      info "Eingabe ${C}latest${NC} für die neueste Version."
      echo ""
      prompt_text "${W_DIST^} Loader-Version" "latest"
      W_BUILD="$TEXT_INPUT"
      ;;
    *)
      W_BUILD="latest"
      ;;
  esac
}

# Stufe 4b — Modpack-Input
wizard_modpack_input() {
  clear_screen; header

  if [ "$W_DIST" = "curseforge" ]; then
    breadcrumb "Java Edition > Modpack > CurseForge"
    section "Schritt 4 von 5  —  CurseForge Modpack"
    echo ""
    info "Du hast zwei Möglichkeiten das Modpack anzugeben:"
    echo ""
    echo -e "    ${C}[A]${NC}  ${W}Download-URL${NC}"
    echo -e "         ${DIM}Direkter Link zur Modpack .zip-Datei${NC}"
    echo -e "         ${DIM}Bsp: https://mediafiles.curseforge.com/.../modpack.zip${NC}"
    echo ""
    echo -e "    ${C}[B]${NC}  ${W}Projekt-ID:Datei-ID${NC}"
    echo -e "         ${DIM}CurseForge Projekt- und Datei-ID (benötigt API Key)${NC}"
    echo -e "         ${DIM}Bsp: 123456:789012${NC}"
    echo ""
    prompt_text "CurseForge URL oder 'projektID:dateiID'"
    W_CF_INPUT="$TEXT_INPUT"

    echo ""
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    info "Ein API Key wird für den automatischen Mod-Download benötigt."
    info "Erhältlich unter: ${C}https://console.curseforge.com${NC}"
    echo ""
    prompt_text "CurseForge API Key (Enter zum Überspringen)"
    W_CF_KEY="$TEXT_INPUT"

  elif [ "$W_DIST" = "modrinth" ]; then
    breadcrumb "Java Edition > Modpack > Modrinth"
    section "Schritt 4 von 5  —  Modrinth Modpack"
    echo ""
    info "Gib den Modrinth Projekt-Slug oder die Projekt-ID ein."
    echo ""
    echo -e "    ${DIM}Beispiele:${NC}"
    echo -e "    ${C}  adrenaserver${NC}          ${DIM}→ neueste Version des Modpacks${NC}"
    echo -e "    ${C}  adrenaserver@1.2.0${NC}    ${DIM}→ bestimmte Version${NC}"
    echo ""
    echo -e "    ${DIM}Den Slug findest du in der URL:${NC}"
    echo -e "    ${DIM}modrinth.com/modpack/${C}SLUG${DIM} ← dieser Teil${NC}"
    echo ""
    prompt_text "Modrinth Slug oder 'slug@version'"
    W_MR_INPUT="$TEXT_INPUT"
  fi

  W_VERSION="auto"; W_BUILD="auto"
}

# Stufe 5 — Bestätigung & EULA
wizard_confirm() {
  clear_screen; header
  section "Schritt 5 von 5  —  Zusammenfassung & Bestätigung"
  echo ""
  echo -e "  ${W}${BOLD}Deine Konfiguration:${NC}"
  echo ""
  echo -e "    ${DIM}Platform     :${NC}  ${W}${W_PLATFORM^}${NC}"
  [ -n "$W_CATEGORY" ] && echo -e "    ${DIM}Kategorie    :${NC}  ${W}${W_CATEGORY^}${NC}"
  echo -e "    ${DIM}Distribution :${NC}  ${W}${W_DIST^}${NC}"
  [ "$W_VERSION" != "auto" ] && echo -e "    ${DIM}MC-Version   :${NC}  ${W}${W_VERSION}${NC}"
  [ "$W_BUILD" != "latest" ] && [ "$W_BUILD" != "auto" ] && echo -e "    ${DIM}Build/Loader :${NC}  ${W}${W_BUILD}${NC}"
  [ -n "$W_CF_INPUT" ] && echo -e "    ${DIM}CurseForge   :${NC}  ${W}${W_CF_INPUT}${NC}"
  [ -n "$W_MR_INPUT" ] && echo -e "    ${DIM}Modrinth     :${NC}  ${W}${W_MR_INPUT}${NC}"
  echo -e "    ${DIM}RAM          :${NC}  ${W}${SERVER_MEMORY} MB${NC}"
  echo ""

  # EULA
  local needs_eula=true
  case "$W_DIST" in velocity|waterfall|bungeecord|waterdogpe) needs_eula=false ;; esac

  if $needs_eula && [ "$MC_EULA" != "true" ]; then
    echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    warn "Du musst die Mojang EULA akzeptieren um den Server zu starten."
    info "EULA lesen: ${C}https://aka.ms/MinecraftEULA${NC}"
    prompt_yesno "Akzeptierst du die Mojang EULA?"
    W_EULA=$YESNO
    if ! $W_EULA; then
      err "EULA nicht akzeptiert. Installation abgebrochen."
      exit 1
    fi
  else
    W_EULA=true
  fi

  echo ""
  echo -e "  ${DIM}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  prompt_yesno "Konfiguration bestätigen und Installation starten?"
  if ! $YESNO; then
    warn "Abgebrochen. Starte den Server neu um den Wizard erneut zu starten."
    exit 0
  fi
}

# ════════════════════════════════════════════════════════════
#  INSTALLER
# ════════════════════════════════════════════════════════════

install_vanilla() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(get_latest_mc_version)
  info "Vanilla ${W_VERSION}"
  download_file "$(get_mc_server_url "$W_VERSION")" "/home/container/server.jar" "Vanilla ${W_VERSION}"
}

install_paper() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(curl -sSL "https://api.papermc.io/v2/projects/paper" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['versions'][-1])")
  [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] && W_BUILD=$(curl -sSL "https://api.papermc.io/v2/projects/paper/versions/${W_VERSION}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['builds'][-1])")
  info "Paper ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.papermc.io/v2/projects/paper/versions/${W_VERSION}/builds/${W_BUILD}/downloads/paper-${W_VERSION}-${W_BUILD}.jar" "/home/container/server.jar" "Paper"
}

install_purpur() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(curl -sSL "https://api.purpurmc.org/v2/purpur" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['versions'][-1])")
  info "Purpur ${W_VERSION}"
  download_file "https://api.purpurmc.org/v2/purpur/${W_VERSION}/latest/download" "/home/container/server.jar" "Purpur ${W_VERSION}"
}

install_folia() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(curl -sSL "https://api.papermc.io/v2/projects/folia" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['versions'][-1])")
  [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] && W_BUILD=$(curl -sSL "https://api.papermc.io/v2/projects/folia/versions/${W_VERSION}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['builds'][-1])")
  info "Folia ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.papermc.io/v2/projects/folia/versions/${W_VERSION}/builds/${W_BUILD}/downloads/folia-${W_VERSION}-${W_BUILD}.jar" "/home/container/server.jar" "Folia"
}

install_pufferfish() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(get_latest_mc_version)
  info "Pufferfish ${W_VERSION}"
  local ci_base="https://ci.pufferfish.host/job/Pufferfish-${W_VERSION}/lastSuccessfulBuild/artifact/build/libs/"
  local jar_file
  jar_file=$(curl -sSL "$ci_base" | grep -oP 'href="[^"]*pufferfish[^"]*\.jar"' | head -1 | tr -d '"' | sed 's/href=//')
  if [ -n "$jar_file" ]; then
    download_file "${ci_base}${jar_file}" "/home/container/server.jar" "Pufferfish ${W_VERSION}"
  else
    warn "Pufferfish CI nicht erreichbar — verwende Paper als Fallback."
    install_paper
  fi
}

install_leaves() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(curl -sSL "https://api.leavesmc.org/v2/projects/leaves" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['versions'][-1])" 2>/dev/null || echo "1.21")
  [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] && W_BUILD=$(curl -sSL "https://api.leavesmc.org/v2/projects/leaves/versions/${W_VERSION}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['builds'][-1])" 2>/dev/null || echo "latest")
  info "Leaves ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.leavesmc.org/v2/projects/leaves/versions/${W_VERSION}/builds/${W_BUILD}/downloads/leaves-${W_VERSION}-${W_BUILD}.jar" "/home/container/server.jar" "Leaves"
}

install_spigot() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(get_latest_mc_version)
  info "Baue Spigot ${W_VERSION} via BuildTools (kann mehrere Minuten dauern)..."
  mkdir -p /tmp/spigot_build && cd /tmp/spigot_build
  download_file "https://hub.spigotmc.org/jenkins/job/BuildTools/lastSuccessfulBuild/artifact/target/BuildTools.jar" "BuildTools.jar" "BuildTools"
  java -Xmx1G -jar BuildTools.jar --rev "$W_VERSION" --output-dir /home/container 2>&1 | tail -5
  local jar; jar=$(find /home/container -name "spigot-*.jar" | head -1)
  [ -n "$jar" ] && mv "$jar" /home/container/server.jar || { err "Spigot Build fehlgeschlagen!"; exit 1; }
  cd /home/container && rm -rf /tmp/spigot_build
}

install_velocity() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(curl -sSL "https://api.papermc.io/v2/projects/velocity" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['versions'][-1])")
  [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] && W_BUILD=$(curl -sSL "https://api.papermc.io/v2/projects/velocity/versions/${W_VERSION}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['builds'][-1])")
  info "Velocity ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.papermc.io/v2/projects/velocity/versions/${W_VERSION}/builds/${W_BUILD}/downloads/velocity-${W_VERSION}-${W_BUILD}.jar" "/home/container/server.jar" "Velocity"
}

install_waterfall() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(curl -sSL "https://api.papermc.io/v2/projects/waterfall" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['versions'][-1])")
  [ "$W_BUILD" = "latest" ] || [ -z "$W_BUILD" ] && W_BUILD=$(curl -sSL "https://api.papermc.io/v2/projects/waterfall/versions/${W_VERSION}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d['builds'][-1])")
  info "Waterfall ${W_VERSION} Build ${W_BUILD}"
  download_file "https://api.papermc.io/v2/projects/waterfall/versions/${W_VERSION}/builds/${W_BUILD}/downloads/waterfall-${W_VERSION}-${W_BUILD}.jar" "/home/container/server.jar" "Waterfall"
}

install_bungeecord() {
  info "BungeeCord (latest)"
  download_file "https://ci.md-5.net/job/BungeeCord/lastSuccessfulBuild/artifact/bootstrap/target/BungeeCord.jar" "/home/container/server.jar" "BungeeCord"
}

install_forge() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(get_latest_mc_version)
  local forge_ver="$W_BUILD"
  if [ "$forge_ver" = "latest" ]; then
    forge_ver=$(curl -sSL "https://files.minecraftforge.net/net/minecraftforge/forge/promotions_slim.json" | python3 -c "
import json,sys; d=json.load(sys.stdin); p=d.get('promos',{})
mc='${W_VERSION}'; v=p.get(mc+'-recommended') or p.get(mc+'-latest') or ''
print(v)")
  fi
  [ -z "$forge_ver" ] && { err "Keine Forge-Version für MC ${W_VERSION} gefunden!"; exit 1; }
  info "Forge ${W_VERSION}-${forge_ver}"
  download_file "https://maven.minecraftforge.net/net/minecraftforge/forge/${W_VERSION}-${forge_ver}/forge-${W_VERSION}-${forge_ver}-installer.jar" "/home/container/forge-installer.jar" "Forge Installer"
  step "Installiere Forge Server (bitte warten)..."
  cd /home/container
  java -Xmx1G -jar forge-installer.jar --installServer 2>&1 | grep -E "(Installing|Patching|Downloading|Finished|Error)" | tail -15
  rm -f forge-installer.jar
  if [ -f "/home/container/run.sh" ]; then
    USE_RUN_SH=true; ok "Forge installiert. run.sh wird beim Start genutzt."
  else
    local jar; jar=$(find /home/container -name "forge-*.jar" | grep -v installer | head -1)
    [ -n "$jar" ] && cp "$jar" /home/container/server.jar || { err "Forge Installation fehlgeschlagen!"; exit 1; }
  fi
}

install_neoforge() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(get_latest_mc_version)
  local neo_mc="${W_VERSION#1.}"
  local neo_ver="$W_BUILD"
  if [ "$neo_ver" = "latest" ]; then
    neo_ver=$(curl -sSL "https://maven.neoforged.net/releases/net/neoforged/neoforge/maven-metadata.xml" | python3 -c "
import sys,re; c=sys.stdin.read()
versions=re.findall(r'<version>([^<]+)</version>',c)
p='${neo_mc}.'; m=[v for v in versions if v.startswith(p)]
print(m[-1] if m else '')")
  fi
  [ -z "$neo_ver" ] && { err "Keine NeoForge-Version für MC ${W_VERSION} gefunden!"; exit 1; }
  info "NeoForge ${neo_ver}"
  download_file "https://maven.neoforged.net/releases/net/neoforged/neoforge/${neo_ver}/neoforge-${neo_ver}-installer.jar" "/home/container/neoforge-installer.jar" "NeoForge Installer"
  step "Installiere NeoForge Server (bitte warten)..."
  cd /home/container
  java -Xmx1G -jar neoforge-installer.jar --install-server /home/container 2>&1 | grep -E "(Installing|Patching|Downloading|Finished|NeoForge|Error)" | tail -15
  rm -f neoforge-installer.jar
  if [ -f "/home/container/run.sh" ]; then
    USE_RUN_SH=true; ok "NeoForge installiert. run.sh wird beim Start genutzt."
  else
    local jar; jar=$(find /home/container -name "neoforge-*.jar" | grep -v installer | head -1)
    [ -n "$jar" ] && cp "$jar" /home/container/server.jar
  fi
}

install_fabric() {
  if [ "$W_VERSION" = "latest" ]; then
    W_VERSION=$(curl -sSL "https://meta.fabricmc.net/v2/versions/game" | python3 -c "
import json,sys; d=json.load(sys.stdin)
s=[v['version'] for v in d if v['stable']]; print(s[0])")
  fi
  local lv="$W_BUILD"
  [ "$lv" = "latest" ] && lv=$(curl -sSL "https://meta.fabricmc.net/v2/versions/loader" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['version'])")
  local iv; iv=$(curl -sSL "https://meta.fabricmc.net/v2/versions/installer" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['version'])")
  info "Fabric MC ${W_VERSION} Loader ${lv}"
  download_file "https://meta.fabricmc.net/v2/versions/loader/${W_VERSION}/${lv}/${iv}/server/jar" "/home/container/server.jar" "Fabric Server"
}

install_quilt() {
  if [ "$W_VERSION" = "latest" ]; then
    W_VERSION=$(curl -sSL "https://meta.quiltmc.org/v3/versions/game" | python3 -c "
import json,sys; d=json.load(sys.stdin)
s=[v['version'] for v in d if v.get('stable',False)]
print(s[0] if s else d[0]['version'])")
  fi
  local lv="$W_BUILD"
  [ "$lv" = "latest" ] && lv=$(curl -sSL "https://meta.quiltmc.org/v3/versions/quilt-loader" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['version'])")
  info "Quilt MC ${W_VERSION} Loader ${lv}"
  download_file "https://quiltmc.org/api/v1/download-latest-installer/java-universal" "/home/container/quilt-installer.jar" "Quilt Installer"
  java -jar /home/container/quilt-installer.jar install server "$W_VERSION" "$lv" --download-server --install-dir=/home/container 2>&1 | tail -5
  rm -f /home/container/quilt-installer.jar
  local jar; jar=$(find /home/container -name "quilt-server-launch.jar" -o -name "quilt*.jar" 2>/dev/null | grep -v installer | head -1)
  [ -n "$jar" ] && cp "$jar" /home/container/server.jar 2>/dev/null || true
  ok "Quilt ${lv} für MC ${W_VERSION} installiert."
}

install_sponge() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(get_latest_mc_version)
  info "SpongeVanilla ${W_VERSION}"
  local dl_url
  dl_url=$(curl -sSL "https://dl-api.spongepowered.org/v2/groups/org.spongepowered/artifacts/spongevanilla/versions?tags=minecraft:${W_VERSION}&limit=1" | python3 -c "
import json,sys; d=json.load(sys.stdin)
items=d.get('artifacts',[]) or d.get('items',[])
if items:
    for a in items[0].get('assets',[]):
        if a.get('extension','')=='jar':
            print(a.get('downloadUrl','')); break" 2>/dev/null || echo "")
  [ -z "$dl_url" ] && dl_url="https://repo.spongepowered.org/repository/sponge-releases/org/spongepowered/spongevanilla/${W_VERSION}-SNAPSHOT/spongevanilla-${W_VERSION}-SNAPSHOT-universal.jar"
  download_file "$dl_url" "/home/container/server.jar" "SpongeVanilla"
}

install_mohist() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION=$(curl -sSL "https://mohistmc.com/api/v2/projects/mohist" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('versions',[])[-1])" 2>/dev/null || echo "1.20.1")
  local build
  build=$(curl -sSL "https://mohistmc.com/api/v2/projects/mohist/${W_VERSION}/builds" | python3 -c "
import json,sys; d=json.load(sys.stdin); b=d.get('builds',[])
print(b[-1].get('number','latest') if b else 'latest')" 2>/dev/null || echo "latest")
  info "Mohist ${W_VERSION} Build ${build}"
  download_file "https://mohistmc.com/api/v2/projects/mohist/${W_VERSION}/builds/${build}/download" "/home/container/server.jar" "Mohist"
}

install_arclight() {
  [ "$W_VERSION" = "latest" ] || [ -z "$W_VERSION" ] && W_VERSION="1.20.1"
  info "Arclight ${W_VERSION}"
  local dl_url
  dl_url=$(curl -sSL "https://api.github.com/repos/IzzelAliz/Arclight/releases/latest" | python3 -c "
import json,sys; d=json.load(sys.stdin); mc='${W_VERSION}'
for a in d.get('assets',[]):
    if mc in a.get('name','') and a['name'].endswith('.jar'):
        print(a['browser_download_url']); break" 2>/dev/null || echo "")
  [ -z "$dl_url" ] && { err "Arclight JAR für ${W_VERSION} nicht gefunden!"; exit 1; }
  download_file "$dl_url" "/home/container/server.jar" "Arclight"
}

install_catserver() {
  info "CatServer (latest)"
  local dl_url
  dl_url=$(curl -sSL "https://api.github.com/repos/Luohuayu/CatServer/releases/latest" | python3 -c "
import json,sys; d=json.load(sys.stdin)
for a in d.get('assets',[]):
    if a.get('name','').endswith('.jar'):
        print(a['browser_download_url']); break" 2>/dev/null || echo "https://catmc.org/download/universal")
  download_file "$dl_url" "/home/container/server.jar" "CatServer"
}

install_pocketmine() {
  info "PocketMine-MP (latest)"
  download_file "https://github.com/pmmp/PocketMine-MP/releases/latest/download/PocketMine-MP.phar" "/home/container/server.phar" "PocketMine-MP"
  echo "POCKETMINE=true" >> "$CONFIG_FILE"
}

install_nukkit() {
  info "Nukkit (latest)"
  download_file "https://ci.opencollab.dev/job/NukkitX/job/Nukkit/job/master/lastSuccessfulBuild/artifact/target/nukkit-1.0-SNAPSHOT.jar" "/home/container/server.jar" "Nukkit"
}

install_powernukkit() {
  info "PowerNukkit (latest)"
  local dl_url
  dl_url=$(curl -sSL "https://api.github.com/repos/PowerNukkit/PowerNukkit/releases/latest" | python3 -c "
import json,sys; d=json.load(sys.stdin)
for a in d.get('assets',[]):
    if a['name'].endswith('.jar') and 'shaded' in a['name']:
        print(a['browser_download_url']); break" 2>/dev/null || echo "")
  [ -z "$dl_url" ] && { err "PowerNukkit Download nicht gefunden!"; exit 1; }
  download_file "$dl_url" "/home/container/server.jar" "PowerNukkit"
}

install_waterdogpe() {
  info "WaterdogPE (latest)"
  download_file "https://jenkins.waterdog.dev/job/Waterdog/job/WaterdogPE/lastSuccessfulBuild/artifact/target/Waterdog.jar" "/home/container/server.jar" "WaterdogPE"
}

install_curseforge_modpack() {
  local input="$W_CF_INPUT" api_key="$W_CF_KEY"
  mkdir -p /home/container/tmp_cf && cd /home/container/tmp_cf

  if [[ "$input" =~ ^https?:// ]]; then
    download_file "$input" "modpack.zip" "CurseForge Modpack"
  elif [[ "$input" =~ ^[0-9]+:[0-9]+$ ]]; then
    local pid="${input%%:*}" fid="${input##*:}"
    [ -z "$api_key" ] && { err "API Key erforderlich für ID-Download!"; exit 1; }
    local dl_url
    dl_url=$(curl -sSL -H "x-api-key: ${api_key}" "https://api.curseforge.com/v1/mods/${pid}/files/${fid}/download-url" | python3 -c "import json,sys; print(json.load(sys.stdin).get('data',''))")
    download_file "$dl_url" "modpack.zip" "CurseForge Modpack"
  else
    err "Ungültige CurseForge-Eingabe!"; exit 1
  fi

  step "Entpacke Modpack..."
  unzip -q modpack.zip -d content/
  local manifest; manifest=$(find content -name "manifest.json" | head -1)
  [ -z "$manifest" ] && { err "manifest.json nicht gefunden!"; exit 1; }

  local mc_ver loader_id
  mc_ver=$(python3 -c "import json; d=json.load(open('${manifest}')); print(d['minecraft']['version'])")
  loader_id=$(python3 -c "import json; d=json.load(open('${manifest}')); loaders=d['minecraft']['modLoaders']; print(loaders[0]['id'] if loaders else 'forge')" 2>/dev/null || echo "forge")
  info "MC ${mc_ver} / Loader ${loader_id}"
  W_VERSION="$mc_ver"; W_BUILD="latest"

  case "${loader_id%%[-_]*}" in
    forge)    install_forge    ;;
    neoforge) install_neoforge ;;
    fabric)   install_fabric   ;;
    quilt)    install_quilt    ;;
    *)        install_vanilla  ;;
  esac

  local overrides; overrides=$(find /home/container/tmp_cf/content -type d -name "overrides" | head -1)
  [ -n "$overrides" ] && cp -r "${overrides}/." /home/container/ && ok "Overrides kopiert."

  if [ -n "$api_key" ]; then
    step "Lade Mods herunter..."
    python3 << PYEOF
import json, os, urllib.request
api_key = "${api_key}"
with open("${manifest}") as f:
    mf = json.load(f)
files = mf.get("files", [])
mods_dir = "/home/container/mods"
os.makedirs(mods_dir, exist_ok=True)
total = len(files)
for i, fe in enumerate(files):
    pid, fid = fe["projectID"], fe["fileID"]
    try:
        req = urllib.request.Request(f"https://api.curseforge.com/v1/mods/{pid}/files/{fid}/download-url", headers={"x-api-key": api_key})
        with urllib.request.urlopen(req, timeout=10) as r:
            url = json.loads(r.read()).get("data","")
        if url:
            fname = url.split("/")[-1]
            dest = os.path.join(mods_dir, fname)
            if not os.path.exists(dest):
                with urllib.request.urlopen(url, timeout=30) as r2:
                    open(dest,"wb").write(r2.read())
            print(f"  [{i+1}/{total}] {fname}")
    except Exception as e:
        print(f"  [SKIP] {pid}:{fid} — {e}")
PYEOF
  else
    warn "Kein API Key — Mods müssen manuell in /home/container/mods/ platziert werden."
  fi
  cd /home/container && rm -rf /home/container/tmp_cf
}

install_modrinth_modpack() {
  local input="$W_MR_INPUT"
  local slug version
  [[ "$input" == *@* ]] && { slug="${input%%@*}"; version="${input##*@}"; } || { slug="$input"; version="latest"; }

  step "Hole Modrinth Projektinfos für '${slug}'..."
  local project_data; project_data=$(curl -sSL "https://api.modrinth.com/v2/project/${slug}")
  local project_title; project_title=$(echo "$project_data" | python3 -c "import json,sys; print(json.load(sys.stdin).get('title','Modpack'))")
  info "Projekt: ${project_title}"

  local version_data
  if [ "$version" = "latest" ]; then
    version_data=$(curl -sSL "https://api.modrinth.com/v2/project/${slug}/version" | python3 -c "import json,sys; d=json.load(sys.stdin); print(json.dumps(d[0]) if d else '{}')")
  else
    version_data=$(curl -sSL "https://api.modrinth.com/v2/version/${version}")
  fi

  local file_url mc_ver loader
  file_url=$(echo "$version_data" | python3 -c "
import json,sys; d=json.load(sys.stdin)
for f in d.get('files',[]):
    if f.get('primary') or f['filename'].endswith('.mrpack'):
        print(f['url']); break" 2>/dev/null | head -1)
  mc_ver=$(echo "$version_data" | python3 -c "import json,sys; d=json.load(sys.stdin); gv=d.get('game_versions',[]); print(gv[-1] if gv else '1.21')")
  loader=$(echo "$version_data" | python3 -c "import json,sys; d=json.load(sys.stdin); l=d.get('loaders',[]); print(l[0] if l else 'fabric')")

  info "MC ${mc_ver} / Loader ${loader}"
  mkdir -p /home/container/tmp_mr && cd /home/container/tmp_mr
  download_file "$file_url" "modpack.mrpack" "${project_title}"

  step "Entpacke .mrpack..."
  unzip -q modpack.mrpack -d content/ 2>/dev/null || true
  W_VERSION="$mc_ver"; W_BUILD="latest"

  case "$loader" in
    forge)    install_forge    ;;
    neoforge) install_neoforge ;;
    fabric)   install_fabric   ;;
    quilt)    install_quilt    ;;
    *)        install_vanilla  ;;
  esac

  if [ -f "/home/container/tmp_mr/content/modrinth.index.json" ]; then
    step "Lade Mods herunter..."
    python3 << PYEOF
import json, os, urllib.request
with open("/home/container/tmp_mr/content/modrinth.index.json") as f:
    index = json.load(f)
files = index.get("files", [])
base = "/home/container"
total = len(files)
for i, fe in enumerate(files):
    urls = fe.get("downloads", []); path = fe.get("path", "")
    if not urls or not path: continue
    dest = os.path.join(base, path)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    if os.path.exists(dest): continue
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "MultiEgg/2.0"})
            with urllib.request.urlopen(req, timeout=30) as r:
                open(dest,"wb").write(r.read())
            print(f"  [{i+1}/{total}] {os.path.basename(path)}")
            break
        except Exception as e:
            print(f"  [SKIP] {os.path.basename(path)} — {e}")
PYEOF
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

  echo ""
  echo -e "${G}${BOLD}  ╔═══════════════════════════════════════════════════╗${NC}"
  echo -e "${G}${BOLD}  ║         ✅  Server wird gestartet...              ║${NC}"
  printf "${G}${BOLD}  ║  Distribution : %-33s║${NC}\n" "${MC_DISTRIBUTION^^}"
  printf "${G}${BOLD}  ║  Version      : %-33s║${NC}\n" "${MC_VERSION}"
  printf "${G}${BOLD}  ║  RAM          : %-33s║${NC}\n" "${SERVER_MEMORY} MB"
  echo -e "${G}${BOLD}  ╚═══════════════════════════════════════════════════╝${NC}"
  echo ""

  [ "$MC_EULA" = "true" ] && accept_eula
  cd /home/container

  local jvm_flags; jvm_flags=$(build_jvm_flags)

  # PocketMine
  grep -q "POCKETMINE=true" "$CONFIG_FILE" 2>/dev/null && { php /home/container/server.phar --no-wizard; return; }

  # Forge / NeoForge run.sh
  grep -q "USE_RUN_SH=true" "$CONFIG_FILE" 2>/dev/null && [ -f "/home/container/run.sh" ] && {
    chmod +x /home/container/run.sh
    bash /home/container/run.sh nogui
    return
  }

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

  # Ergebnisse in Config-Variablen übertragen
  MC_DISTRIBUTION="$W_DIST"
  MC_VERSION="$W_VERSION"
  MC_BUILD="$W_BUILD"
  EULA="$( $W_EULA && echo true || echo false )"
  CURSEFORGE_MODPACK="$W_CF_INPUT"
  MODRINTH_MODPACK="$W_MR_INPUT"
  [ -n "$W_CF_KEY" ] && CURSEFORGE_API_KEY="$W_CF_KEY"
  save_config
}

run_install() {
  clear_screen; header
  echo -e "  ${M}${BOLD}Installation läuft...${NC}"
  echo ""

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

  echo "installed=$(date)"           > "$INSTALL_LOCK"
  echo "distribution=${MC_DISTRIBUTION}" >> "$INSTALL_LOCK"
  echo "mc_version=${MC_VERSION}"    >> "$INSTALL_LOCK"

  echo ""
  ok "Installation erfolgreich abgeschlossen!"
  echo ""
}

main() {
  mkdir -p /home/container
  cd /home/container

  if [ "$FORCE_REINSTALL" = "true" ]; then
    warn "FORCE_REINSTALL=true — Entferne bestehende Installation..."
    rm -f /home/container/server.jar "$INSTALL_LOCK" "$CONFIG_FILE"
  fi

  if [ -f "$INSTALL_LOCK" ]; then
    load_config
    start_server
    exit 0
  fi

  # Begrüßung
  clear_screen; header
  echo -e "  ${Y}${BOLD}Willkommen! Dieser Server wurde noch nicht eingerichtet.${NC}"
  echo ""
  echo -e "  Der Setup-Wizard führt dich Schritt für Schritt durch die"
  echo -e "  Konfiguration. Antworte jeweils mit der ${C}Zahl${NC} der gewünschten"
  echo -e "  Option und bestätige mit ${C}Enter${NC}."
  echo ""
  echo -e "  ${DIM}Tipp: Lösche ${C}.mce_installed${DIM} um den Wizard erneut zu starten.${NC}"
  echo ""
  prompt_yesno "Setup-Wizard jetzt starten?"
  if ! $YESNO; then
    warn "Abgebrochen. Starte den Server neu um den Wizard zu öffnen."
    exit 0
  fi

  run_wizard
  run_install
  start_server
}

main
