-- Cheats Menu Module for Overlord / MW2CR
-- An in-game Cheats submenu for the VR pause menu: damage protection, AI
-- targeting, sustained ammunition, one-shot refills, a weapon armory, mission
-- items, throwables, and static model placement.
--
-- Gated on the `overlord_cheats_enabled` dvar, which ui_scripts/overlord_extras
-- registers and toggles. This module only ever reads it.

-- Shared helpers live in ui_scripts/_common, which sorts and therefore loads
-- before this module. Resolve it once and fail loudly: a half-working cheats
-- menu is worse than one that says why it is absent.
local common = _G.OverlordCommon
if not common then
    print("[Overlord Cheats] ui_scripts/_common did not load; menu not registered")
    return
end
if not common.Claim("Cheats") then return end

local ExecCmd = common.Exec
local ExecCmdNotify = common.ExecNotify
local SetChoice = common.AddChoiceButton
local createDivider = common.CreateDivider
local Button = common.AddButton
local IsCheatsUnlocked = function()
    -- overlord_extras registers and owns this dvar; this module only reads it.
    return common.GetDvarBool("overlord_cheats_enabled")
end

-- Overlord's launcher owns these three preferences and re-applies them
-- idempotently on the server scheduler. Firing `god`/`notarget` as console
-- toggles fights that loop: the launcher reasserts its own value on the next
-- tick and the menu and the launcher's VR Settings page disagree. Setting the
-- preference instead makes a second press harmless.
-- Contract: docs/vr-official-cheats.md in the Overlord source tree.
local CHEAT_HEALTH_DVAR = "vr_cheatHealth"      -- off | demigod | god
local CHEAT_NOTARGET_DVAR = "vr_cheatNotarget"  -- off | on
local CHEAT_AMMO_DVAR = "vr_cheatAmmo"          -- off | reserve | infinite

-- Submenu creation helper
local function CreateSubmenu(root, title, populateFunc)
    local menuwidth = 650
    local menu = LUI.MenuTemplate.new(root, {
        menu_title = title,
        exclusiveController = 0,
        menu_width = menuwidth,
        menu_top_indent = LUI.MenuTemplate.spMenuOffset or 0,
        showTopRightSmallBar = true,
        uppercase_title = true
    })

    if populateFunc then
        populateFunc(menu, createDivider)
    end

    if LUI.Options and LUI.Options.InitScrollingList then
        LUI.Options.InitScrollingList(menu.list, nil)
    end

    menu:AddBackButton()
    return menu
end

