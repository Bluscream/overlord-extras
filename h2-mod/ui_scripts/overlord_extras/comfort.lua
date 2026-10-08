-- Overlord Extras: Comfort & Camera Options
OverlordExtras = OverlordExtras or {}
OverlordExtras.Comfort = {}

function OverlordExtras.Comfort.BuildOptions(menu, createDivider)
    createDivider(menu, "VR Camera & Comfort")

    -- vr_cameraBob (Movement camera bob)
    LUI.Options.CreateOptionButton(
        menu,
        "vr_cameraBob",
        "Camera Bob",
        "Controls native horizontal and vertical movement bob for firearms, hands, and knife in VR.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )

    -- vr_disableBlur
    LUI.Options.CreateOptionButton(
        menu,
        "vr_disableBlur",
        "Disable Motion Blur",
        "Disables fullscreen motion blur passes for reduced VR motion sickness.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )

    -- vr_disableLensFlare
    LUI.Options.CreateOptionButton(
        menu,
        "vr_disableLensFlare",
        "Disable Lens Flare",
        "Disables camera lens flares in VR.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )

    -- vr_headStabilization
    LUI.Options.CreateOptionButton(
        menu,
        "vr_headStabilization",
        "Head Stabilization",
        "Applies smoothing/filtering to headset jitter and micro-movements.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )

    -- vr_desktopStabilization
    LUI.Options.CreateOptionButton(
        menu,
        "vr_desktopStabilization",
        "Spectator Stabilization",
        "Stabilizes the desktop mirror view for recording and streaming.",
        {
            { text = "@LUA_MENU_ENABLED", value = true },
            { text = "@LUA_MENU_DISABLED", value = false }
        }
    )
end
