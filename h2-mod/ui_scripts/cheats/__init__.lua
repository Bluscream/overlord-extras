-- Cheats Menu Module for Overlord / MW2CR
-- Provides an in-game Cheats submenu in the Pause Menu (and Frontend Campaign Menu)
-- Supports Godmode, Demigod, Notarget, Noclip, UFO, Refills, Full Weapon Armory,
-- Special Knives, Mission Items, Throwables & Fun Cheats, and Model Spawning.

if (Engine.InFrontend and Engine.InFrontend()) then
    -- Also allow exploring from campaign menu if desired, or skip
end

local function ExecCmd(cmd)
    Engine.Exec(cmd)
end

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

-- Weapon category tables (using authentic Call of Duty MW2 internal weapon IDs)
local WEAPONS_AR = {
    { id = "m4", name = "M4A1", desc = "Fully automatic assault rifle" },
    { id = "m4m203_reflex", name = "M4A1 w/ M203 & Reflex", desc = "M4A1 equipped with grenade launcher and optic" },
    { id = "m4_silencer", name = "M4A1 Suppressed", desc = "M4A1 with silencer" },
    { id = "m16", name = "M16A4", desc = "3-round burst assault rifle" },
    { id = "m16_grenadier", name = "M16A4 Grenadier", desc = "M16A4 with M203 grenade launcher" },
    { id = "ak47", name = "AK-47", desc = "High caliber fully automatic rifle" },
    { id = "ak47_grenadier", name = "AK-47 w/ GP-25", desc = "AK-47 with GP-25 underbarrel grenade launcher" },
    { id = "scar_h", name = "SCAR-H", desc = "High damage battle rifle" },
    { id = "famas", name = "FAMAS", desc = "3-round burst bullpup assault rifle" },
    { id = "fal", name = "FAL", desc = "Semi-automatic battle rifle" },
    { id = "tavor", name = "TAR-21 (Tavor)", desc = "Bullpup assault rifle with high fire rate" },
    { id = "masada", name = "ACR (Masada)", desc = "Low recoil assault rifle" },
    { id = "fn2000", name = "F2000", desc = "High rate of fire bullpup assault rifle" }
}

local WEAPONS_SMG = {
    { id = "mp5k", name = "MP5K", desc = "Compact 9mm submachine gun" },
    { id = "ump45", name = "UMP45", desc = "High stopping power .45 ACP submachine gun" },
    { id = "uzi", name = "Mini-Uzi", desc = "High fire rate open-bolt submachine gun" },
    { id = "p90", name = "P90", desc = "50-round top-loading high capacity submachine gun" },
    { id = "kriss", name = "Vector (KRISS)", desc = "Extremely high fire rate submachine gun" }
}

local WEAPONS_SHOTGUN = {
    { id = "spas12", name = "SPAS-12", desc = "Pump-action combat shotgun" },
    { id = "aa12", name = "AA-12", desc = "Fully automatic box-fed shotgun" },
    { id = "m1014", name = "M1014", desc = "Semi-automatic combat shotgun" },
    { id = "striker", name = "Striker", desc = "Revolving cylinder combat shotgun" },
    { id = "ranger", name = "Ranger", desc = "Over-under double-barrel break-action shotgun" },
    { id = "model1887", name = "Model 1887", desc = "Lever-action 12-gauge shotgun" },
    { id = "winchester1200", name = "W1200", desc = "Classic pump-action shotgun" }
}

local WEAPONS_LMG = {
    { id = "l86", name = "L86 LSW", desc = "Magazine-fed light support weapon" },
    { id = "rpd", name = "RPD", desc = "7.62mm belt-fed light machine gun" },
    { id = "mg4", name = "MG4", desc = "5.56mm high-capacity belt-fed machine gun" },
    { id = "aug", name = "AUG HBAR", desc = "Heavy-barreled light machine gun" },
    { id = "m240", name = "M240", desc = "Heavy belt-fed general-purpose machine gun" }
}

