-- Overlord Extras: Rendering & Display Options
OverlordExtras = OverlordExtras or {}
OverlordExtras.Rendering = {}

function OverlordExtras.Rendering.BuildOptions(menu, createDivider)
    createDivider(menu, "VR Rendering & Performance")

    -- r_postAA (Critical for Beta 4 stability: Off vs FXAA vs SMAA)
    LUI.Options.CreateOptionButton(
        menu,
        "r_postAA",
        "Anti-Aliasing (Post-AA)",
        "Post-processing anti-aliasing. NOTE: Set to 'Off' if experiencing crashes on Beta 4.",
        {
            { text = "Off", value = "Off" },
            { text = "FXAA", value = "FXAA" },
            { text = "SMAA 1x", value = "SMAA 1x" },
            { text = "SMAA T2x", value = "SMAA T2x" },
            { text = "Filmic SMAA 1x", value = "Filmic SMAA 1x" },
            { text = "Filmic SMAA T2x", value = "Filmic SMAA T2x" }
        }
    )

    -- cg_drawFPS
    LUI.Options.CreateOptionButton(
        menu,
        "cg_drawFPS",
        "@LUA_MENU_DRAW_FPS",
        "@LUA_MENU_DRAW_FPS_DESC",
        {
            { text = "@LUA_MENU_DISABLED", value = 0 },
            { text = "@LUA_MENU_FPS_ONLY", value = 1 },
            { text = "@LUA_MENU_FPS_AND_VIEWPOS", value = 2 }
        }
    )

    -- vr_recordingMode
    LUI.Options.CreateOptionButton(
        menu,
        "vr_recordingMode",
        "Stream Preview Mode",
        "Enables desktop recording / streaming display optimization.",
        {
            { text = "@LUA_MENU_DISABLED", value = false },
            { text = "@LUA_MENU_ENABLED", value = true }
        }
    )
end
