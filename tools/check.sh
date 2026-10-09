#!/usr/bin/env bash
# ==============================================================================
# check.sh — the repository's quality gate.
# ==============================================================================
# There is no compiler and no test harness for any of this code: the Lua runs in
# the game's HavokScript VM and the GSC runs in the engine. A parse check plus a
# linter is therefore the entire static verification story, which makes it worth
# running on every change rather than occasionally.
#
# Usage: tools/check.sh
# Exits non-zero if any step fails. A step whose tool is missing is reported as
# SKIP and does not pass silently.
set -euo pipefail
IFS=$'\n\t'

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "${REPO_DIR}"

failures=0
skips=0

step() {
  printf '\n\033[1;34m==>\033[0m %s\n' "$1"
}

fail() {
  printf '\033[1;31mFAIL\033[0m %s\n' "$1" >&2
  failures=$((failures + 1))
}

skip() {
  printf '\033[1;33mSKIP\033[0m %s (install it to enable this check)\n' "$1" >&2
  skips=$((skips + 1))
}

mapfile -t shell_files < <(git ls-files --cached --others --exclude-standard '*.sh')
mapfile -t lua_files < <(git ls-files --cached --others --exclude-standard '*.lua')
mapfile -t python_files < <(git ls-files --cached --others --exclude-standard '*.py')

step "bash -n (syntax)"
for file in "${shell_files[@]}"; do
  bash -n "${file}" || fail "bash -n ${file}"
done

step "shellcheck"
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck -S style "${shell_files[@]}" || fail "shellcheck"
else
  skip shellcheck
fi

step "shfmt (formatting)"
if command -v shfmt >/dev/null 2>&1; then
  shfmt -d -i 2 -ci "${shell_files[@]}" || fail "shfmt: run 'shfmt -w -i 2 -ci' on the files above"
else
  skip shfmt
fi

step "Lua parse check (5.1 syntax)"
# The game's HavokScript is a Lua 5.1 fork, so a 5.1-compatible parser is the
# right check. LuaJIT is 5.1-compatible and is already present on this host.
lua_parser=""
for candidate in luac5.1 luajit lua5.1; do
  if command -v "${candidate}" >/dev/null 2>&1; then
    lua_parser="${candidate}"
    break
  fi
done
if [[ -n "${lua_parser}" ]]; then
  for file in "${lua_files[@]}"; do
    case "${lua_parser}" in
      luajit) "${lua_parser}" -bl "${file}" >/dev/null || fail "${lua_parser} parse ${file}" ;;
      *) "${lua_parser}" -p "${file}" || fail "${lua_parser} parse ${file}" ;;
    esac
  done
  printf 'parsed %d file(s) with %s\n' "${#lua_files[@]}" "${lua_parser}"
else
  skip "luajit / luac5.1"
fi

step "luacheck"
if command -v luacheck >/dev/null 2>&1; then
  luacheck "${lua_files[@]}" || fail "luacheck"
else
  skip luacheck
fi

step "Python syntax"
if [[ ${#python_files[@]} -gt 0 ]]; then
  python3 -m py_compile "${python_files[@]}" || fail "python3 -m py_compile"
  find . -name '__pycache__' -type d -prune -exec rm -rf {} + 2>/dev/null || true
fi

step "ruff"
if command -v ruff >/dev/null 2>&1 && [[ ${#python_files[@]} -gt 0 ]]; then
  ruff check "${python_files[@]}" || fail "ruff"
  ruff format --diff "${python_files[@]}" || fail "ruff format"
else
  skip ruff
fi

# gsc-tool is the engine's own compiler front end, so `--mode comp --dry`
# reproduces the errors the game would print at load, including semantic ones a
# parse alone misses (a local declared inside an `if` is not visible after it).
# MW2CR is the h2 title on pc.
step "GSC compile check (gsc-tool, game=h2)"
mapfile -t gsc_files < <(git ls-files --cached --others --exclude-standard '*.gsc' '*.csc')
if [[ ${#gsc_files[@]} -eq 0 ]]; then
  printf 'no GSC files\n'
elif command -v gsc-tool >/dev/null 2>&1; then
  for file in "${gsc_files[@]}"; do
    gsc-tool --mode comp --game h2 --system pc --dry "${file}" || fail "gsc-tool comp ${file}"
  done
  printf 'compiled %d GSC file(s)\n' "${#gsc_files[@]}"
else
  skip gsc-tool
  # Fall back to the only thing shell can assert without a compiler.
  for file in "${gsc_files[@]}"; do
    opens="$(tr -cd '{' <"${file}" | wc -c)"
    closes="$(tr -cd '}' <"${file}" | wc -c)"
    if [[ "${opens}" != "${closes}" ]]; then
      fail "${file}: ${opens} '{' vs ${closes} '}'"
    fi
  done
fi

printf '\n============================================\n'
printf 'failures: %d   skipped checks: %d\n' "${failures}" "${skips}"
if [[ ${failures} -gt 0 ]]; then
  printf '\033[1;31mGATE FAILED\033[0m\n' >&2
  exit 1
fi
if [[ ${skips} -gt 0 ]]; then
  printf '\033[1;33mGATE PASSED WITH %d SKIPPED CHECK(S)\033[0m\n' "${skips}"
else
  printf '\033[1;32mGATE PASSED\033[0m\n'
fi
