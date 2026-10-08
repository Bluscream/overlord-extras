-- Overlord Extras: Menu Builder and Injections
-- Sub-modules register their functions onto the OverlordExtras global table.
-- require() in Havok Script returns true, not a module table — use bare names (resolved relative to this directory).
require("comfort")
require("gameplay")
require("rendering")
require("cheats_option")

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

LUI.MenuBuilder.m_types_build["overlord_extras_menu"] = function(a1)
    local menu = LUI.MenuTemplate.new(a1, {
        menu_title = "OVERLORD VR EXTRAS",
        menu_list_divider_top_offset = -(LUI.H1MenuTab.tabChangeHoldingElementHeight + H1MenuDims.spacing),
        menu_width = GenericMenuDims.OptionMenuWidth
    })

    OverlordExtras.Comfort.BuildOptions(menu, createDivider)
    OverlordExtras.Gameplay.BuildOptions(menu, createDivider)
    OverlordExtras.Rendering.BuildOptions(menu, createDivider)
    OverlordExtras.CheatsOption.BuildOptions(menu, createDivider)

    LUI.Options.InitScrollingList(menu.list, nil)
    LUI.Options.AddOptionTextInfo(menu)
    menu:AddBackButton()

    return menu
end

-- Hook 1: PC Controls / General Options Menu
LUI.addmenubutton("pc_controls", {
    index = 5,
    text = "OVERLORD VR EXTRAS",
    description = "Adjust VR camera bob, immersion, physical reloads, and anti-aliasing.",
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
    end
})

-- Hook 2: Main Campaign Menu (Frontend)
LUI.addmenubutton("main_campaign", {
    index = 7,
    text = "OVERLORD VR EXTRAS",
    description = "Configure Overlord VR settings and comfort dvars.",
    callback = function()
        LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
    end
})

-- Hook 3: In-Game Pause Menu (Accessible live while in VR)
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
