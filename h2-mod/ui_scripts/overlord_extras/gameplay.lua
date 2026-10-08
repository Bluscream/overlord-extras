-- Overlord Extras: Gameplay & Immersion Options
OverlordExtras = OverlordExtras or {}
OverlordExtras.Gameplay = {}

function OverlordExtras.Gameplay.BuildOptions(menu, createDivider)
    createDivider(menu, "VR Gameplay & Immersion")

    -- vr_physicalReload
    LUI.Options.CreateOptionButton(
        menu,
        "vr_physicalReload",
        "Physical Reloads",
        "Enable manual magazine insertion, ejection, and bolt cycling.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )

    -- vr_closedBoltChamber
    LUI.Options.CreateOptionButton(
        menu,
        "vr_closedBoltChamber",
        "Closed Bolt Chambering",
        "Enables +1 in the chamber and authentic bolt hold-open behavior.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )

    -- vr_weaponHudNativeSource
    LUI.Options.CreateOptionButton(
        menu,
        "vr_weaponHudNativeSource",
        "Native Pip Ammo HUD",
        "Adapts native ammo counts, bullet pips, and caliber info for VR displays.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )

    -- vr_hideHud
    LUI.Options.CreateOptionButton(
        menu,
        "vr_hideHud",
        "Hide 2D HUD",
        "Hides standard 2D HUD elements for maximum VR immersion.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )
end