-- ============================================================
-- Where a given weapon physically goes in VR
-- ============================================================
-- `give` is not replaced in VR, but it does not put anything in your hands:
-- command.cpp skips G_SelectWeapon whenever VR carry is active, so the weapon
-- enters the native inventory and the carry system assigns it a body slot.
-- free_slot() in weapon_carry.hpp tries right waist, then left waist, then the
-- back, then the hidden extraction-only overflow queue -- and accepts() gates
-- the waist slots behind policy.waist, which weapon_carry_profiles.hpp grants
-- to an authored list, NOT to the native weapon category ("a native SMG
-- category is not a waist permit").
--
-- Nothing here is guesswork; the lists below mirror that file exactly.
local CARRY_HIP = "hip"       -- right hip, else left hip, else back
local CARRY_BACK = "back"     -- back only; a second one is hidden in overflow
local CARRY_BELLY = "belly"   -- its own abdominal slot, never dropped
local CARRY_OFFHAND = "off"   -- not in the carry system at all

local CARRY_TEXT = {
    [CARRY_HIP] = "Goes to your right hip, then left hip, then back.",
    [CARRY_BACK] = "Goes on your back -- too large for a hip slot. A second "
        .. "back-slot weapon is stowed out of sight and has to be drawn by "
        .. "reaching behind you.",
    [CARRY_BELLY] = "Goes to its own abdominal slot and cannot be dropped.",
    [CARRY_OFFHAND] = "Not handled by VR carry; it stays in its native "
        .. "equipment or offhand slot.",
}


-- Weapon category tables (using authentic Call of Duty MW2 internal weapon IDs)
local WEAPONS_AR = {
    { id = "m4", name = "M4A1", desc = "Fully automatic assault rifle", carry = CARRY_BACK },
    { id = "m4m203_reflex", name = "M4A1 w/ M203 & Reflex", desc = "M4A1 equipped with grenade launcher and optic", carry = CARRY_BACK },
    { id = "m4_silencer", name = "M4A1 Suppressed", desc = "M4A1 with silencer", carry = CARRY_BACK },
    { id = "m16", name = "M16A4", desc = "3-round burst assault rifle", carry = CARRY_BACK },
    { id = "m16_grenadier", name = "M16A4 Grenadier", desc = "M16A4 with M203 grenade launcher", carry = CARRY_BACK },
    { id = "ak47", name = "AK-47", desc = "High caliber fully automatic rifle", carry = CARRY_BACK },
    { id = "ak47_grenadier", name = "AK-47 w/ GP-25", desc = "AK-47 with GP-25 underbarrel grenade launcher", carry = CARRY_BACK },
    { id = "scar_h", name = "SCAR-H", desc = "High damage battle rifle", carry = CARRY_BACK },
    { id = "famas", name = "FAMAS", desc = "3-round burst bullpup assault rifle", carry = CARRY_BACK },
    { id = "fal", name = "FAL", desc = "Semi-automatic battle rifle", carry = CARRY_BACK },
    { id = "tavor", name = "TAR-21 (Tavor)", desc = "Bullpup assault rifle with high fire rate", carry = CARRY_BACK },
    { id = "masada", name = "ACR (Masada)", desc = "Low recoil assault rifle", carry = CARRY_BACK },
    { id = "fn2000", name = "F2000", desc = "High rate of fire bullpup assault rifle", carry = CARRY_BACK }
}

local WEAPONS_SMG = {
    { id = "mp5k", name = "MP5K", desc = "Compact 9mm submachine gun", carry = CARRY_BACK },
    { id = "ump45", name = "UMP45", desc = "High stopping power .45 ACP submachine gun", carry = CARRY_BACK },
    { id = "uzi", name = "Mini-Uzi", desc = "High fire rate open-bolt submachine gun", carry = CARRY_HIP },
    { id = "p90", name = "P90", desc = "50-round top-loading high capacity submachine gun", carry = CARRY_BACK },
    { id = "kriss", name = "Vector (KRISS)", desc = "Extremely high fire rate submachine gun", carry = CARRY_BACK }
}

local WEAPONS_SHOTGUN = {
    { id = "spas12", name = "SPAS-12", desc = "Pump-action combat shotgun", carry = CARRY_BACK },
    { id = "aa12", name = "AA-12", desc = "Fully automatic box-fed shotgun", carry = CARRY_BACK },
    { id = "m1014", name = "M1014", desc = "Semi-automatic combat shotgun", carry = CARRY_BACK },
    { id = "striker", name = "Striker", desc = "Revolving cylinder combat shotgun", carry = CARRY_BACK },
    { id = "ranger", name = "Ranger", desc = "Over-under double-barrel break-action shotgun", carry = CARRY_HIP },
    { id = "model1887", name = "Model 1887", desc = "Lever-action 12-gauge shotgun", carry = CARRY_BACK },
    { id = "winchester1200", name = "W1200", desc = "Classic pump-action shotgun", carry = CARRY_BACK }
}

local WEAPONS_LMG = {
    { id = "l86", name = "L86 LSW", desc = "Magazine-fed light support weapon", carry = CARRY_BACK },
    { id = "rpd", name = "RPD", desc = "7.62mm belt-fed light machine gun", carry = CARRY_BACK },
    { id = "mg4", name = "MG4", desc = "5.56mm high-capacity belt-fed machine gun", carry = CARRY_BACK },
    { id = "aug", name = "AUG HBAR", desc = "Heavy-barreled light machine gun", carry = CARRY_BACK },
    { id = "m240", name = "M240", desc = "Heavy belt-fed general-purpose machine gun", carry = CARRY_BACK }
}

local WEAPONS_SNIPER = {
    { id = "cheytac", name = "Intervention (CheyTac M200)", desc = ".408 CheyTac bolt-action sniper rifle", carry = CARRY_BACK },
    { id = "barrett", name = "Barrett .50cal", desc = "Semi-automatic heavy anti-materiel sniper rifle", carry = CARRY_BACK },
    { id = "m14_scoped", name = "M14 EBR (Scoped)", desc = "Precision marksman rifle", carry = CARRY_BACK },
    { id = "m14ebr_thermal", name = "M14 EBR (Thermal)", desc = "M14 EBR equipped with thermal scope", carry = CARRY_BACK },
    { id = "dragunov", name = "Dragunov SVD", desc = "Semi-automatic designated marksman sniper rifle", carry = CARRY_BACK },
    { id = "wa2000", name = "WA2000", desc = "Bullpup semi-automatic sniper rifle", carry = CARRY_BACK }
}

local WEAPONS_HANDGUNS = {
    { id = "beretta", name = "M9 Beretta", desc = "Standard military sidearm 9mm", carry = CARRY_HIP },
    { id = "usp", name = "USP .45", desc = "Tactical sidearm .45 ACP", carry = CARRY_HIP },
    { id = "coltanaconda", name = ".44 Magnum (Colt Anaconda)", desc = "High stopping power revolver", carry = CARRY_HIP },
    { id = "deserteagle", name = "Desert Eagle", desc = "Heavy .50 AE magnum pistol", carry = CARRY_HIP },
    { id = "colt45", name = "M1911 .45", desc = "Classic .45 ACP military pistol", carry = CARRY_HIP },
    { id = "glock", name = "G18 (Glock)", desc = "Fully automatic machine pistol", carry = CARRY_HIP },
    { id = "m93r", name = "M93 Raffica", desc = "3-round burst machine pistol", carry = CARRY_BACK },
    { id = "tmp", name = "TMP / MP9", desc = "Rapid-fire compact machine pistol", carry = CARRY_HIP },
    { id = "pp2000", name = "PP2000", desc = "Compact Russian machine pistol", carry = CARRY_HIP }
}

local WEAPONS_LAUNCHERS = {
    { id = "m79", name = "M79 (Thumper)", desc = "Break-action 40mm grenade launcher", carry = CARRY_BACK },
    { id = "rpg", name = "RPG-7", desc = "Unguided rocket propelled grenade", carry = CARRY_BACK },
    { id = "at4", name = "AT4", desc = "Single-shot disposable anti-armor rocket", carry = CARRY_BACK },
    { id = "javelin", name = "Javelin", desc = "Lock-on top-attack heavy guided missile", carry = CARRY_BACK },
    { id = "stinger", name = "Stinger", desc = "Surface-to-air anti-aircraft missile launcher", carry = CARRY_BACK }
}

local WEAPONS_SPECIAL_MELEE = {
    { id = "ending_knife", name = "Ending Knife", desc = "The iconic final confrontation commando knife", carry = CARRY_HIP },
    { id = "ending_knife_bloody", name = "Bloody Ending Knife", desc = "Blood-stained campaign knife", carry = CARRY_HIP },
    { id = "h2_cheatcommandoknife", name = "Cheat Commando Bayonet", desc = "Green Beret high-damage bayonet blade", carry = CARRY_HIP },
    { id = "h2_cheatpickaxe", name = "Cheat Climbing Pickaxe", desc = "Dual ice pickaxe melee weapon", carry = CARRY_OFFHAND },
    { id = "ice_picker", name = "Cliffhanger Ice Pick", desc = "Story ice climbing pick tool", carry = CARRY_OFFHAND },
    { id = "ice_picker_bigjump", name = "Cliffhanger Big Jump Ice Pick", desc = "Ice pick configured for deep leaps", carry = CARRY_OFFHAND },
    { id = "riot_shield", name = "Riot Shield", desc = "Ballistic blast and bullet shield (arm-mounted in VR)", carry = CARRY_BACK }
}

local WEAPONS_SPECIAL_MISSION = {
    { id = "remote_missile_detonator", name = "AGM / Predator Laptop", desc = "Tactical remote missile control notebook unit", carry = CARRY_OFFHAND },
    { id = "remote_missile_detonator_finite", name = "AGM Laptop (Finite)", desc = "Tactical remote missile unit (finite missiles)", carry = CARRY_OFFHAND },
    { id = "usp_laserdesignator", name = "Laser Target Designator", desc = "Arcadia / Exodus artillery and Stryker designator", carry = CARRY_BELLY },
    { id = "sentry_minigun", name = "Deployable Sentry Turret", desc = "Automated deployable minigun sentry gun", carry = CARRY_OFFHAND },
    { id = "c4", name = "C4 Explosives & Detonator", desc = "Remote detonated plastic explosives", carry = CARRY_OFFHAND },
    { id = "claymore", name = "Claymore Anti-Personnel Mines", desc = "Directional tripwire laser mines", carry = CARRY_OFFHAND },
    { id = "flare", name = "Whisky Hotel Signal Flare", desc = "Emergency green rooftop signaling flare", carry = CARRY_OFFHAND },
    { id = "airdrop_marker", name = "Care Package Airdrop Canister", desc = "Killstreak airdrop supply smoke marker", carry = CARRY_OFFHAND },
    { id = "airdrop_sentry_marker", name = "Sentry Airdrop Marker", desc = "Care package marker calling in a sentry gun", carry = CARRY_OFFHAND },
    { id = "airdrop_mega_marker", name = "Emergency Airdrop Marker", desc = "Multi-crate emergency air drop marker", carry = CARRY_OFFHAND }
}

local WEAPONS_THROWABLES = {
    { id = "fraggrenade", name = "M67 Frag Grenade", desc = "Standard fragmentation hand grenade", carry = CARRY_OFFHAND },
    { id = "semtex", name = "Semtex Sticky Grenade", desc = "Timed adhesive explosive grenade", carry = CARRY_OFFHAND },
    { id = "flash_grenade", name = "Flashbang", desc = "Tactical blinding / disorienting grenade", carry = CARRY_OFFHAND },
    { id = "smoke_grenade", name = "Smoke Grenade", desc = "Concealment smoke screen", carry = CARRY_OFFHAND },
    { id = "h2_cheatpomegrenade", name = "Cheat Pomegranate Grenade", desc = "Explosive pomegranate fruit grenade", carry = CARRY_OFFHAND },
    { id = "h2_cheatfootball", name = "Cheat Football / Soccer Ball", desc = "Bouncing soccer ball explosive", carry = CARRY_OFFHAND }
}

local MODELS_MISSION_ITEMS = {
    { id = "h2_viewmodel_uav_control_unit", name = "AGM Control Unit (Laptop)", desc = "Detailed predator drone console model" },
    { id = "h2_viewmodel_laser_designator", name = "Laser Target Designator", desc = "Targeting binoculars / designator model" },
    { id = "viewmodel_ice_picker", name = "Ice Climbing Axe (Right)", desc = "Cliffhanger technical climbing axe model" },
    { id = "viewmodel_ice_picker_03", name = "Ice Climbing Axe (Left)", desc = "Cliffhanger technical climbing axe model #2" },
    { id = "h2_viewmodel_flare", name = "Signal Road Flare", desc = "Whisky Hotel green illumination flare model" },
    { id = "viewmodel_commando_knife", name = "Commando Combat Knife", desc = "Standard military combat knife model" },
    { id = "viewmodel_commando_knife_bloody", name = "Bloody Commando Knife", desc = "Bloodied combat knife model" },
    { id = "wpn_h1_melee_rifle_bayonet_vm", name = "Rifle Bayonet Knife", desc = "Green Beret tactical bayonet model" },
    { id = "h2_cheat_pomegranate", name = "Pomegranate Prop", desc = "Pomegranate fruit projectile model" },
    { id = "h2_viewmodel_cheat_soccer_ball", name = "Soccer Ball Prop", desc = "Physics soccer ball prop model" },
    { id = "com_laptop_open", name = "Enemy Intel Laptop (Open)", desc = "Campaign collectible enemy intel laptop" },
    { id = "com_laptop_closed", name = "Intel Laptop (Closed)", desc = "Closed tactical field laptop" },
    { id = "prop_briefcase", name = "Arcadia Panic Room Briefcase", desc = "Mission objective documents briefcase" },
    { id = "dsm_unit", name = "Estate DSM Transfer Unit", desc = "Makarov's estate DSM data transfer module" },
    { id = "vehicle_uav", name = "MQ-1 Predator Drone", desc = "Airborne reconnaissance & strike drone model" },
    { id = "weapon_claymore", name = "Claymore Mine Model", desc = "M18A1 directional mine ground model" },
    { id = "weapon_c4", name = "C4 Block Model", desc = "Military C4 satchel explosive pack" }
}

local NPCS_AND_CHARACTERS = {
    { id = "body_hero_soap_arctic", name = "Soap MacTavish (Cliffhanger)", desc = "Captain MacTavish in winter arctic gear" },
    { id = "body_hero_price_gulag", name = "Captain Price (Gulag)", desc = "Captain Price upon rescue from the Gulag" },
    { id = "body_hero_ghost_arctic", name = "Ghost (Cliffhanger)", desc = "Simon 'Ghost' Riley in arctic winter gear" },
    { id = "body_hero_shepherd", name = "General Shepherd", desc = "Commander of Task Force 141" },
    { id = "body_makarov", name = "Vladimir Makarov", desc = "Leader of the Ultranationalist faction" },
    { id = "body_hero_roach", name = "Gary 'Roach' Sanderson", desc = "TF141 operative player model" },
    { id = "body_us_army_rifleman", name = "US Army Ranger (Rifleman)", desc = "Standard US Army Ranger infantry" },
    { id = "body_russian_arctic_assault", name = "Russian Soldier (Arctic)", desc = "Russian Federation arctic special forces" },
    { id = "body_russian_urban_assault", name = "Russian Soldier (Urban)", desc = "Russian Federation urban warfare infantry" },
    { id = "body_militia_assault", name = "Rio Favela Militia Fighter", desc = "Brazilian militia insurgent" },
    { id = "body_shadow_company_assault", name = "Shadow Company Elite Mercenary", desc = "General Shepherd's private elite PMCs" },
    { id = "body_juggernaut", name = "Juggernaut Heavy Assault", desc = "Armored explosive-resistant heavy unit" }
}

-- Populate weapon list menu helper
local function PopulateWeaponList(menu, list)
    for _, item in ipairs(list) do
        local where = item.carry and CARRY_TEXT[item.carry]
        Button(menu, item.name, item.desc .. ". " .. (where or "")
                .. " [give " .. item.id .. "]", function()
            ExecCmdNotify("give " .. item.id, "Given: " .. item.name)
        end)
    end
end

-- Populate model spawn menu helper
local function PopulateModelList(menu, list)
    for _, item in ipairs(list) do
        Button(menu, item.name, item.desc .. " [static model: spawn_xmodel " .. item.id .. "]", function()
            ExecCmdNotify("spawn_xmodel " .. item.id, "Placed: " .. item.name)
        end)
    end
end

-- Submenu Registrations
LUI.MenuBuilder.registerType("cheats_ar_menu", function(root)
    return CreateSubmenu(root, "Assault Rifles", function(menu)
        PopulateWeaponList(menu, WEAPONS_AR)
    end)
end)

LUI.MenuBuilder.registerType("cheats_smg_menu", function(root)
    return CreateSubmenu(root, "Submachine Guns", function(menu)
        PopulateWeaponList(menu, WEAPONS_SMG)
    end)
end)

LUI.MenuBuilder.registerType("cheats_shotgun_menu", function(root)
    return CreateSubmenu(root, "Shotguns", function(menu)
        PopulateWeaponList(menu, WEAPONS_SHOTGUN)
    end)
end)

LUI.MenuBuilder.registerType("cheats_lmg_menu", function(root)
    return CreateSubmenu(root, "Light Machine Guns", function(menu)
        PopulateWeaponList(menu, WEAPONS_LMG)
    end)
end)

LUI.MenuBuilder.registerType("cheats_sniper_menu", function(root)
    return CreateSubmenu(root, "Sniper & Marksman Rifles", function(menu)
        PopulateWeaponList(menu, WEAPONS_SNIPER)
    end)
end)

LUI.MenuBuilder.registerType("cheats_handgun_menu", function(root)
    return CreateSubmenu(root, "Handguns & Machine Pistols", function(menu)
        PopulateWeaponList(menu, WEAPONS_HANDGUNS)
    end)
end)

LUI.MenuBuilder.registerType("cheats_launcher_menu", function(root)
    return CreateSubmenu(root, "Launchers & Heavy", function(menu)
        PopulateWeaponList(menu, WEAPONS_LAUNCHERS)
    end)
end)

LUI.MenuBuilder.registerType("cheats_melee_menu", function(root)
    return CreateSubmenu(root, "Special Melee & Knives", function(menu)
        PopulateWeaponList(menu, WEAPONS_SPECIAL_MELEE)
    end)
end)

LUI.MenuBuilder.registerType("cheats_mission_menu", function(root)
    return CreateSubmenu(root, "Mission & Story Items", function(menu)
        PopulateWeaponList(menu, WEAPONS_SPECIAL_MISSION)
    end)
end)

LUI.MenuBuilder.registerType("cheats_throwable_menu", function(root)
    return CreateSubmenu(root, "Throwables & Cheat Fun", function(menu)
        PopulateWeaponList(menu, WEAPONS_THROWABLES)
    end)
end)

LUI.MenuBuilder.registerType("cheats_models_menu", function(root)
    return CreateSubmenu(root, "Place Prop Models (Static)", function(menu, div)
        div(menu, "Scene Cleanup")
        Button(menu, "^1[CLEAR ALL SPAWNED MODELS]^7", "Remove all models spawned into the scene", function()
            ExecCmdNotify("clear_spawned_xmodels", "Cleared placed models")
        end)

        div(menu, "Mission Props (Static, No Collision)")
        PopulateModelList(menu, MODELS_MISSION_ITEMS)
    end)
end)

LUI.MenuBuilder.registerType("cheats_characters_menu", function(root)
    return CreateSubmenu(root, "Characters & NPCs", function(menu, div)
        div(menu, "Living Combat AI Spawner")
        -- The GSC side (h2-mod/scripts/actor_spawner.gsc) polls this dvar and
        -- clears it on read, so it acts as a one-shot request rather than a mode.
        -- actor_spawner.gsc iprintln's the actual outcome a moment later, so
        -- these only confirm that the request was sent.
        SetChoice(menu, "^2[SPAWN ENEMY SOLDIER (AI)]^7", "cheat_spawn_ai", "axis",
            "Spawns a live enemy soldier with AI, a weapon, and combat behaviour.",
            "Requested enemy soldier")
        SetChoice(menu, "^2[SPAWN FRIENDLY ALLY (AI)]^7", "cheat_spawn_ai", "allies",
            "Spawns a live allied soldier with AI, a weapon, and combat behaviour.",
            "Requested friendly ally")
        SetChoice(menu, "^3[SPAWN RANDOM COMBATANT (AI)]^7", "cheat_spawn_ai", "any",
            "Spawns a live soldier from whichever spawners this level provides.",
            "Requested random combatant")

        div(menu, "Static Character Models (No AI)")
        Button(menu, "^1[CLEAR ALL SPAWNED 3D MODELS]^7", "Remove all static 3D models spawned into the scene", function()
            ExecCmdNotify("clear_spawned_xmodels", "Cleared placed models")
        end)

        PopulateModelList(menu, NPCS_AND_CHARACTERS)
    end)
end)

-- Every function on the `game` table is bound with the table itself as its
-- first parameter (`[](const game&, ...)` in ui_scripting.cpp), so these are
-- METHODS: `game:assetlist(...)`, never `game.assetlist(...)`. A dot call
-- passes the string where the table is expected and raises "table expected,
-- got string" out of the menu build. `Engine.*` is the opposite — dot calls.
local function MissionWeaponNames()
    if type(game) ~= "table" or game.assetlist == nil then
        return nil, "the game asset API is unavailable in this build"
    end
    -- assetlist throws when the asset type is unknown, and the throw would
    -- otherwise escape through LUI's dispatcher rather than this menu.
    local ok, weapons = pcall(function() return game:assetlist("weapon") end)
    if not ok then
        return nil, tostring(weapons)
    end
    return weapons
end

local function MissionWeaponLabel(name)
    if game.getweapondisplayname == nil then
        return name
    end
    local ok, display = pcall(function() return game:getweapondisplayname(name) end)
    if ok and type(display) == "string" and #display > 0 and display ~= name then
        return display .. " [" .. name .. "]"
    end
    return name
end

LUI.MenuBuilder.registerType("cheats_mission_weapons_menu", function(root)
    return CreateSubmenu(root, "Active Mission Weapons", function(menu)
        local weapons, err = MissionWeaponNames()
        if not weapons then
            Button(menu, "^1Asset list unavailable^7", err, function() end)
            return
        end

        local seen = {}
        local shown = 0
        for _, wpn in ipairs(weapons) do
            if not seen[wpn]
                and not string.find(wpn, "destructible", 1, true)
                and not string.find(wpn, "barrel", 1, true)
                and not string.find(wpn, "turret", 1, true) then
                seen[wpn] = true
                shown = shown + 1
                local label = MissionWeaponLabel(wpn)
                Button(menu, label, "Spawn active weapon: " .. wpn, function()
                    ExecCmdNotify("give " .. wpn, "Given: " .. label)
                end)
            end
        end

        if shown == 0 then
            Button(menu, "^1No weapons loaded in this level^7", "The asset list returned nothing this level loads.", function() end)
        end
    end)
end)

-- Weapons & Gear Spawner Hub
--
-- Grouped by where a weapon physically ends up in VR rather than by game
-- category, because that is what decides whether you can actually reach it.
-- Only the hip-capable group fits a waist holster; everything in the back-only
-- group competes for the single back slot, and the loser is invisible.
LUI.MenuBuilder.registerType("cheats_armory_menu", function(root)
    return CreateSubmenu(root, "Armory & Item Spawner", function(menu, div)
        div(menu, "Inventory Space")
        -- Native ownership is a 15-entry array (capacity = 15 in
        -- weapon_carry.hpp) and reconcile_instances refuses past it, so the
        -- carry system stops placing weapons. There is no Lua call in the
        -- shipped Engine surface that reports how many you are carrying, so
        -- this cannot show a live count -- it just keeps the remedy one press
        -- away from the buttons that cause the problem.
        Button(menu, "^1[CLEAR INVENTORY - TAKE ALL WEAPONS]^7", "Empties your hands and every holster. The game caps "
                .. "you at 15 owned weapons; past that, newly given weapons "
                .. "stop being placed at all. Clear here if guns stop appearing.", function()
            ExecCmdNotify("take all", "Removed all weapons")
        end)

        div(menu, "Fits a Hip Holster")
        Button(menu, "^5Handguns & Machine Pistols^7", "M9, USP .45, .44 Magnum, Desert Eagle, M1911, G18, "
                .. "TMP, PP2000. All reach a waist holster, except the M93 "
                .. "Raffica, which goes on your back.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_handgun_menu")
        end)

        Button(menu, "^4Special Melee & Knives^7", "The three commando knives reach a waist holster. The "
                .. "ice picks, pickaxe and riot shield do not -- they are "
                .. "outside VR carry entirely.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_melee_menu")
        end)

        div(menu, "Back Slot Only")
        Button(menu, "^3Assault Rifles^7", "M4A1, AK-47, SCAR-H, ACR, FAMAS, M16A4, FAL, TAR-21, F2000.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_ar_menu")
        end)

        Button(menu, "^3Submachine Guns^7", "UMP45, MP5K, P90 and the Vector go on your back; only "
                .. "the Mini-Uzi reaches a hip. A native SMG category is not a "
                .. "waist permit.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_smg_menu")
        end)

        Button(menu, "^3Shotguns^7", "SPAS-12, AA-12, M1014, Striker, Model 1887 and W1200 "
                .. "go on your back; only the Ranger reaches a hip.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_shotgun_menu")
        end)

        Button(menu, "^3Light Machine Guns^7", "RPD, M240, MG4, AUG HBAR, L86 LSW.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_lmg_menu")
        end)

        Button(menu, "^3Sniper & Marksman Rifles^7", "Intervention, Barrett .50cal, M14 EBR, Dragunov, WA2000.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_sniper_menu")
        end)

        Button(menu, "^5Launchers & Heavy^7", "RPG-7, M79 Thumper, and the AT4, Javelin and Stinger. "
                .. "Those last three are right-hand-fires-only: the left hand "
                .. "can support but not shoot.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_launcher_menu")
        end)

        div(menu, "Native Equipment Slots")
        Button(menu, "^4Mission & Story Items^7", "AGM/Predator laptop, C4, claymores, flare, sentry and "
                .. "airdrop markers stay in their native equipment slots. The "
                .. "laser designator gets its own abdominal slot.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_mission_menu")
        end)

        Button(menu, "^6Throwables & Fun Cheats^7", "Frag, Semtex, Flash, Smoke, Pomegranate and Football. "
                .. "Grenades are outside VR carry and use the native offhand.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_throwable_menu")
        end)

        div(menu, "Mission Inventory Inspection")
        Button(menu, "^2[ACTIVE MISSION WEAPONS (AUTO-DETECT)]^7", "Every weapon asset the current level actually loaded. "
                .. "Names outside this list may not exist in this mission.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_mission_weapons_menu")
        end)
    end)
