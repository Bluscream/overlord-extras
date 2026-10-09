-- Shared helpers for the Overlord Extras ui_scripts modules.
--
-- WHY THIS IS ITS OWN MODULE DIRECTORY
-- `require` resolves against the requiring module's OWN folder
-- (ui_scripting.cpp: folder = dirname(root script); target = folder/name.lua),
-- so a sibling module cannot require across into another module's directory.
-- The only supported way to share code between ui_scripts modules is a global
-- namespace published by a module that loads first.
--
-- WHY THE NAME STARTS WITH AN UNDERSCORE
-- ui_script_modules.hpp sorts the module directories and loads them in that
-- order. '_' is 0x5F and lowercase letters start at 0x61, so `_common` sorts
-- ahead of agent_ipc, cheats and overlord_extras and is guaranteed to have run
-- before any of them. Consumers can therefore resolve OverlordCommon at load
-- time instead of lazily on every call.
--
-- Consumers must fail loudly if this table is missing, never degrade silently:
--     local common = _G.OverlordCommon
--     if not common then print("..."); return end

if _G.OverlordCommon then
    print("[Overlord Common] already loaded; skipping re-registration")
    return
end

local M = {}

-- ============================================================
-- Module lifecycle
-- ============================================================

-- LUI.addmenubutton and LUI.onmenuopen append a callback rather than replacing
-- one, so loading a module twice (the `dofile` hot-reload workflow) duplicates
-- every menu entry it registers. Claim returns false on the second call.
local claimed = {}
function M.Claim(name)
    if claimed[name] then
        print(string.format("[Overlord %s] already loaded; skipping re-registration", name))
        return false
    end
    claimed[name] = true
    return true
end

-- ============================================================
-- Engine access
-- ============================================================
-- Every one of these is feature-tested. A missing host function is a nil call,
-- and a nil call out of a LUI event handler surfaces as an access violation
-- rather than a Lua error -- this project has the minidumps to prove it.

function M.Exec(cmd)
    if type(Engine.Exec) == "function" then
        Engine.Exec(cmd)
    end
end

function M.SetDvarString(dvar, value)
    if type(Engine.SetDvarString) == "function" then
        Engine.SetDvarString(dvar, value)
    else
        -- `set` is queued like any other console command, so the write lands a
        -- frame later than the direct accessor would.
        M.Exec(string.format("set %s %s", dvar, value))
    end
end

function M.SetDvarBool(dvar, value)
    if type(Engine.SetDvarBool) == "function" then
        Engine.SetDvarBool(dvar, value)
    else
        M.SetDvarString(dvar, value and "1" or "0")
    end
end

-- An unregistered dvar reads back nil, so this answers false rather than
-- letting `nil` reach a concatenation and take the dispatcher down with it.
function M.GetDvarBool(dvar)
    if type(Engine.GetDvarBool) ~= "function" then
        return false
    end
    return Engine.GetDvarBool(dvar) == true
end

function M.GetDvarString(dvar, fallback)
    if type(Engine.GetDvarString) ~= "function" then
        return fallback
    end
    local value = Engine.GetDvarString(dvar)
    if type(value) ~= "string" then
        return fallback
    end
    return value
end

-- ============================================================
-- Toast feedback
-- ============================================================
-- There is no notification function anywhere in the Engine table. The native
-- cheat commands (god, demigod, notarget, noclip) print their own
-- CG_GameMessage from C++, but anything routed through `give`, `spawn_xmodel`
-- or a dvar is silent, so a button that did nothing looked exactly like one
-- that worked.
--
-- h2-mod's achievements module does publish a global `addnotification`, but it
-- is a 5s/6s QUEUE: ten armory clicks would back up a minute of stale toasts.
-- This is a single slot that replaces its text and resets its timer instead,
-- built from the element/timer/animation patterns in
-- h2-mod/ui_scripts/achievements/toast.lua, which are known to work here.