local WEAPONS_SNIPER = {
    { id = "cheytac", name = "Intervention (CheyTac M200)", desc = ".408 CheyTac bolt-action sniper rifle" },
    { id = "barrett", name = "Barrett .50cal", desc = "Semi-automatic heavy anti-materiel sniper rifle" },
    { id = "m14_scoped", name = "M14 EBR (Scoped)", desc = "Precision marksman rifle" },
    { id = "m14ebr_thermal", name = "M14 EBR (Thermal)", desc = "M14 EBR equipped with thermal scope" },
    { id = "dragunov", name = "Dragunov SVD", desc = "Semi-automatic designated marksman sniper rifle" },
    { id = "wa2000", name = "WA2000", desc = "Bullpup semi-automatic sniper rifle" }
}

local WEAPONS_HANDGUNS = {
    { id = "beretta", name = "M9 Beretta", desc = "Standard military sidearm 9mm" },
    { id = "usp", name = "USP .45", desc = "Tactical sidearm .45 ACP" },
    { id = "coltanaconda", name = ".44 Magnum (Colt Anaconda)", desc = "High stopping power revolver" },
    { id = "deserteagle", name = "Desert Eagle", desc = "Heavy .50 AE magnum pistol" },
    { id = "colt45", name = "M1911 .45", desc = "Classic .45 ACP military pistol" },
    { id = "glock", name = "G18 (Glock)", desc = "Fully automatic machine pistol" },
    { id = "m93r", name = "M93 Raffica", desc = "3-round burst machine pistol" },
    { id = "tmp", name = "TMP / MP9", desc = "Rapid-fire compact machine pistol" },
    { id = "pp2000", name = "PP2000", desc = "Compact Russian machine pistol" }
}

local WEAPONS_LAUNCHERS = {
    { id = "m79", name = "M79 (Thumper)", desc = "Break-action 40mm grenade launcher" },
    { id = "rpg", name = "RPG-7", desc = "Unguided rocket propelled grenade" },
    { id = "at4", name = "AT4", desc = "Single-shot disposable anti-armor rocket" },
    { id = "javelin", name = "Javelin", desc = "Lock-on top-attack heavy guided missile" },
    { id = "stinger", name = "Stinger", desc = "Surface-to-air anti-aircraft missile launcher" }
}

local WEAPONS_SPECIAL_MELEE = {
    { id = "ending_knife", name = "Ending Knife", desc = "The iconic final confrontation commando knife" },
    { id = "ending_knife_bloody", name = "Bloody Ending Knife", desc = "Blood-stained campaign knife" },
    { id = "h2_cheatcommandoknife", name = "Cheat Commando Bayonet", desc = "Green Beret high-damage bayonet blade" },
    { id = "h2_cheatpickaxe", name = "Cheat Climbing Pickaxe", desc = "Dual ice pickaxe melee weapon" },
    { id = "ice_picker", name = "Cliffhanger Ice Pick", desc = "Story ice climbing pick tool" },
    { id = "ice_picker_bigjump", name = "Cliffhanger Big Jump Ice Pick", desc = "Ice pick configured for deep leaps" },
    { id = "riot_shield", name = "Riot Shield", desc = "Ballistic blast and bullet shield (arm-mounted in VR)" }
}

local WEAPONS_SPECIAL_MISSION = {
    { id = "remote_missile_detonator", name = "AGM / Predator Laptop", desc = "Tactical remote missile control notebook unit" },
    { id = "remote_missile_detonator_finite", name = "AGM Laptop (Finite)", desc = "Tactical remote missile unit (finite missiles)" },
    { id = "usp_laserdesignator", name = "Laser Target Designator", desc = "Arcadia / Exodus artillery and Stryker designator" },
    { id = "sentry_minigun", name = "Deployable Sentry Turret", desc = "Automated deployable minigun sentry gun" },
    { id = "c4", name = "C4 Explosives & Detonator", desc = "Remote detonated plastic explosives" },
    { id = "claymore", name = "Claymore Anti-Personnel Mines", desc = "Directional tripwire laser mines" },
    { id = "flare", name = "Whisky Hotel Signal Flare", desc = "Emergency green rooftop signaling flare" },
    { id = "airdrop_marker", name = "Care Package Airdrop Canister", desc = "Killstreak airdrop supply smoke marker" },
    { id = "airdrop_sentry_marker", name = "Sentry Airdrop Marker", desc = "Care package marker calling in a sentry gun" },
    { id = "airdrop_mega_marker", name = "Emergency Airdrop Marker", desc = "Multi-crate emergency air drop marker" }
}

