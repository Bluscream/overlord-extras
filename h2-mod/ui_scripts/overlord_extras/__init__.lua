-- Overlord Extras: VR Settings Menu
-- All-in-one module: h2-mod's require() cannot resolve sibling files within the same module folder.
-- Modeled after settings/settings.lua which puts everything inline.

print("[Overlord Extras] Initializing modular VR settings menu...")

local function createDivider(menu, text)
    local element = LUI.UIElement.new({
        leftAnchor = true,
        rightAnchor = true,
        left = 0,
        right = 0,
        topAnchor = true,
        bottomAnchor = false,
        top = 0,
        bottom = 33.33
    })

    element.scrollingToNext = true
    element:addElement(LUI.MenuBuilder.BuildRegisteredType("h1_option_menu_titlebar", {
        title_bar_text = Engine.ToUpperCase(Engine.Localize(text))
    }))

    menu.list:addElement(element)
end

-- ============================================================
-- Section: VR Camera & Comfort
-- ============================================================

local function buildComfortOptions(menu)
    createDivider(menu, "VR Camera & Comfort")

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

-- ============================================================
-- Section: VR Gameplay & Immersion
-- ============================================================

local function buildGameplayOptions(menu)
    createDivider(menu, "VR Gameplay & Immersion")

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

-- ============================================================
-- Section: VR Rendering & Performance
-- ============================================================

local function buildRenderingOptions(menu)
    createDivider(menu, "VR Rendering & Performance")

    LUI.Options.CreateOptionButton(
        menu,
        "r_postAA",
        "Anti-Aliasing (Post-AA)",
        "Post-processing anti-aliasing. Set to 'Off' to resolve VR rendering/stereo artifacts, blur, and crashes on Beta 4.",
        {
            { text = "Off", value = "Off" },
            { text = "FXAA", value = "FXAA" },
            { text = "SMAA 1x", value = "SMAA 1x" },
            { text = "SMAA T2x", value = "SMAA T2x" },
            { text = "Filmic SMAA 1x", value = "Filmic SMAA 1x" },
            { text = "Filmic SMAA T2x", value = "Filmic SMAA T2x" }
        }
    )

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

-- ============================================================
-- Section: Sandbox & Cheats
-- ============================================================

local function buildCheatsOptions(menu)
    createDivider(menu, "Sandbox & Cheats")

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

-- ============================================================
-- Menu Registration
-- ============================================================

LUI.addmenubutton("pc_controls", {
    index = 5,
    text = "OVERLORD VR EXTRAS",
    description = "Adjust VR camera bob, immersion, physical reloads, and anti-aliasing.",
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
    end
})

LUI.MenuBuilder.m_types_build["overlord_extras_menu"] = function(a1)
    local menu = LUI.MenuTemplate.new(a1, {
        menu_title = "OVERLORD VR EXTRAS",
        menu_list_divider_top_offset = -(LUI.H1MenuTab.tabChangeHoldingElementHeight + H1MenuDims.spacing),
        menu_width = GenericMenuDims.OptionMenuWidth
    })

    buildComfortOptions(menu)
    buildGameplayOptions(menu)
    buildRenderingOptions(menu)
    buildCheatsOptions(menu)

    LUI.Options.InitScrollingList(menu.list, nil)
    LUI.Options.AddOptionTextInfo(menu)
    menu:AddBackButton()

    return menu
end

-- Hook: Main Campaign Menu (Frontend)
LUI.addmenubutton("main_campaign", {
    index = 7,
    text = "OVERLORD VR EXTRAS",
    description = "Configure Overlord VR settings and comfort dvars.",
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
    end
})

-- Hook: In-Game Pause Menu (Accessible live while in VR)
if LUI.onmenuopen then
    LUI.onmenuopen("sp_pause_menu", function(element)
        local pauseMenu = element:getFirstChild()
        if not pauseMenu or not pauseMenu.AddButton then return end

        pauseMenu:AddButton("^2VR EXTRAS^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
        end, nil, true, nil, {
            desc_text = "Live VR comfort, camera bob, reload physics, and renderer settings"
        })
    end)
end

print("[Overlord Extras] VR Extras menu successfully registered")
