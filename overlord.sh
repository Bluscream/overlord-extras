#!/usr/bin/env bash
# ==============================================================================
# overlord.sh — Unified Launcher, Version Switcher, IPC CLI & Manager for Overlord VR
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
REPO_DIR="$(cd "$(dirname "${REAL_SCRIPT}")" && pwd -P)"
GAME_DIR="${GAME_DIR:-/run/media/blu/WinData/Games/Battle.net/Call of Duty Modern Warfare 2 (2019)/Call of Duty Modern Warfare 2 Campaign Remastered}"

# Upstream repository for Overlord VR releases
UPSTREAM_REPO="Aeka0/Overlord"
CACHE_DIR="${HOME}/.cache/overlord-switcher"

# Overlord IPC paths
H2_MOD_DIR="${GAME_DIR}/h2-mod"
IPC_IN="${H2_MOD_DIR}/ipc_in.txt"
IPC_TMP="${H2_MOD_DIR}/ipc_in.tmp"
IPC_OUT="${H2_MOD_DIR}/ipc_out.txt"
IPC_TIMEOUT_SEC=3

# Steam shortcut specifics
STEAM_SHORTCUT_ID="17596034734578728960"
STEAM_APPID="4096896093"
STEAM_USERDATA_VDF="${HOME}/.local/share/Steam/userdata/62180933/config/shortcuts.vdf"
STEAM_CONFIG_VDF="${HOME}/.local/share/Steam/config/config.vdf"
DESKTOP_ENTRY="${HOME}/Desktop/Call of Duty Modern Warfare 2 (2019) VR.desktop"

# Formatting helpers
log_info() {
  printf "[\033[1;34mINFO\033[0m] %s\n" "$*"
}

log_success() {
  printf "[\033[1;32mOK\033[0m] %s\n" "$*"
}

log_warn() {
  printf "[\033[1;33mWARN\033[0m] %s\n" "$*" >&2
}

log_error() {
  printf "[\033[1;31mERROR\033[0m] %s\n" "$*" >&2
}

die() {
  log_error "$*"
  exit 1
}

# ==============================================================================
# Helper Functions: Process Detection
# ==============================================================================
get_game_pids() {
  # Use pgrep -ax as per guidelines (never bare pgrep -f)
  pgrep -ax "overlord.exe|MW2CR.exe" || true
}

is_game_running() {
  local pids
  pids="$(get_game_pids)"
  [[ -n "${pids}" ]]
}

# ==============================================================================
# Feature: Deployment to Game Directory
# ==============================================================================
deploy_extras() {
  log_info "Deploying Overlord Extras to game directory: ${GAME_DIR}"
  [[ -d "${GAME_DIR}" ]] || die "Game directory not found at '${GAME_DIR}'"

  mkdir -p "${GAME_DIR}/h2-mod/ui_scripts" \
           "${GAME_DIR}/h2-mod/scripts"

  # Deploy UI scripts (overlord_extras, agent_ipc, cheats)
  if [[ -d "${REPO_DIR}/h2-mod/ui_scripts/overlord_extras" ]]; then
    mkdir -p "${GAME_DIR}/h2-mod/ui_scripts/overlord_extras"
    cp -rf "${REPO_DIR}/h2-mod/ui_scripts/overlord_extras/." "${GAME_DIR}/h2-mod/ui_scripts/overlord_extras/"
  fi

  if [[ -d "${REPO_DIR}/h2-mod/ui_scripts/agent_ipc" ]]; then
    mkdir -p "${GAME_DIR}/h2-mod/ui_scripts/agent_ipc"
    cp -rf "${REPO_DIR}/h2-mod/ui_scripts/agent_ipc/." "${GAME_DIR}/h2-mod/ui_scripts/agent_ipc/"
  fi

  if [[ -d "${REPO_DIR}/h2-mod/ui_scripts/cheats" ]]; then
    mkdir -p "${GAME_DIR}/h2-mod/ui_scripts/cheats"
    cp -rf "${REPO_DIR}/h2-mod/ui_scripts/cheats/." "${GAME_DIR}/h2-mod/ui_scripts/cheats/"
  fi

  # Deploy scripts (GSC actors, etc.)
  if [[ -d "${REPO_DIR}/h2-mod/scripts" ]]; then
    cp -rf "${REPO_DIR}/h2-mod/scripts/." "${GAME_DIR}/h2-mod/scripts/"
  fi

  # Symlink launcher script into game dir for convenience
  ln -sf "${REAL_SCRIPT}" "${GAME_DIR}/overlord.sh"

  log_success "Overlord Extras successfully deployed."
}