local WEAPONS_THROWABLES = {
    { id = "fraggrenade", name = "M67 Frag Grenade", desc = "Standard fragmentation hand grenade" },
    { id = "semtex", name = "Semtex Sticky Grenade", desc = "Timed adhesive explosive grenade" },
    { id = "flash_grenade", name = "Flashbang", desc = "Tactical blinding / disorienting grenade" },
    { id = "smoke_grenade", name = "Smoke Grenade", desc = "Concealment smoke screen" },
    { id = "h2_cheatpomegrenade", name = "Cheat Pomegranate Grenade", desc = "Explosive pomegranate fruit grenade" },
    { id = "h2_cheatfootball", name = "Cheat Football / Soccer Ball", desc = "Bouncing soccer ball explosive" }
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
    { id = "h2_cheat_soccer_ball", name = "Soccer Ball Prop", desc = "Physics soccer ball prop model" },
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
        menu:AddButton(item.name, function()
            ExecCmd("give " .. item.id)
        end, nil, true, nil, {
            desc_text = item.desc .. " [Command: give " .. item.id .. "]"
        })
    end
end

-- Populate model spawn menu helper
local function PopulateModelList(menu, list)
    for _, item in ipairs(list) do
        menu:AddButton(item.name, function()
            ExecCmd("spawn_xmodel " .. item.id)
        end, nil, true, nil, {
            desc_text = item.desc .. " [Command: spawn_xmodel " .. item.id .. "]"
        })
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
    return CreateSubmenu(root, "Spawn Props & Equipment", function(menu, div)
        div(menu, "Scene Cleanup")
        menu:AddButton("^1[CLEAR ALL SPAWNED MODELS]^7", function()
            ExecCmd("clear_spawned_xmodels")
        end, nil, true, nil, {
            desc_text = "Remove all models spawned into the scene"
        })

        div(menu, "Mission Props & Interactive Gear")
        PopulateModelList(menu, MODELS_MISSION_ITEMS)
    end)
end)

LUI.MenuBuilder.registerType("cheats_characters_menu", function(root)
    return CreateSubmenu(root, "Characters & NPCs", function(menu, div)
        div(menu, "Living Combat AI Spawner")
        menu:AddButton("^2[SPAWN ENEMY SOLDIER (AI)]^7", function()
            if Engine.SetDvarString then
                Engine.SetDvarString("cheat_spawn_ai", "axis")
            else
                Engine.Exec("set cheat_spawn_ai axis")
            end
        end, nil, true, nil, {
            desc_text = "Spawns an active combat enemy soldier with AI, weapon and behavior"
        })

        menu:AddButton("^2[SPAWN FRIENDLY ALLY (AI)]^7", function()
            if Engine.SetDvarString then
                Engine.SetDvarString("cheat_spawn_ai", "allies")
            else
                Engine.Exec("set cheat_spawn_ai allies")
            end
        end, nil, true, nil, {
            desc_text = "Spawns an active friendly allied combat soldier with AI"
        })

        menu:AddButton("^3[SPAWN RANDOM COMBATANT (AI)]^7", function()
            if Engine.SetDvarString then
                Engine.SetDvarString("cheat_spawn_ai", "any")
            else
                Engine.Exec("set cheat_spawn_ai any")
            end
        end, nil, true, nil, {
            desc_text = "Spawns a random active AI soldier into the scene"
        })

        div(menu, "Static 3D Character Models")
        menu:AddButton("^1[CLEAR ALL SPAWNED 3D MODELS]^7", function()
            ExecCmd("clear_spawned_xmodels")
        end, nil, true, nil, {
            desc_text = "Remove all static 3D models spawned into the scene"
        })

        PopulateModelList(menu, NPCS_AND_CHARACTERS)
    end)
end)

