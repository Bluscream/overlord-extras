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
IPC_TIMEOUT_SEC="${OVERLORD_IPC_TIMEOUT:-3}"

# Every ui_scripts module this repo owns. deploy, uninstall and status all read
# this list, so adding a module is a one-line change instead of three.
# _common must be present: the other modules refuse to register without it. Its
# name starts with an underscore so it sorts, and therefore loads, first.
UI_SCRIPT_MODULES=(_common overlord_extras agent_ipc cheats)

# Every GSC script this repo owns, for the same reason: uninstall and status
# both walk this list rather than naming one file each.
GSC_SCRIPTS=(actor_spawner.gsc player_state.gsc)

# Steam shortcut specifics
STEAM_SHORTCUT_ID="17596034734578728960"
STEAM_APPID="4096896093"
STEAM_USERDATA_VDF="${HOME}/.local/share/Steam/userdata/62180933/config/shortcuts.vdf"
STEAM_CONFIG_VDF="${HOME}/.local/share/Steam/config/config.vdf"
DESKTOP_ENTRY="${HOME}/Desktop/Call of Duty Modern Warfare 2 (2019) VR.desktop"

# Formatting helpers
log_info() {
  printf "[\033[1;34mINFO\033[0m] %s\n" "$(join_words "$@")"
}

log_success() {
  printf "[\033[1;32mOK\033[0m] %s\n" "$(join_words "$@")"
}

log_warn() {
  printf "[\033[1;33mWARN\033[0m] %s\n" "$(join_words "$@")" >&2
}

log_error() {
  printf "[\033[1;31mERROR\033[0m] %s\n" "$(join_words "$@")" >&2
}

die() {
  log_error "$(join_words "$@")"
  exit 1
}

# `IFS=$'\n\t'` above makes "$*" and "${arr[*]}" join on a NEWLINE, not a space.
# The IPC bridge treats every line as a separate command, so `cmd give m4` was
# arriving in-game as two commands, `give` and `m4`. Join explicitly instead.
join_words() {
  local IFS=' '
  printf '%s' "$*"
}

# ==============================================================================
# Helper Functions: Process Detection
# ==============================================================================
# The launcher is overlord.exe, but the process that actually hosts the game is
# h2-mod's cached h2_sp64_bnet_ship.exe. Omitting it made `status` report
# STOPPED mid-session and left `kill` with nothing to kill.
# Linux truncates comm to 15 bytes, so match the truncated form as well.
GAME_PROCESS_PATTERN='overlord\.exe|MW2CR\.exe|h2_sp64_bnet_ship\.exe|h2_sp64_bnet_sh'

get_game_pids() {
  # -ax matches the command NAME only, so the pattern is never tested against
  # this script's own (enormous) argument list. Never use bare `pgrep -f`.
  pgrep -ax "${GAME_PROCESS_PATTERN}" || true
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

  local module src
  for module in "${UI_SCRIPT_MODULES[@]}"; do
    src="${REPO_DIR}/h2-mod/ui_scripts/${module}"
    # A module listed but absent from the repo is a packaging mistake, not an
    # optional extra: skipping it silently ships an incomplete deployment.
    [[ -d "${src}" ]] || die "ui_scripts module '${module}' is missing from the repo at '${src}'"
    mkdir -p "${GAME_DIR}/h2-mod/ui_scripts/${module}"
    cp -rf "${src}/." "${GAME_DIR}/h2-mod/ui_scripts/${module}/"
    log_info "Deployed ui_scripts/${module}"
  done

  # Deploy scripts (GSC actors, etc.)
  if [[ -d "${REPO_DIR}/h2-mod/scripts" ]]; then
    cp -rf "${REPO_DIR}/h2-mod/scripts/." "${GAME_DIR}/h2-mod/scripts/"
  fi

  # Symlink launcher script into game dir for convenience
  ln -sf "${REAL_SCRIPT}" "${GAME_DIR}/overlord.sh"

  log_success "Overlord Extras successfully deployed."

  # ui_scripts are read once at UI load and GSC once at level load, so a game
  # that is already running keeps whatever it started with. This applies to
  # every module, not just one feature.
  if [[ -n "$(get_game_pids)" ]]; then
    log_warn "The game is running; it is still using the modules it loaded at startup."
    log_warn "Restart it to pick these up."
  fi
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
    die "Missing required utilities for version switching: $(join_words "${missing[@]}")"
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
  printf "%s\n" "${full_payload}" >"${IPC_TMP}"
  mv -f "${IPC_TMP}" "${IPC_IN}"

  local start_time
  start_time=$(date +%s)
  local deadline=$((start_time + IPC_TIMEOUT_SEC))

  while [[ $(date +%s) -le ${deadline} ]]; do
    # Match the id anchored to its own line, so a request id appearing inside a
    # command's output cannot be mistaken for the response header.
    if [[ -f "${IPC_OUT}" ]] && grep -qx "id: ${req_id}" "${IPC_OUT}" 2>/dev/null; then
      local status
      # head -n 1: only the header's status counts. A command whose output
      # contains a "status:" line would otherwise decide its own exit code.
      status="$(grep -m 1 "^status:" "${IPC_OUT}" | awk '{print $2}')"
      sed -n '/^output:/,$ p' "${IPC_OUT}" | sed '1d'

      [[ "${status}" == "ok" ]] && return 0
      return 2
    fi
    sleep 0.05
  done

  log_error "Timeout waiting for Overlord IPC response (${IPC_TIMEOUT_SEC}s). Is the game running?"
  rm -f "${IPC_IN}" 2>/dev/null || true
  return 1
}

