#!/usr/bin/env bash
# ==============================================================================
# overlord-cmd.sh - Agent & Host IPC CLI for Overlord / MW2CR
# ==============================================================================
set -euo pipefail

REAL_SCRIPT="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(cd "$(dirname "${REAL_SCRIPT}")" && pwd)"
H2_MOD_DIR="${SCRIPT_DIR}/h2-mod"
IPC_IN="${H2_MOD_DIR}/ipc_in.txt"
IPC_TMP="${H2_MOD_DIR}/ipc_in.tmp"
IPC_OUT="${H2_MOD_DIR}/ipc_out.txt"

TIMEOUT_SEC=3
VERBOSE=0

print_usage() {
    cat <<EOF
Usage: $(basename "$0") [options] [command...]

Commands:
  <console_command>          Send console command to game (e.g. 'god', 'noclip', 'give m4a1')
  --lua <lua_code>           Evaluate Lua code/expression (e.g. 'return Engine.GetDvarString("mapname")')
  --dvar <name> [value]      Get or set dvar value
  --interactive, -i          Enter interactive REPL shell
  --status                   Check IPC bridge status
  --timeout <sec>            Wait timeout in seconds (default: 3)
  --help, -h                 Show this help

Examples:
  $(basename "$0") god
  $(basename "$0") give cheytac
  $(basename "$0") --lua 'return Engine.GetDvarFloat("cg_fov")'
  $(basename "$0") --dvar cg_fov 95
  $(basename "$0") -i
EOF
}

if [[ ! -d "${H2_MOD_DIR}" ]]; then
    echo "[ERROR] h2-mod directory not found at '${H2_MOD_DIR}'" >&2
    exit 1
fi

send_and_wait() {
    local payload="$1"
    local req_id
    req_id="$(date +%s%N | cut -b1-13)-$RANDOM"

    # Prepend request ID
    local full_payload
    full_payload="id: ${req_id}
${payload}"

    # Remove stale output if old request
    rm -f "${IPC_OUT}" 2>/dev/null || true

    # Write atomically
    printf "%s\n" "${full_payload}" > "${IPC_TMP}"
    mv -f "${IPC_TMP}" "${IPC_IN}"

    # Wait for response
    local start_time
    start_time=$(date +%s)
    local deadline=$((start_time + TIMEOUT_SEC))

    while [[ $(date +%s) -le ${deadline} ]]; do
        if [[ -f "${IPC_OUT}" ]]; then
            # Check if this output corresponds to our request ID or is ready
            if grep -q "id: ${req_id}" "${IPC_OUT}" 2>/dev/null; then
                # Parse and display response
                local status
                status=$(grep "^status:" "${IPC_OUT}" | awk '{print $2}')
                
                # Output lines after 'output:'
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

    echo "[ERROR] Timeout waiting for Overlord IPC response (${TIMEOUT_SEC}s). Is the game running with Overlord active?" >&2
    rm -f "${IPC_IN}" 2>/dev/null || true
    return 1
}

# Parse options
MODE="cmd"
CMD_ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --lua|-l)
            MODE="lua"
            shift
            CMD_ARGS+=("$@")
            break
            ;;
        --dvar|-d)
            MODE="dvar"
            shift
            CMD_ARGS+=("$@")
            break
            ;;
        --interactive|-i)
            MODE="interactive"
            shift
            ;;
        --status)
            MODE="status"
            shift
            ;;
        --timeout|-t)
            TIMEOUT_SEC="$2"
            shift 2
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            CMD_ARGS+=("$1")
            shift
            ;;
    esac
done

case "${MODE}" in
    interactive)
        echo "=== Overlord Interactive IPC Shell ==="
        echo "Type commands to execute in game. Prefix with 'lua: ' or 'eval: ' for Lua code."
        echo "Type 'exit' or 'quit' or Ctrl+D to leave."
        echo "----------------------------------------"
        while IFS= read -r -p "overlord> " line; do
            [[ -z "${line}" ]] && continue
            [[ "${line}" == "exit" || "${line}" == "quit" ]] && break
            send_and_wait "${line}" || true
        done
        ;;

    status)
        echo "[INFO] Testing Overlord IPC connection..."
        send_and_wait "eval: return { overlord_active = true, map = Engine.GetDvarString and Engine.GetDvarString('mapname') or 'unknown' }"
        ;;

    lua)
        if [[ ${#CMD_ARGS[@]} -eq 0 ]]; then
            echo "[ERROR] Missing Lua code argument." >&2
            exit 1
        fi
        CODE="${CMD_ARGS[*]}"
        send_and_wait "lua: ${CODE}"
        ;;

    dvar)
        if [[ ${#CMD_ARGS[@]} -eq 0 ]]; then
            echo "[ERROR] Missing dvar name argument." >&2
            exit 1
        fi
        if [[ ${#CMD_ARGS[@]} -eq 1 ]]; then
            send_and_wait "dvar: ${CMD_ARGS[0]}"
        else
            send_and_wait "dvar: ${CMD_ARGS[0]}=${CMD_ARGS[1]}"
        fi
        ;;

    cmd)
        if [[ ${#CMD_ARGS[@]} -eq 0 ]]; then
            print_usage
            exit 0
        fi
        COMMAND="${CMD_ARGS[*]}"
        send_and_wait "${COMMAND}"
        ;;
esac
