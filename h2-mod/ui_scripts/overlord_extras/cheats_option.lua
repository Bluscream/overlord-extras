-- Overlord Extras: Sandbox & Cheats Options
OverlordExtras = OverlordExtras or {}
OverlordExtras.CheatsOption = {}

function OverlordExtras.CheatsOption.BuildOptions(menu, createDivider)
    createDivider(menu, "Sandbox & Cheats")

    -- overlord_cheats_enabled (Master lock for the in-game cheats menu)
    LUI.Options.CreateOptionButton(
        menu,
        "overlord_cheats_enabled",
        "Enable Cheats Menu",
        "Unlocks the in-game Cheats & Sandbox submenu in the Pause Menu.",
        {
            { text = "@LUA_MENU_DISABLED", value = false },
            { text = "@LUA_MENU_ENABLED", value = true }
        }
    )
end