LUI.MenuBuilder.registerType("cheats_mission_weapons_menu", function(root)
    return CreateSubmenu(root, "Active Mission Weapons", function(menu)
        if game and game.assetlist then
            local weapons = game.assetlist("weapon")
            local seen = {}
            for _, wpn in ipairs(weapons) do
                if not seen[wpn] and not string.find(wpn, "destructible") and not string.find(wpn, "barrel") and not string.find(wpn, "turret") then
                    seen[wpn] = true
                    local dispName = wpn
                    if game.getweapondisplayname then
                        local d = game.getweapondisplayname(wpn)
                        if d and #d > 0 and d ~= wpn then
                            dispName = d .. " [" .. wpn .. "]"
                        end
                    end
                    menu:AddButton(dispName, function()
                        ExecCmd("give " .. wpn)
                    end, nil, true, nil, {
                        desc_text = "Spawn active weapon: " .. wpn
                    })
                end
            end
        else
            menu:AddButton("Asset list unavailable", function() end)
        end
    end)
end)

-- Weapons & Gear Spawner Hub
LUI.MenuBuilder.registerType("cheats_armory_menu", function(root)
    return CreateSubmenu(root, "Armory & Item Spawner", function(menu, div)
        div(menu, "Mission Inventory Inspection")
        menu:AddButton("^2[ACTIVE MISSION WEAPONS (AUTO-DETECT)]^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_mission_weapons_menu")
        end, nil, true, nil, { desc_text = "Dynamically inspect and spawn any weapon loaded into the current mission" })

        div(menu, "Primary Firearms")
        menu:AddButton("^3Assault Rifles^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_ar_menu")
        end, nil, true, nil, { desc_text = "Spawn M4A1, AK-47, SCAR-H, ACR, FAMAS, etc." })

        menu:AddButton("^3Submachine Guns^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_smg_menu")
        end, nil, true, nil, { desc_text = "Spawn UMP45, MP5K, P90, Vector, Mini-Uzi" })

        menu:AddButton("^3Shotguns^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_shotgun_menu")
        end, nil, true, nil, { desc_text = "Spawn SPAS-12, AA-12, Model 1887, Ranger, Striker" })

        menu:AddButton("^3Light Machine Guns^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_lmg_menu")
        end, nil, true, nil, { desc_text = "Spawn RPD, M240, MG4, AUG HBAR, L86 LSW" })

        menu:AddButton("^3Sniper & Marksman Rifles^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_sniper_menu")
        end, nil, true, nil, { desc_text = "Spawn Intervention, Barrett .50cal, M14 EBR, Dragunov" })

        div(menu, "Sidearms & Heavy Ordnance")
        menu:AddButton("^5Handguns & Machine Pistols^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_handgun_menu")
        end, nil, true, nil, { desc_text = "Spawn M9, USP .45, .44 Magnum, Desert Eagle, G18, Raffica" })

        menu:AddButton("^5Launchers & Heavy^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_launcher_menu")
        end, nil, true, nil, { desc_text = "Spawn RPG-7, AT4, Javelin, Stinger, M79 Thumper" })

        div(menu, "Melee, Equipment & Story Items")
        menu:AddButton("^4Special Melee & Knives^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_melee_menu")
        end, nil, true, nil, { desc_text = "Spawn Ending Knife, Bloody Knife, Commando Bayonet, Ice Picks" })

        menu:AddButton("^4Mission & Story Items^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_mission_menu")
        end, nil, true, nil, { desc_text = "Spawn AGM/Predator Laptop, Laser Designator, C4, Claymores, Flare" })

        menu:AddButton("^6Throwables & Fun Cheats^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_throwable_menu")
        end, nil, true, nil, { desc_text = "Spawn Frag, Semtex, Flash, Pomegranate, Football" })
    end)
end)