# Join a console command's words with spaces before handing it to the
# line-oriented bridge, and refuse an embedded newline rather than letting it
# split into several commands in game.
send_console_command() {
  local command_line
  command_line="$(join_words "$@")"
  [[ "${command_line}" != *$'\n'* ]] ||
    die "A console command must be a single line; the IPC bridge is line-oriented."
  ipc_send_and_wait "${command_line}"
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
    done <<<"${remaining_pids}"
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
    done <<<"${pids}"
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

  # Both files are rewritten by tools/steam_shortcut.py, which backs each one up,
  # brace-matches the config.vdf entry instead of regexing it, and refuses to
  # write shortcuts.vdf unless the serialized bytes parse back identically.
  local helper="${REPO_DIR}/tools/steam_shortcut.py"
  [[ -f "${helper}" ]] || die "Steam shortcut helper not found at '${helper}'"

  python3 "${helper}" point \
    --shortcuts "${STEAM_USERDATA_VDF}" \
    --appid "${STEAM_APPID}" \
    --appname "Call of Duty Modern Warfare 2 (2019) VR" \
    --exe "${REAL_SCRIPT}" \
    --start-dir "${GAME_DIR}/" \
    --launch-options "launch"

  if [[ -f "${STEAM_CONFIG_VDF}" ]]; then
    python3 "${helper}" clear-compat \
      --config "${STEAM_CONFIG_VDF}" \
      --appid "${STEAM_APPID}"
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

  [[ -d "${GAME_DIR}" ]] || die "Game directory not found at '${GAME_DIR}'"

  log_info "Removing deployed Overlord Extras from game directory..."
  local module target
  for module in "${UI_SCRIPT_MODULES[@]}"; do
    target="${GAME_DIR}/h2-mod/ui_scripts/${module}"
    if [[ -d "${target}" ]]; then
      rm -rf "${target}"
      log_info "Removed ui_scripts/${module}"
    fi
  done
  local script
  for script in "${GSC_SCRIPTS[@]}"; do
    rm -f "${GAME_DIR}/h2-mod/scripts/${script}"
  done
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

  local module deployed=() missing=()
  for module in "${UI_SCRIPT_MODULES[@]}"; do
    if [[ -f "${GAME_DIR}/h2-mod/ui_scripts/${module}/__init__.lua" ]]; then
      deployed+=("${module}")
    else
      missing+=("${module}")
    fi
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    printf "%-25s: Deployed (%s)\n" "Overlord Extras" "$(join_words "${deployed[@]}")"
  else
    printf "%-25s: \033[1;33mIncomplete\033[0m (missing: %s)\n" "Overlord Extras" "$(join_words "${missing[@]}")"
  fi

  local script gsc_ok=() gsc_missing=()
  for script in "${GSC_SCRIPTS[@]}"; do
    if [[ -f "${GAME_DIR}/h2-mod/scripts/${script}" ]]; then
      gsc_ok+=("${script}")
    else
      gsc_missing+=("${script}")
    fi
  done
  if [[ ${#gsc_missing[@]} -eq 0 ]]; then
    printf "%-25s: Deployed (%s)\n" "GSC scripts" "$(join_words "${gsc_ok[@]}")"
  else
    printf "%-25s: \033[1;33mIncomplete\033[0m (missing: %s)\n" "GSC scripts" "$(join_words "${gsc_missing[@]}")"
  fi

  # Test IPC if running
  if [[ -n "${pids}" ]]; then
    printf "%-25s: " "IPC Bridge Status"
    ipc_send_and_wait "eval: return { overlord_active = true, map = Engine.GetDvarString and Engine.GetDvarString('mapname') or 'unknown' }" || echo "Not responding"
  fi
  printf "\n"
}

# Read the player-state dvars that scripts/player_state.gsc publishes.
#
# Only names that ui_scripts/_common registers at UI load time are read here.
# Reading an unregistered dvar faults in the native accessor (0xC0000005) and
# takes the game down -- a Lua pcall does not catch it, because the fault is in
# C++ below Lua. Never add a name to this list without registering it first.
PLAYER_STATE_FIELDS=(tick origin angles health stance weapon weapon_count weapons)

# Make every name safe to read, without asking whether it exists.
#
# Writing a dvar is always safe -- it creates the name if absent. Reading one
# that was never registered faults in the native accessor and kills the game.
# So write all of them blank first, then read.
#
# Blanking costs nothing: player_state.gsc republishes at 4Hz, so a live level
# refills them within ~250ms. If no level is loaded there is nothing to
# preserve, and the blanks are exactly the "not published" signal. This is why
# the reader does not care which ui_scripts/_common the running game happens to
# have loaded.
ensure_player_state_dvars() {
  local lua='' f
  for f in "${PLAYER_STATE_FIELDS[@]}"; do
    lua+="Engine.Exec('set overlord_ps_${f} \"\"'); "
  done
  lua+='return "registered"'
  ipc_send_and_wait "eval: ${lua}" >/dev/null 2>&1 || return 1
}

sample_player_state() {
  # Built as one line: the IPC bridge is line-oriented and rejects embedded
  # newlines.
  local lua='local d={'
  local f
  for f in "${PLAYER_STATE_FIELDS[@]}"; do lua+="\"${f}\","; done
  lua+='}; local o={}; for _,k in ipairs(d) do o[#o+1]=k.."="..tostring(Engine.GetDvarString("overlord_ps_"..k)) end; return table.concat(o,"|")'

  ipc_send_and_wait "eval: ${lua}" 2>/dev/null | sed -n 's/^\[LUA\] => "\(.*\)"$/\1/p'
}

show_player_status() {
  local pids
  pids="$(get_game_pids)"
  if [[ -z "${pids}" ]]; then
    log_error "Game is not running; player state is only published while a level is loaded."
    return 1
  fi

  # Engine.Exec is queued, so give the writes a frame to land and the GSC a
  # publish cycle (250ms) to refill them.
  ensure_player_state_dvars || {
    log_error "No response from the IPC bridge."
    return 1
  }
  sleep 0.5

  local first second
  first="$(sample_player_state)"
  if [[ -z "${first}" ]]; then
    log_error "No response from the IPC bridge."
    return 1
  fi

  # A second sample proves the GSC publisher thread is actually running. The
  # dvars persist after it stops (level end, player death), so a frozen tick is
  # the only way to tell live data from a leftover snapshot.
  sleep 0.5
  second="$(sample_player_state)"

  declare -A state
  local pair
  while IFS= read -r pair; do
    [[ -z "${pair}" ]] && continue
    state["${pair%%=*}"]="${pair#*=}"
    # printf '%s\n', not '%s': `read` returns non-zero on a final line with no
    # newline terminator, so the loop body never runs for it and the LAST field
    # is silently dropped. That field is `weapons`.
  done < <(printf '%s\n' "${first}" | tr '|' '\n')

  local tick_a="${state[tick]:-}" tick_b=""
  tick_b="$(printf '%s' "${second}" | tr '|' '\n' | sed -n 's/^tick=//p')"

  printf "\n=== Overlord Player State ===\n"

  if [[ -z "${tick_a}" || "${tick_a}" == "nil" || "${tick_a}" == "0" || "${tick_a}" == "" ]]; then
    printf "%-25s: \033[1;33mNOT PUBLISHED\033[0m\n" "Publisher"
    printf "\nNo level is loaded, or scripts/player_state.gsc is not deployed.\n"
    printf "Player state only exists while a mission is running.\n\n"
    return 0
  fi

  if [[ "${tick_a}" == "${tick_b}" ]]; then
    printf "%-25s: \033[1;33mSTALE\033[0m (tick frozen at %s)\n" "Publisher" "${tick_a}"
    printf "%-25s: %s\n" "" "Values below are a leftover snapshot, not live."
  else
    printf "%-25s: \033[1;32mLIVE\033[0m (tick %s -> %s)\n" "Publisher" "${tick_a}" "${tick_b}"
  fi

  printf "%-25s: %s\n" "Map" "$(ipc_send_and_wait 'eval: return tostring(Engine.GetDvarString("mapname"))' 2>/dev/null | sed -n 's/^\[LUA\] => "\(.*\)"$/\1/p')"
  printf "%-25s: %s\n" "Origin (x y z)" "${state[origin]:-?}"
  printf "%-25s: %s\n" "Angles (pitch yaw roll)" "${state[angles]:-?}"
  printf "%-25s: %s\n" "Health (cur max)" "${state[health]:-?}"
  printf "%-25s: %s\n" "Stance" "${state[stance]:-?}"
  printf "%-25s: %s\n" "Weapon in hand" "${state[weapon]:-?}"

  # 15 is the native ownership array's capacity (weapon_carry.hpp); past it
  # reconcile_instances refuses and newly given weapons stop being placed at
  # all, which looks like `give` silently failing.
  local count="${state[weapon_count]:-0}"
  if [[ "${count}" =~ ^[0-9]+$ ]] && ((count >= 15)); then
    printf "%-25s: \033[1;31m%s / 15 (AT CAP)\033[0m\n" "Weapons carried" "${count}"
    printf "%-25s: %s\n" "" "New weapons will not be placed. Run 'take all' to clear."
  else
    printf "%-25s: %s / 15\n" "Weapons carried" "${count}"
  fi

  local weapons="${state[weapons]:-}"
  if [[ -n "${weapons}" && "${weapons}" != "nil" ]]; then
    printf "%-25s:\n" "Inventory"
    # '%s\n' for the same reason as above: a one-weapon list has no commas, so
    # without the terminator the whole list would be dropped.
    printf '%s\n' "${weapons}" | tr ',' '\n' | while IFS= read -r wpn; do
      [[ -n "${wpn}" ]] && printf "  - %s\n" "${wpn}"
    done
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
  status --player, player    Live player position, rotation, health, stance
                             and carried weapons (needs a loaded level)
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
  launch | run | -singleplayer)
    launch_game "$@"
    ;;

  deploy)
    deploy_extras
    ;;

  stop | exit)
    stop_game
    ;;

  kill)
    kill_game
    ;;

  status)
    # ACTION was shifted off above, so the subcommand is $1 here.
    if [[ "${1:-}" == "--player" || "${1:-}" == "player" ]]; then
      show_player_status
    else
      show_status
    fi
    ;;

  player | --player)
    show_player_status
    ;;

  point-steam | steam-setup | link-steam)
    point_custom_steam_game
    ;;

  switch)
    prompt_interactive_switch
    ;;

  --versions | versions | --list | list)
    list_versions
    ;;

  --version | version | -v)
    [[ $# -ge 1 ]] || die "Version flag requires a tag argument (e.g. v0.4.0-beta)."
    install_version "$1"
    ;;

  current)
    log_info "Current active version: $(get_current_version)"
    ;;

  uninstall)
    uninstall "${1:-extras}"
    ;;

  --lua | lua | -l)
    [[ $# -ge 1 ]] || die "Missing Lua code to evaluate."
    # A newline inside the payload would split one expression into several
    # commands at the bridge, so reject it rather than mangling it silently.
    LUA_CODE="$(join_words "$@")"
    [[ "${LUA_CODE}" != *$'\n'* ]] || die "Lua code must be a single line; the IPC bridge is line-oriented."
    ipc_send_and_wait "lua: ${LUA_CODE}"
    ;;

  --dvar | dvar | -d)
    [[ $# -ge 1 ]] || die "Missing dvar name."
    if [[ $# -eq 1 ]]; then
      ipc_send_and_wait "dvar: $1"
    else
      ipc_send_and_wait "dvar: $1=$2"
    fi
    ;;

  -i | --interactive | repl)
    run_ipc_interactive
    ;;

  cmd)
    [[ $# -ge 1 ]] || die "Missing console command."
    send_console_command "$@"
    ;;

  --help | -h | help)
    print_help
    exit 0
    ;;

  -*)
    # An unrecognised flag is a typo, not a console command. Sending it to the
    # bridge turned `--staus` into a three-second wait and "Is the game running?".
    log_error "Unknown option '${ACTION}'."
    print_help >&2
    exit 64
    ;;

  *)
    # Bare words are passed through as console commands ('god', 'give m4'), but
    # only when the game is actually up — otherwise a mistyped subcommand waits
    # out the IPC timeout and reports a connection problem instead of the typo.
    if ! is_game_running; then
      log_error "Unknown command '${ACTION}', and no running game to send it to as a console command."
      print_help >&2
      exit 64
    fi
    send_console_command "${ACTION}" "$@"
    ;;
esac
