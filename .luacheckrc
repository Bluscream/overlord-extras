-- The game runs HavokScript, a Lua 5.1 fork, so 5.1 is the closest std.
std = "lua51"

-- Host-provided globals we only read.
read_globals = {
    "Engine",                 -- dvars, Exec/ExecNow, Localize, PlaySound, GetLuiRoot
    "CoD",                    -- CoD.TextSettings.*, CoD.SFX.*
    "Colors",                 -- Colors.grey_14, Colors.h1.*, Colors.h2.*
    "GenericButtonSettings",
    "GenericMenuDims",
    "H1MenuDims",
    "RegisterMaterial",
    "game",                   -- methods: game:assetlist(), game:getweapondisplayname()
    "io",                     -- host replacement: readfile/writefile/fileexists/removefile
}

-- LUI is written to, not just read: registering a menu assigns into
-- LUI.MenuBuilder.m_types_build. Declaring it read-only makes that a warning.
globals = {
    "LUI",
    -- ui_scripts/_common publishes the shared helper table here. `require`
    -- resolves against the requiring module's own folder, so a global is the
    -- only way to share code across ui_scripts modules.
    "OverlordCommon",
}

-- 120 is right for code, but the weapon and model lists are one data row per
-- entry ({ id, name, desc }) and wrapping them across three lines each makes a
-- 40-entry table far harder to scan or diff. Code lines are kept under 120.
max_line_length = 160

-- agent_ipc swaps the global `print` to capture a Lua evaluation's output and
-- restores it on both the success and the error path. The host provides print,
-- and there is no other way to capture what evaluated code writes.
files["h2-mod/ui_scripts/agent_ipc/__init__.lua"] = {
    globals = { "print" },
}
