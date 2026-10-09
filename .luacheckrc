-- The game runs HavokScript, a Lua 5.1 fork, so 5.1 is the closest std.
std = "lua51"

-- Host-provided globals. These are read-only from our side; declaring them
-- keeps luacheck from reporting the entire engine API as undefined, without
-- disabling the check that catches our own accidental globals.
read_globals = {
    "Engine",
    "LUI",
    "GenericButtonSettings",
    "GenericMenuDims",
    "H1MenuDims",
    "game",
    "io",
}

-- Globals this code deliberately writes. Anything not listed here that is
-- assigned without `local` is a bug.
globals = {
    "AgentIPC_Active",
}

max_line_length = 120

-- agent_ipc swaps the global `print` to capture a Lua evaluation's output and
-- restores it on both the success and the error path. There is no other way to
-- capture output from a host-provided print.
files["h2-mod/ui_scripts/agent_ipc/__init__.lua"] = {
    globals = { "AgentIPC_Active", "print" },
}