-- Main Cheats Menu
LUI.MenuBuilder.registerType("cheats_menu", function(root)
    local isUnlocked = Engine.GetDvarBool and Engine.GetDvarBool("overlord_cheats_enabled")
    if not isUnlocked then
        return CreateSubmenu(root, "Cheats Locked", function(menu)
            menu:AddButton("^1Cheats are currently disabled^7", function()
                LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
            end, nil, true, nil, {
                desc_text = "Open Overlord Extras and toggle 'Enable Cheats Menu' to unlock."
            })
            menu:AddButton("Open VR Extras Menu", function()
                LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
            end, nil, true, nil, {
                desc_text = "Configure VR settings and unlock developer cheats"
            })
        end)
    end

    return CreateSubmenu(root, "Cheats & Sandbox", function(menu, div)
        div(menu, "Invulnerability & Flight")
        menu:AddButton("^2Toggle Godmode^7", function()
            ExecCmd("god")
        end, nil, true, nil, { desc_text = "Toggle invulnerability against all damage (god)" })

        menu:AddButton("^2Toggle Demigod^7", function()
            ExecCmd("demigod")
        end, nil, true, nil, { desc_text = "Toggle demigod mode (invulnerable with health flinching)" })

        menu:AddButton("^3Toggle No Target (Stealth)^7", function()
            ExecCmd("notarget")
        end, nil, true, nil, { desc_text = "Toggle enemies ignoring player presence (notarget)" })

        menu:AddButton("^5Toggle Noclip^7", function()
            ExecCmd("noclip")
        end, nil, true, nil, { desc_text = "Toggle noclip through walls and terrain (noclip)" })

        menu:AddButton("^5Toggle UFO Mode^7", function()
            ExecCmd("ufo")
        end, nil, true, nil, { desc_text = "Toggle free flight camera movement (ufo)" })

        div(menu, "Health & Ammunition")
        menu:AddButton("^2Refill Max Health^7", function()
            ExecCmd("give health")
        end, nil, true, nil, { desc_text = "Instantly restore player health to 100%" })

        menu:AddButton("^3Refill Current Ammo^7", function()
            ExecCmd("give ammo")
        end, nil, true, nil, { desc_text = "Refill magazines and reserve ammo for current weapon" })

        menu:AddButton("^3Refill All Weapons Ammo^7", function()
            ExecCmd("give allammo")
        end, nil, true, nil, { desc_text = "Refill ammo for all carried weapons and modules" })

        div(menu, "Armory & Entity Spawners")
        menu:AddButton("^6[ARMORY (WEAPONS & ITEMS)]^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_armory_menu")
        end, nil, true, nil, { desc_text = "Browse and spawn every weapon, launcher, and item in the game" })

        menu:AddButton("^4[SPAWN CHARACTERS & LIVING AI]^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_characters_menu")
        end, nil, true, nil, { desc_text = "Spawn living combat AI soldiers or 3D character models" })

        menu:AddButton("^4[SPAWN PROPS & INTERACTIVE EQUIPMENT]^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_models_menu")
        end, nil, true, nil, { desc_text = "Spawn 3D world models: Laptops, Briefcase, DSM, UAV, Ice Picks" })

        div(menu, "Inventory Control")
        menu:AddButton("^1Drop Current Weapon^7", function()
            ExecCmd("dropweapon")
        end, nil, true, nil, { desc_text = "Drop the currently active weapon onto the ground" })

        menu:AddButton("^1Take All Weapons^7", function()
            ExecCmd("take all")
        end, nil, true, nil, { desc_text = "Remove all weapons from inventory (empty hands)" })
    end)
end)

-- Hook into sp_pause_menu
if LUI.onmenuopen then
    LUI.onmenuopen("sp_pause_menu", function(element)
        local menu = element:getFirstChild()
        if not menu or not menu.AddButton then
            return
        end

        local isUnlocked = Engine.GetDvarBool and Engine.GetDvarBool("overlord_cheats_enabled")
        if not isUnlocked then
            menu:AddButton("^1CHEATS (LOCKED)^7", function()
                LUI.FlowManager.RequestAddMenu(nil, "overlord_extras_menu")
            end, nil, true, nil, {
                desc_text = "Cheats are locked. Go to VR EXTRAS to toggle 'Enable Cheats Menu'."
            })
            return
        end

        menu:AddButton("^3CHEATS^7", function()
            LUI.FlowManager.RequestAddMenu(nil, "cheats_menu")
        end, nil, true, nil, {
            desc_text = "Access godmode, noclip, ammo refills, weapons, and entity spawner"
        })
    end)
end
