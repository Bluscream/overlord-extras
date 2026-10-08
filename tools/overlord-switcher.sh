#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ==============================================================================
# Overlord VR Version Switcher for MW2CR
# ==============================================================================
# Discovers, downloads, caches, and switches releases of Aeka0/Overlord.
# Usage:
#   ./overlord-switcher.sh                     # Interactive release picker
#   ./overlord-switcher.sh --version <tag>     # Headless switch to specific tag
#   ./overlord-switcher.sh --list              # List available versions
#   ./overlord-switcher.sh --current           # Show currently active version
# ==============================================================================

REPO="Aeka0/Overlord"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
GAME_DIR="${SCRIPT_DIR}"
CACHE_DIR="${HOME}/.cache/overlord-switcher"

log() {
  printf "[\033[1;34mINFO\033[0m] %s\n" "$*"
}

success() {
  printf "[\033[1;32mSUCCESS\033[0m] %s\n" "$*"
}

warn() {
  printf "[\033[1;33mWARN\033[0m] %s\n" "$*" >&2
}

die() {
  printf "[\033[1;31mERROR\033[0m] %s\n" "$*" >&2
  exit 1
}

# Ensure extraction dependencies are present
check_deps() {
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
    die "Missing required utilities: ${missing[*]}"
  fi
}

# Fetch releases JSON via gh or curl
fetch_releases_json() {
  if command -v gh >/dev/null 2>&1; then
    gh api "repos/${REPO}/releases" 2>/dev/null || curl -sSL "https://api.github.com/repos/${REPO}/releases"
  else
    curl -sSL "https://api.github.com/repos/${REPO}/releases"
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
  log "Fetching releases for ${REPO}..."
  local releases_json
  releases_json="$(fetch_releases_json)"

  printf "\n%-15s %-20s %-12s\n" "TAG" "NAME" "PRERELEASE"
  printf "%-15s %-20s %-12s\n" "---------------" "--------------------" "------------"
  echo "$releases_json" | jq -r '.[] | "\(.tag_name)\t\(.name)\t\(.prerelease)"' | while IFS=$'\t' read -r tag name pre; do
    printf "%-15s %-20s %-12s\n" "$tag" "$name" "$pre"
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
  log "Target release: ${target_tag}"

  mkdir -p "${CACHE_DIR}"

  log "Fetching release metadata for ${target_tag}..."
  local release_info
  if command -v gh >/dev/null 2>&1; then
    release_info="$(gh api "repos/${REPO}/releases/tags/${target_tag}" 2>/dev/null || curl -sSL "https://api.github.com/repos/${REPO}/releases/tags/${target_tag}")"
  else
    release_info="$(curl -sSL "https://api.github.com/repos/${REPO}/releases/tags/${target_tag}")"
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
    log "Using cached archive: ${cached_archive}"
  else
    log "Downloading ${asset_name} from ${asset_url}..."
    curl -fSL -o "${cached_archive}.tmp" "$asset_url"
    mv "${cached_archive}.tmp" "$cached_archive"
    success "Download completed and cached."
  fi

  local extract_tmp
  extract_tmp="$(mktemp -d -p "${CACHE_DIR}" "extract-${target_tag}-XXXXXX")"
  trap 'rm -rf "${extract_tmp}"' EXIT

  log "Extracting ${asset_name}..."
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
    log "Unwrapping archive root directory: $(basename "${source_dir}")"
  fi

  log "Deploying Overlord files to game directory (${GAME_DIR})..."
  # Copy extracted files over to the game directory preserving directory structure
  cp -rf "${source_dir}/." "${GAME_DIR}/"

  rm -rf "${extract_tmp}"
  trap - EXIT

  success "Overlord successfully switched to ${target_tag}!"
  log "Current status: $(get_current_version)"
}

prompt_interactive() {
  log "Fetching releases list..."
  local releases_json
  releases_json="$(fetch_releases_json)"

  local tags=()
  local names=()
  while IFS=$'\t' read -r tag name; do
    tags+=("$tag")
    names+=("$name")
  done < <(echo "$releases_json" | jq -r '.[] | "\(.tag_name)\t\(.name)"')

  if [[ ${#tags[@]} -eq 0 ]]; then
    die "No releases found on GitHub repository ${REPO}."
  fi

  printf "\nCurrent active version: %s\n\n" "$(get_current_version)"
  printf "Available Overlord versions:\n"
  for i in "${!tags[@]}"; do
    printf "  [%d] %-15s (%s)\n" "$((i + 1))" "${tags[i]}" "${names[i]}"
  done
  printf "\n"

  local choice
  while true; do
    read -r -p "Select a version to install [1-${#tags[@]}] (or 'q' to quit): " choice
    if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
      log "Aborted."
      exit 0
    fi
    if [[ "$choice" =~ ^[0-9]+$ ]] && ((choice >= 1 && choice <= ${#tags[@]})); then
      local selected_tag="${tags[$((choice - 1))]}"
      install_version "$selected_tag"
      break
    else
      warn "Invalid selection. Please enter a number between 1 and ${#tags[@]}."
    fi
  done
}

print_help() {
  cat <<EOF
Overlord VR Version Switcher

Usage:
  $(basename "$0")                      Interactive version selection
  $(basename "$0") --version <TAG>      Switch to specific release tag (e.g. v0.2.0-beta, v0.4.0-beta)
  $(basename "$0") -v <TAG>             Short form of --version
  $(basename "$0") --list               List all available releases
  $(basename "$0") --current            Print current active version
  $(basename "$0") --help               Show this help message

Examples:
  ./overlord-switcher.sh --version v0.2.0-beta
  ./overlord-switcher.sh --version v0.4.0-beta
EOF
}

# ==============================================================================
# Argument Parsing
# ==============================================================================
check_deps

if [[ $# -eq 0 ]]; then
  if [[ -t 0 ]]; then
    prompt_interactive
  else
    die "Non-interactive environment detected. Please specify --version <TAG> or run with a TTY."
  fi
  exit 0
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version|-v)
      [[ $# -ge 2 ]] || die "Flag $1 requires a version argument (e.g. v0.2.0-beta)."
      install_version "$2"
      shift 2
      ;;
    --list|-l)
      list_versions
      shift
      ;;
    --current|-c)
      log "Current active version: $(get_current_version)"
      shift
      ;;
    --help|-h)
      print_help
      shift
      ;;
    *)
      die "Unknown argument: $1. Run with --help for usage."
      ;;
  esac
done
