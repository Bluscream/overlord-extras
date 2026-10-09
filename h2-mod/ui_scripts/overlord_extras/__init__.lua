-- Overlord Extras: VR Settings Menu
--
-- Kept in one file deliberately, matching h2-mod's settings/settings.lua.
-- Shared helpers come from ui_scripts/_common, which sorts and therefore loads
-- before this module.

local common = _G.OverlordCommon
if not common then
    print("[Overlord Extras] ui_scripts/_common did not load; menu not registered")
    return
end
if not common.Claim("Extras") then return end

local createDivider = common.CreateDivider
local Toast = common.Toast
local Button = common.AddButton

print("[Overlord Extras] Initializing modular VR settings menu...")

-- This module owns overlord_cheats_enabled; ui_scripts/cheats only reads it.
--
-- Registered unconditionally, by writing, at load time. The previous version
-- used `not Engine.GetDvarType(name)` to register only when absent -- but that
-- is itself a read of a possibly-unregistered name, which is the operation that
-- faults in the native accessor. Writing is always safe; asking is not.
--
-- `set`, not `seta`: a cheat gate should start locked every launch rather than
-- persist into the player's config. Registering here at load rather than in
-- buildCheatsOptions means re-opening the menu does not re-lock it mid-session.
common.Exec("set overlord_cheats_enabled 0")

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

    local postAAOptions = {
        { text = "Off", value = "Off" },
        { text = "FXAA", value = "FXAA" },
        { text = "SMAA 1x", value = "SMAA 1x" },
        { text = "SMAA T2x", value = "SMAA T2x" },
        { text = "Filmic SMAA 1x", value = "Filmic SMAA 1x" },
        { text = "Filmic SMAA T2x", value = "Filmic SMAA T2x" }
    }

    local function getPostAAText()
        local currentVal = common.GetDvarString("r_postAA", "Off")
        for _, opt in ipairs(postAAOptions) do
            if opt.value == currentVal then
                return opt.text
            end
        end
        return currentVal
    end

    local function cyclePostAA(delta)
        local currentVal = common.GetDvarString("r_postAA", "Off")
        local idx = 1
        for i, opt in ipairs(postAAOptions) do
            if opt.value == currentVal then
                idx = i
                break
            end
        end
        local nextIdx = idx + delta
        if nextIdx > #postAAOptions then
            nextIdx = 1
        elseif nextIdx < 1 then
            nextIdx = #postAAOptions
        end
        local chosen = postAAOptions[nextIdx]
        common.SetDvarString("r_postAA", chosen.value)
        Toast("Anti-aliasing: " .. chosen.text)
    end

    LUI.Options.AddButtonOptionVariant(
        menu,
        GenericButtonSettings.Variants.Select,
        "Anti-Aliasing (Post-AA)",
        "Post-processing anti-aliasing. Set to 'Off' to resolve VR rendering and "
            .. "stereo artifacts, blur, and crashes on Beta 4.",
        getPostAAText,
        function() cyclePostAA(1) end,
        function() cyclePostAA(-1) end
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

    local function getCheatsEnabledText()
        if common.GetDvarBool("overlord_cheats_enabled") then
            return Engine.Localize("@LUA_MENU_ENABLED")
        end
        return Engine.Localize("@LUA_MENU_DISABLED")
    end

    local function toggleCheats()
        local enabled = not common.GetDvarBool("overlord_cheats_enabled")
        common.SetDvarBool("overlord_cheats_enabled", enabled)
        Toast(enabled and "Cheats menu unlocked" or "Cheats menu locked")
    end

    LUI.Options.AddButtonOptionVariant(
        menu,
        GenericButtonSettings.Variants.Select,
        "Enable Cheats Menu",
        "Unlocks the in-game Cheats & Sandbox submenu in the Pause Menu.",
        getCheatsEnabledText,
        toggleCheats,
        toggleCheats
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

        Button(pauseMenu, "^2VR EXTRAS^7", "Live VR comfort, camera bob, reload physics, and renderer settings", function()
            LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
        end)
    end)
end

print("[Overlord Extras] VR Extras menu successfully registered")