local SHOW_MS = 2200
local FADE_MS = 160
local slot, toast_label

local function toast_root()
    if type(Engine.GetLuiRoot) == "function" then
        local ok, root = pcall(Engine.GetLuiRoot)
        if ok and root then return root end
    end
    return LUI.roots and (LUI.roots.UIRoot0 or LUI.roots.UIRootFull)
end

local function build_toast()
    local parent = toast_root()
    if not parent then return false end
    if slot and slot:getParent() then return true end

    local font = CoD.TextSettings.Font21
    slot = LUI.UIElement.new({
        topAnchor = true, leftAnchor = true, rightAnchor = true,
        top = 120, left = 0, right = 0, height = font.Height + 12,
        alpha = 0
    })
    slot.id = "OverlordCommonToast"
    -- Priority keeps it above the pause menu, which is where the buttons are.
    if type(slot.setPriority) == "function" then slot:setPriority(1000) end
    slot:registerAnimationState("shown", { alpha = 1 })
    slot:registerAnimationState("hidden", { alpha = 0 })

    slot:addElement(LUI.UIImage.new({
        topAnchor = true, bottomAnchor = true,
        leftAnchor = true, rightAnchor = true,
        alpha = 0.55, color = Colors.grey_14
    }))

    toast_label = LUI.UIText.new({
        topAnchor = true, leftAnchor = true, rightAnchor = true,
        top = 6, height = font.Height,
        font = font.Font,
        alignment = LUI.Alignment.Center
    })
    slot:addElement(toast_label)

    -- One shared timer, Reset per message, so a new toast restarts the dwell
    -- instead of appending to a queue.
    local timer = LUI.UITimer.new(SHOW_MS, "overlord_toast_expired")
    slot:addElement(timer)
    slot:registerEventHandler("overlord_toast_expired", function()
        LUI.UITimer.Stop(timer)
        slot:animateToState("hidden", FADE_MS)
    end)
    slot.timer = timer

    if not pcall(function() parent:addElement(slot) end) then
        slot, toast_label = nil, nil
        return false
    end
    return true
end

-- Cosmetic only: a toast must never be able to break the button that raised it.
function M.Toast(text)
    if type(text) ~= "string" or #text == 0 then return end
    pcall(function()
        if not build_toast() then return end
        toast_label:setText(text)
        LUI.UITimer.Reset(slot.timer)
        slot:animateToState("hidden")
        slot:animateToState("shown", FADE_MS)
        if CoD and CoD.SFX and CoD.SFX.MenuAccept and type(Engine.PlaySound) == "function" then
            Engine.PlaySound(CoD.SFX.MenuAccept)
        end
    end)
end

-- Exec is queued, so the toast states what was requested, not what the engine
-- went on to do. `give` and `spawn_xmodel` report their own failures on screen
-- ("Weapon does not exist"), which appears after this.
function M.ExecNotify(cmd, text)
    M.Exec(cmd)
    M.Toast(text)
end

-- ============================================================
-- Menu building
-- ============================================================

-- A section header inside a scrolling option list.
function M.CreateDivider(menu, text)
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

-- menu:AddButton's signature is positional and mostly nil
-- (label, callback, nil, true, nil, {desc_text=...}); this names the two
-- arguments that ever vary.
function M.AddButton(menu, label, desc, onPress)
    menu:AddButton(label, onPress, nil, true, nil, { desc_text = desc })
end

-- A button that sets one known dvar value, as opposed to toggling. Overlord's
-- launcher re-applies its own cheat preferences idempotently on the server
-- scheduler, so a toggle command fights it while an explicit value does not.
function M.AddChoiceButton(menu, label, dvar, value, desc, notice)
    M.AddButton(menu, label, desc, function()
        M.SetDvarString(dvar, value)
        M.Toast(notice or label)
    end)
end

_G.OverlordCommon = M
print("[Overlord Common] shared helpers registered")