end)

-- Main Cheats Menu
LUI.MenuBuilder.registerType("cheats_menu", function(root)
    local isUnlocked = IsCheatsUnlocked()
    if not isUnlocked then
        return CreateSubmenu(root, "Cheats Locked", function(menu)
            Button(menu, "^1Cheats are currently disabled^7", "Open Overlord Extras and toggle 'Enable Cheats Menu' to unlock.", function()
                LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
            end)
            Button(menu, "Open VR Extras Menu", "Configure VR settings and unlock developer cheats", function()
                LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
            end)
        end)
    end

    return CreateSubmenu(root, "Cheats & Sandbox", function(menu, div)
        div(menu, "Damage Protection")
        SetChoice(menu, "^2Protection: Godmode^7", CHEAT_HEALTH_DVAR, "god",
            "Immune to all damage. Scripted mission deaths still apply.",
            "Protection: godmode")
        SetChoice(menu, "^2Protection: Demigod^7", CHEAT_HEALTH_DVAR, "demigod",
            "Immune to damage, but still flinches and shows hit feedback.",
            "Protection: demigod")
        SetChoice(menu, "^1Protection: Off^7", CHEAT_HEALTH_DVAR, "off",
            "Take normal damage again.",
            "Protection: off")

        div(menu, "AI Targeting")
        SetChoice(menu, "^3No Target: On^7", CHEAT_NOTARGET_DVAR, "on",
            "Enemies stop targeting you. Your model is still visible.",
            "No target: on")
        SetChoice(menu, "^1No Target: Off^7", CHEAT_NOTARGET_DVAR, "off",
            "Enemies target you normally again.",
            "No target: off")

        div(menu, "Flight & Collision")
        -- No launcher preference exists for these two, so they stay native
        -- toggles and nothing re-applies them behind the menu's back.
        -- noclip prints its own "noclip ON/OFF" from C++ (command.cpp), so a
        -- toast here would duplicate it. ufo has no such message.
        Button(menu, "^5Toggle Noclip^7", "Toggle noclip through walls and terrain (noclip)", function()
            ExecCmd("noclip")
        end)

        Button(menu, "^5Toggle UFO Mode^7", "Toggle free flight camera movement (ufo)", function()
            ExecCmdNotify("ufo", "Toggled UFO mode")
        end)

        div(menu, "Sustained Ammunition")
        SetChoice(menu, "^3Sustained Ammo: Infinite^7", CHEAT_AMMO_DVAR, "infinite",
            "Never consume ammunition and never need to reload.",
            "Sustained ammo: infinite")
        SetChoice(menu, "^3Sustained Ammo: Infinite Reserve^7", CHEAT_AMMO_DVAR, "reserve",
            "Reserve ammunition stays topped up; magazines still need reloading.",
            "Sustained ammo: infinite reserve")
        SetChoice(menu, "^1Sustained Ammo: Off^7", CHEAT_AMMO_DVAR, "off",
            "Consume ammunition normally again.",
            "Sustained ammo: off")

        div(menu, "One-Shot Refills")
        Button(menu, "^2Refill Max Health^7", "Instantly restore player health to 100%", function()
            ExecCmdNotify("give health", "Health restored")
        end)

        Button(menu, "^3Refill Current Ammo^7", "Refill magazines and reserve ammo for current weapon", function()
            ExecCmdNotify("give ammo", "Ammo refilled")
        end)

        Button(menu, "^3Refill All Weapons Ammo^7", "Refill ammo for all carried weapons and modules", function()
            ExecCmdNotify("give allammo", "Ammo refilled for all weapons")
        end)

        div(menu, "Armory & Entity Spawners")
        Button(menu, "^6[ARMORY (WEAPONS & ITEMS)]^7", "Browse and spawn every weapon, launcher, and item in the game", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_armory_menu")
        end)

        Button(menu, "^4[SPAWN CHARACTERS & LIVING AI]^7", "Spawn living combat AI, or place static character models with no AI", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_characters_menu")
        end)

        Button(menu, "^4[PLACE PROP MODELS (STATIC)]^7", "Place static models in front of you: laptops, briefcase, "
                .. "DSM, UAV, ice picks. No collision or physics.", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_models_menu")
        end)

        div(menu, "Inventory Control")
        Button(menu, "^1Drop Current Weapon^7", "Drop the currently active weapon onto the ground", function()
            ExecCmdNotify("dropweapon", "Dropped current weapon")
        end)

        Button(menu, "^1Take All Weapons^7", "Empty your hands and every holster. Also the fix when "
                .. "given weapons stop appearing: the game owns at most 15 at "
                .. "once, and past that the carry system stops placing them.", function()
            ExecCmdNotify("take all", "Removed all weapons")
        end)
    end)
end)

-- Hook into sp_pause_menu
if LUI.onmenuopen then
    LUI.onmenuopen("sp_pause_menu", function(element)
        local menu = element:getFirstChild()
        if not menu or not menu.AddButton then
            return
        end

        local isUnlocked = IsCheatsUnlocked()
        if not isUnlocked then
            Button(menu, "^1CHEATS (LOCKED)^7", "Cheats are locked. Go to VR EXTRAS to toggle 'Enable Cheats Menu'.", function()
                LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
            end)
            return
        end

        Button(menu, "^3CHEATS^7", "Access godmode, noclip, ammo refills, weapons, and entity spawner", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_menu")
        end)
    end)
end

-- Last line of the module, so seeing it in the console means every registration
-- above ran. Without it, a silent load is indistinguishable from the early
-- `return` on a missing _common.
print("[Overlord Cheats] Cheats & Sandbox menu registered")