# ==============================================================================
# Feature: Version Switcher
# ==============================================================================
check_extract_deps() {
  local missing=()
  for cmd in curl jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done

  if ! command -v 7z >/dev/null 2>&1 && ! command -v 7za >/dev/null 2>&1 && ! command -v bsdtar >/dev/null 2>&1; then
    missing+=("7z/bsdtar")
  fi

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required utilities for version switching: ${missing[*]}"
  fi
}

fetch_releases_json() {
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/${UPSTREAM_REPO}/releases" 2>/dev/null || curl -sSL "https://api.github.com/repos/${UPSTREAM_REPO}/releases"
  else
    curl -sSL "https://api.github.com/repos/${UPSTREAM_REPO}/releases"
  fi
}

get_current_version() {
  local ver_file="${GAME_DIR}/version.json"
  if [[ -f "$ver_file" ]]; then
    jq -r '"\(.name) (file_version: \(.file_version | join(".")))"' "$ver_file" 2>/dev/null || echo "Unknown (malformed version.json)"
  else
    echo "None detected (version.json missing)"
  fi
}

list_versions() {
  check_extract_deps
  log_info "Fetching releases for ${UPSTREAM_REPO}..."
  local releases_json
  releases_json="$(fetch_releases_json)"

  printf "\n%-16s %-22s %-12s\n" "TAG" "NAME" "PRERELEASE"
  printf "%-16s %-22s %-12s\n" "----------------" "----------------------" "------------"
  echo "$releases_json" | jq -r '.[] | "\(.tag_name)\t\(.name)\t\(.prerelease)"' | while IFS=$'\t' read -r tag name pre; do
    printf "%-16s %-22s %-12s\n" "$tag" "$name" "$pre"
  done
  printf "\nCurrent active version: %s\n\n" "$(get_current_version)"
}

extract_archive() {
  local archive="$1"
  local dest="$2"

  if command -v 7z >/dev/null 2>&1; then
    7z x -y -o"$dest" "$archive" >/dev/null
  elif command -v 7za >/dev/null 2>&1; then
    7za x -y -o"$dest" "$archive" >/dev/null
  elif command -v bsdtar >/dev/null 2>&1; then
    bsdtar -xf "$archive" -C "$dest"
  else
    die "No suitable extractor found (7z, 7za, or bsdtar required)."
  fi
}

