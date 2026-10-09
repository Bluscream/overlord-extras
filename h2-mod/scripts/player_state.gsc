// Player state publisher for Modern Warfare 2 Campaign Remastered / Overlord
//
// WHY THIS EXISTS
// The LUI `Engine` table exposes no live player state. Enumerating every key
// matching player/pos/angle/origin/weapon/ammo returns only menu-data and
// loadout-metadata functions -- there is no origin, no angles and no inventory
// accessor anywhere in it. GSC does have all three, so this script reads them
// and republishes them as dvars, which the host CLI can then read over the
// agent IPC bridge.
//
// WHY THE DVARS ARE WRITTEN, NEVER PROBED
// Reading a dvar that was never registered faults inside the native accessor
// (0xC0000005) -- the fault is in C++, below Lua, so a Lua `pcall` around the
// read does NOT catch it and `tostring()` on the result does not help either,
// because nothing ever reaches Lua. The only safe rule is: never ask for a name
// that might not exist. Every name below is therefore registered twice over --
// here with setdvar() before the first read, and in ui_scripts/_common with
// `seta` at UI load time, which covers the frontend where no level is loaded
// and this script has never run.
//
// Note: GSC has no file-scope constants in this dialect, so tunables are locals
// at their point of use.

// Overlord's loader calls main() from G_LoadStructs and init() from
// Scr_LoadLevel (src/client/component/gsc/script_loading.cpp). level.player
// does not exist during the structs phase, so a runtime publisher belongs in
// init().
init()
{
    thread publish_player_state();
}

publish_player_state()
{
    level endon("game_ended");

    // 4Hz. The body is a handful of dvar writes; it is deliberately slower than
    // the 20Hz used by the spawner watcher, because nothing here is latency
    // sensitive -- the host reads it on demand, not per frame.
    publish_interval = 0.25;

    // Registered empty before anything can read them, so a read during level
    // load cannot hit an unregistered name and cannot return a stale value from
    // the previous level.
    setdvar("overlord_ps_tick", "0");
    setdvar("overlord_ps_origin", "");
    setdvar("overlord_ps_angles", "");
    setdvar("overlord_ps_health", "");
    setdvar("overlord_ps_stance", "");
    setdvar("overlord_ps_weapon", "");
    setdvar("overlord_ps_weapon_count", "0");
    setdvar("overlord_ps_weapons", "");

    tick = 0;

    for (;;)
    {
        if (isdefined(level.player) && isalive(level.player))
        {
            tick = tick + 1;
            level.player publish_one_frame(tick);
        }
        wait publish_interval;
    }
}

publish_one_frame(tick)
{
    // self is the player.

    // A monotonic counter is what lets the host tell live data from a leftover
    // snapshot: the dvars persist after this thread stops (level end, death),
    // and a frozen tick is the only signal that they have gone stale.
    setdvar("overlord_ps_tick", tick);

    origin = self.origin;
    setdvar("overlord_ps_origin", int(origin[0]) + " " + int(origin[1]) + " " + int(origin[2]));

    // Rounded to whole degrees: this is for a status readout, and the
    // fractional part is noise at headset update rates.
    angles = self.angles;
    setdvar("overlord_ps_angles", int(angles[0]) + " " + int(angles[1]) + " " + int(angles[2]));

    max_health = self.maxhealth;
    if (!isdefined(max_health))
    {
        max_health = 0;
    }
    setdvar("overlord_ps_health", self.health + " " + max_health);

    setdvar("overlord_ps_stance", self getstance());

    current = self getcurrentweapon();
    if (!isdefined(current))
    {
        current = "none";
    }
    setdvar("overlord_ps_weapon", current);

    publish_inventory();
}

publish_inventory()
{
    // self is the player.
    weapons = self getweaponslistall();
    if (!isdefined(weapons))
    {
        setdvar("overlord_ps_weapon_count", "0");
        setdvar("overlord_ps_weapons", "");
        return;
    }

    setdvar("overlord_ps_weapon_count", weapons.size);

    // Native weapon ownership is a 15-entry array (capacity = 15 in
    // weapon_carry.hpp) and reconcile_instances refuses past it, so this count
    // reaching 15 is exactly when newly given weapons stop being placed. This
    // is the live count the Cheats menu could not show.
    list = "";
    for (i = 0; i < weapons.size; i++)
    {
        if (i > 0)
        {
            list = list + ",";
        }
        list = list + weapons[i];
    }
    setdvar("overlord_ps_weapons", list);
}