install_version() {
  local target_tag="$1"
  check_extract_deps
  log_info "Target release: ${target_tag}"

  mkdir -p "${CACHE_DIR}"

  log_info "Fetching release metadata for ${target_tag}..."
  local release_info
  if command -v gh >/dev/null 2>&1; then
    release_info="$(gh api "repos/${UPSTREAM_REPO}/releases/tags/${target_tag}" 2>/dev/null || curl -sSL "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${target_tag}")"
  else
    release_info="$(curl -sSL "https://api.github.com/repos/${UPSTREAM_REPO}/releases/tags/${target_tag}")"
  fi

  local asset_url
  local asset_name
  asset_url="$(echo "$release_info" | jq -r '.assets[] | select(.name | test("(?i)\\.7z$")) | .browser_download_url' | head -n 1)"
  asset_name="$(echo "$release_info" | jq -r '.assets[] | select(.name | test("(?i)\\.7z$")) | .name' | head -n 1)"

  if [[ -z "$asset_url" || "$asset_url" == "null" ]]; then
    die "No .7z release asset found for release tag '${target_tag}'."
  fi

  local cached_archive="${CACHE_DIR}/${target_tag}-${asset_name}"
  if [[ -f "$cached_archive" ]]; then
    log_info "Using cached archive: ${cached_archive}"
  else
    log_info "Downloading ${asset_name} from ${asset_url}..."
    curl -fSL -o "${cached_archive}.tmp" "$asset_url"
    mv "${cached_archive}.tmp" "$cached_archive"
    log_success "Download completed and cached."
  fi

  local extract_tmp
  extract_tmp="$(mktemp -d -p "${CACHE_DIR}" "extract-${target_tag}-XXXXXX")"
  trap 'rm -rf "${extract_tmp}"' EXIT

  log_info "Extracting ${asset_name}..."
  extract_archive "$cached_archive" "$extract_tmp"

  # Upstream archives are often packaged with a top-level directory (e.g. "Beta 2" or "Beta 4")
  local source_dir="${extract_tmp}"
  local subdirs=()
  while IFS= read -r -d '' d; do
    subdirs+=("$d")
  done < <(find "${extract_tmp}" -mindepth 1 -maxdepth 1 -type d -print0)

  local file_count
  file_count="$(find "${extract_tmp}" -mindepth 1 -maxdepth 1 -type f | wc -l)"

  if [[ ${#subdirs[@]} -eq 1 && $file_count -eq 0 ]]; then
    source_dir="${subdirs[0]}"
    log_info "Unwrapping archive root directory: $(basename "${source_dir}")"
  fi

  log_info "Deploying Overlord binaries to game directory (${GAME_DIR})..."
  cp -rf "${source_dir}/." "${GAME_DIR}/"

  rm -rf "${extract_tmp}"
  trap - EXIT

  # Re-deploy extras over the new release
  deploy_extras

  log_success "Overlord successfully switched to ${target_tag}!"
  log_info "Current active version: $(get_current_version)"
}

prompt_interactive_switch() {
  check_extract_deps
  log_info "Fetching releases list from ${UPSTREAM_REPO}..."
  local releases_json
  releases_json="$(fetch_releases_json)"

  local tags=()
  local names=()
  while IFS=$'\t' read -r tag name; do
    tags+=("$tag")
    names+=("$name")
  done < <(echo "$releases_json" | jq -r '.[] | "\(.tag_name)\t\(.name)"')

  if [[ ${#tags[@]} -eq 0 ]]; then
    die "No releases found on GitHub repository ${UPSTREAM_REPO}."
  fi

  printf "\nCurrent active version: %s\n\n" "$(get_current_version)"
  printf "Available Overlord versions:\n"
  for i in "${!tags[@]}"; do
    printf "  [%d] %-16s (%s)\n" "$((i + 1))" "${tags[i]}" "${names[i]}"
  done
  printf "\n"

  local choice
  while true; do
    read -r -p "Select a version to install [1-${#tags[@]}] (or 'q' to quit): " choice
    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
      log_info "Aborted."
      exit 0
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#tags[@]})); then
      local selected_tag="${tags[$((choice - 1))]}"
      install_version "$selected_tag"
      break
    else
      log_warn "Invalid selection. Please enter a number between 1 and ${#tags[@]}."
    fi
  done
}

# ==============================================================================
# Feature: Agent IPC CLI
# ==============================================================================
ipc_send_and_wait() {
  local payload="$1"
  local req_id
  req_id="$(date +%s%N | cut -b1-13)-$RANDOM"

  local full_payload="id: ${req_id}
${payload}"

  rm -f "${IPC_OUT}" 2>/dev/null || true

  # Atomic write
  printf "%s\n" "${full_payload}" > "${IPC_TMP}"
  mv -f "${IPC_TMP}" "${IPC_IN}"

  local start_time
  start_time=$(date +%s)
  local deadline=$((start_time + IPC_TIMEOUT_SEC))

  while [[ $(date +%s) -le ${deadline} ]]; do
    if [[ -f "${IPC_OUT}" ]]; then
      if grep -q "id: ${req_id}" "${IPC_OUT}" 2>/dev/null; then
        local status
        status=$(grep "^status:" "${IPC_OUT}" | awk '{print $2}')
        sed -n '/^output:/,$ p' "${IPC_OUT}" | sed '1d'

        if [[ "${status}" == "ok" ]]; then
          return 0
        else
          return 2
        fi
      fi
    fi
    sleep 0.05
  done

  log_error "Timeout waiting for Overlord IPC response (${IPC_TIMEOUT_SEC}s). Is the game running?"
  rm -f "${IPC_IN}" 2>/dev/null || true
  return 1
}

run_ipc_interactive() {
  echo "=== Overlord Interactive IPC Shell ==="
  echo "Type commands to execute in game. Prefix with 'lua: ' or 'eval: ' for Lua code."
  echo "Type 'exit' or 'quit' or Ctrl+D to leave."
  echo "----------------------------------------"
  while IFS= read -r -p "overlord> " line; do
    [[ -z "${line}" ]] && continue
    [[ "${line}" == "exit" || "${line}" == "quit" ]] && break
    ipc_send_and_wait "${line}" || true
  done
}

# ==============================================================================
# Feature: Game Launch, Stop, Kill
# ==============================================================================
launch_game() {
  if is_game_running; then
    log_warn "Overlord / MW2CR is already running:"
    get_game_pids
    return 0
  fi

  [[ -f "${GAME_DIR}/overlord.exe" ]] || die "overlord.exe not found in '${GAME_DIR}'. Run './overlord.sh switch' to install a version first."

  # Ensure extras are deployed
  deploy_extras

  # Environment setup for OpenXR, WiVRn & Proton
  export PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1
  export PRESSURE_VESSEL_FILESYSTEMS_RW="/var/lib/flatpak/app/io.github.wivrn.wivrn"
  export STEAM_COMPAT_DATA_PATH="${STEAM_COMPAT_DATA_PATH:-${HOME}/.local/share/Steam/steamapps/compatdata/NonSteamLaunchers}"
  export WINEPREFIX="${WINEPREFIX:-${STEAM_COMPAT_DATA_PATH}/pfx}"
  export PROTONPATH="${PROTONPATH:-${HOME}/.local/share/Steam/compatibilitytools.d/GE-Proton11-7}"
  export PROTON_ENABLE_OPENXR=1
  export GAMEID="${STEAM_SHORTCUT_ID}"

  local umu_bin="${HOME}/bin/umu-run"
  if ! command -v "${umu_bin}" >/dev/null 2>&1; then
    if command -v umu-run >/dev/null 2>&1; then
      umu_bin="$(command -v umu-run)"
    else
      umu_bin=""
    fi
  fi

  cd "${GAME_DIR}"
  log_info "Launching Overlord VR via umu-run / Proton..."

  if [[ -n "${umu_bin}" ]]; then
    exec "${umu_bin}" "${GAME_DIR}/overlord.exe" -singleplayer "$@"
  else
    log_warn "umu-run not found. Attempting direct Proton runner..."
    exec python3 "${PROTONPATH}/proton" run "${GAME_DIR}/overlord.exe" -singleplayer "$@"
  fi
}

stop_game() {
  log_info "Attempting graceful shutdown of Overlord / MW2CR..."
  if ! is_game_running; then
    log_info "Game is not running."
    return 0
  fi

  # Attempt IPC quit command first
  ipc_send_and_wait "quit" >/dev/null 2>&1 || true
  sleep 1

  local remaining_pids
  remaining_pids="$(get_game_pids)"
  if [[ -n "${remaining_pids}" ]]; then
    log_info "Sending SIGTERM to game process..."
    while IFS= read -r line; do
      local pid
      pid="$(echo "$line" | awk '{print $1}')"
      if [[ -n "$pid" ]]; then
        kill -15 "$pid" 2>/dev/null || true
      fi
    done <<< "${remaining_pids}"
  fi

  sleep 1
  if is_game_running; then
    log_warn "Game process still running. Run './overlord.sh kill' to force kill."
  else
    log_success "Game stopped successfully."
  fi
}

kill_game() {
  log_info "Force terminating Overlord / MW2CR processes..."
  local pids
  pids="$(get_game_pids)"
  if [[ -z "${pids}" ]]; then
    log_info "No game processes found."
  else
    while IFS= read -r line; do
      local pid
      pid="$(echo "$line" | awk '{print $1}')"
      if [[ -n "$pid" ]]; then
        kill -9 "$pid" 2>/dev/null || true
        log_info "Killed PID $pid"
      fi
    done <<< "${pids}"
    log_success "Game processes terminated."
  fi
  rm -f "${IPC_IN}" "${IPC_TMP}" "${IPC_OUT}" 2>/dev/null || true
}

# ==============================================================================
# Feature: Point Custom Steam Game to this Launcher
# ==============================================================================
point_custom_steam_game() {
  log_info "Configuring Steam custom shortcut to point to overlord.sh..."
  [[ -f "${STEAM_USERDATA_VDF}" ]] || die "Steam shortcuts.vdf not found at '${STEAM_USERDATA_VDF}'"

  if is_game_running; then
    log_info "Game is currently running. Stopping game gracefully first..."
    stop_game
    if is_game_running; then
      log_warn "Game did not stop gracefully, force-killing..."
      kill_game
    fi
  fi

  local steam_running=false
  if pgrep -ax steam >/dev/null 2>&1; then
    steam_running=true
  fi

  if [[ "${steam_running}" == true ]]; then
    log_info "Shutting down Steam client via steamcli for safe configuration update..."
    steamcli client shutdown || true
    sleep 2
  fi

  # Backup shortcuts.vdf and config.vdf
  cp "${STEAM_USERDATA_VDF}" "${STEAM_USERDATA_VDF}.bak.$(date +%s)"
  [[ -f "${STEAM_CONFIG_VDF}" ]] && cp "${STEAM_CONFIG_VDF}" "${STEAM_CONFIG_VDF}.bak.$(date +%s)"

  python3 - <<PYEOF
import struct, os, sys

def parse_vdf(b):
    idx = 0
    def read_str():
        nonlocal idx
        end = b.find(b'\x00', idx)
        s = b[idx:end].decode('utf-8', 'replace')
        idx = end + 1
        return s
    def parse_dict():
        nonlocal idx
        res = {}
        while idx < len(b):
            t = b[idx]
            idx += 1
            if t == 8:
                break
            name = read_str()
            if t == 0:
                res[name] = parse_dict()
            elif t == 1:
                res[name] = read_str()
            elif t == 2:
                val = struct.unpack('<I', b[idx:idx+4])[0]
                idx += 4
                res[name] = val
        return res
    return parse_dict()

def dump_vdf(d):
    out = bytearray()
    def write_dict(data):
        for k, v in data.items():
            if isinstance(v, dict):
                out.append(0)
                out.extend(k.encode('utf-8') + b'\x00')
                write_dict(v)
                out.append(8)
            elif isinstance(v, str):
                out.append(1)
                out.extend(k.encode('utf-8') + b'\x00')
                out.extend(v.encode('utf-8') + b'\x00')
            elif isinstance(v, int):
                out.append(2)
                out.extend(k.encode('utf-8') + b'\x00')
                out.extend(struct.pack('<I', v))
    write_dict(d)
    out.append(8)
    return bytes(out)

vdf_path = "${STEAM_USERDATA_VDF}"
with open(vdf_path, 'rb') as f:
    data = parse_vdf(f.read())

shortcuts = data.get('shortcuts', {})
target_key = None
for k, v in shortcuts.items():
    if v.get('appid') == int("${STEAM_APPID}") or 'Call of Duty Modern Warfare 2 (2019) VR' in v.get('appname', ''):
        target_key = k
        break

if not target_key:
    print("[ERROR] Could not find shortcut for Call of Duty Modern Warfare 2 in shortcuts.vdf", file=sys.stderr)
    sys.exit(1)

sc = shortcuts[target_key]
sc['exe'] = '"${REAL_SCRIPT}"'
sc['StartDir'] = '${GAME_DIR}/'
sc['LaunchOptions'] = 'launch %command%'

with open(vdf_path, 'wb') as f:
    f.write(dump_vdf(data))

print(f"[OK] Updated shortcut entry [{target_key}] exe to: {sc['exe']}")
PYEOF

  # Modify config.vdf to remove forced Proton on the Linux shell script shortcut
  if [[ -f "${STEAM_CONFIG_VDF}" ]]; then
    python3 - <<PYEOF
config_path = "${STEAM_CONFIG_VDF}"
with open(config_path, 'r', encoding='utf-8', errors='ignore') as f:
    content = f.read()

# Remove forced CompatTool mapping for STEAM_APPID if present so Steam executes shell script natively
appid = "${STEAM_APPID}"
if appid in content:
    import re
    # Match block: "4096896093" \s* { [^}]+ }
    pattern = r'(\t*"' + appid + r'"\s*\{[^}]*\})'
    new_content = re.sub(pattern, '', content)
    with open(config_path, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"[OK] Cleared forced Proton compatibility tool for {appid} in config.vdf")
PYEOF
  fi

  if [[ -f "${DESKTOP_ENTRY}" ]]; then
    log_info "Verified Desktop entry: ${DESKTOP_ENTRY}"
  fi

  if [[ "${steam_running}" == true ]]; then
    log_info "Restarting Steam client via steamcli..."
    steamcli client launch || true
  fi

  log_success "Custom Steam shortcut successfully pointed to overlord.sh!"
}

# ==============================================================================
# Feature: Uninstall
# ==============================================================================
uninstall() {
  local mode="${1:-extras}"
  log_info "Uninstall requested (mode: ${mode})..."

  log_info "Removing deployed Overlord Extras from game directory..."
  rm -rf "${GAME_DIR}/h2-mod/ui_scripts/overlord_extras"
  rm -rf "${GAME_DIR}/h2-mod/ui_scripts/agent_ipc"
  rm -f "${GAME_DIR}/h2-mod/scripts/actor_spawner.gsc"
  rm -f "${GAME_DIR}/overlord.sh"

  if [[ "${mode}" == "--all" || "${mode}" == "all" || "${mode}" == "--full" ]]; then
    log_info "Removing Overlord binaries from game directory..."
    rm -f "${GAME_DIR}/overlord.exe" \
          "${GAME_DIR}/overlord.pdb" \
          "${GAME_DIR}/overlord.vrmanifest" \
          "${GAME_DIR}/version.json" \
          "${GAME_DIR}/release-info.json"
    log_success "All Overlord binaries and extras removed."
  else
    log_success "Overlord Extras removed. (Overlord core binaries retained. Pass 'uninstall --all' for full removal)."
  fi
}

# ==============================================================================
# Feature: Status
# ==============================================================================
show_status() {
  printf "\n=== Overlord VR Status ===\n"
  printf "%-25s: %s\n" "Game Directory" "${GAME_DIR}"
  printf "%-25s: %s\n" "Active Version" "$(get_current_version)"

  local pids
  pids="$(get_game_pids)"
  if [[ -n "${pids}" ]]; then
    printf "%-25s: \033[1;32mRUNNING\033[0m (%s)\n" "Game Process" "$(echo "${pids}" | tr '\n' ' ')"
  else
    printf "%-25s: \033[1;30mSTOPPED\033[0m\n" "Game Process"
  fi

  local extras_status="Missing"
  if [[ -d "${GAME_DIR}/h2-mod/ui_scripts/overlord_extras" && -d "${GAME_DIR}/h2-mod/ui_scripts/agent_ipc" ]]; then
    extras_status="Deployed"
  fi
  printf "%-25s: %s\n" "Overlord Extras" "${extras_status}"

  # Test IPC if running
  if [[ -n "${pids}" ]]; then
    printf "%-25s: " "IPC Bridge Status"
    ipc_send_and_wait "eval: return { overlord_active = true, map = Engine.GetDvarString and Engine.GetDvarString('mapname') or 'unknown' }" || echo "Not responding"
  fi
  printf "\n"
}

# ==============================================================================
# Usage & Help
# ==============================================================================
print_help() {
  cat <<EOF
Overlord VR Management CLI & Launcher

Usage:
  $(basename "$0") [command] [options]

Core Commands:
  launch, run                Deploy extras and launch game in VR (default action)
  deploy                     Deploy Overlord Extras to game directory
  stop, exit                 Gracefully exit the game via IPC / SIGTERM
  kill                       Force-kill running game processes and clear IPC files
  status                     Display game process, version, and extras status
  point-steam                Point the Steam custom game shortcut to this launcher

Version Management:
  switch                     Interactive release switcher (Aeka0/Overlord)
  --versions, versions, list List available releases on GitHub
  --version <tag>, version   Switch to a specific release (e.g. v0.4.0-beta)
  current                    Show current installed version
  uninstall [--all]          Remove deployed extras (or --all for full Overlord removal)

Agent IPC Commands:
  cmd <console_command...>   Send console command (e.g. 'god', 'noclip', 'give m4a1')
  --lua, lua <code...>       Evaluate Lua expression or script in-game
  --dvar, dvar <name> [val]  Get or set dvar
  -i, --interactive, repl    Open interactive IPC REPL shell

Examples:
  $(basename "$0")                      # Launch game
  $(basename "$0") switch               # Pick and install version
  $(basename "$0") --version v0.4.0-beta
  $(basename "$0") point-steam          # Hook Steam shortcut to overlord.sh
  $(basename "$0") god                  # Toggle godmode in-game
  $(basename "$0") --lua 'return Engine.GetDvarString("mapname")'
  $(basename "$0") kill                 # Force terminate game
EOF
}

# ==============================================================================
# Argument Dispatcher
# ==============================================================================
if [[ $# -eq 0 ]]; then
  launch_game
  exit 0
fi

ACTION="$1"
shift

case "${ACTION}" in
  launch|run|-singleplayer)
    launch_game "$@"
    ;;

  deploy)
    deploy_extras
    ;;

  stop|exit)
    stop_game
    ;;

  kill)
    kill_game
    ;;

  status)
    show_status
    ;;

  point-steam|steam-setup|link-steam)
    point_custom_steam_game
    ;;

  switch)
    prompt_interactive_switch
    ;;

  --versions|versions|--list|list)
    list_versions
    ;;

  --version|version|-v)
    [[ $# -ge 1 ]] || die "Version flag requires a tag argument (e.g. v0.4.0-beta)."
    install_version "$1"
    ;;

  current)
    log_info "Current active version: $(get_current_version)"
    ;;

  uninstall)
    uninstall "${1:-extras}"
    ;;

  --lua|lua|-l)
    [[ $# -ge 1 ]] || die "Missing Lua code to evaluate."
    ipc_send_and_wait "lua: $*"
    ;;

  --dvar|dvar|-d)
    [[ $# -ge 1 ]] || die "Missing dvar name."
    if [[ $# -eq 1 ]]; then
      ipc_send_and_wait "dvar: $1"
    else
      ipc_send_and_wait "dvar: $1=$2"
    fi
    ;;

  -i|--interactive|repl)
    run_ipc_interactive
    ;;

  cmd)
    [[ $# -ge 1 ]] || die "Missing console command."
    ipc_send_and_wait "$*"
    ;;

  --help|-h|help)
    print_help
    exit 0
    ;;

  *)
    # If passed something like 'god' or 'noclip' or in-game command, pass to IPC
    ipc_send_and_wait "${ACTION} $*"
    ;;
esac
