// Live AI Actor Spawner for Modern Warfare 2 Campaign Remastered / Overlord
//
// Watches the 'cheat_spawn_ai' dvar for a one-shot team request ("axis",
// "allies" or "any") written by the Cheats pause menu, and spawns one AI actor
// in front of the player.
//
// A dvar poll is used because GSC cannot receive a host event. The dvar is
// cleared before the spawn runs, so a request fires exactly once even if the
// spawn itself fails.

// Note: GSC has no file-scope constants in this dialect, so the two tunables
// (poll interval and spawn distance) are locals at their point of use.

main()
{
    thread watch_spawner_dvar();
}

watch_spawner_dvar()
{
    level endon("game_ended");

    // One server frame at 20Hz; the body only reads a dvar.
    poll_interval = 0.2;

    // Registering the dvar empty means the first poll cannot read a stale value
    // left over from a previous level.
    setdvar("cheat_spawn_ai", "");

    for (;;)
    {
        team_cmd = getdvar("cheat_spawn_ai");
        if (isdefined(team_cmd) && team_cmd != "")
        {
            // Clear before acting: a spawn failure must not re-fire next tick.
            setdvar("cheat_spawn_ai", "");
            spawn_actor_near_player(team_cmd);
        }
        wait poll_interval;
    }
}

spawn_actor_near_player(team)
{
    if (!isdefined(level.player))
    {
        return;
    }
    player = level.player;

    spawners = [];
    if (team == "axis" || team == "enemy")
    {
        spawners = getspawnerteamarray("axis");
    }
    else if (team == "allies" || team == "friendly")
    {
        spawners = getspawnerteamarray("allies");
    }

    if (!isdefined(spawners) || spawners.size == 0)
    {
        spawners = getspawnerarray();
    }

    if (!isdefined(spawners) || spawners.size == 0)
    {
        iprintln("^1No spawners found in this map^7");
        return;
    }

    spawner = spawners[randomint(spawners.size)];
    if (!isdefined(spawner))
    {
        return;
    }

    // `spawner.count` is the level's own budget for that spawner. Setting it to
    // 999 and walking away made the spawner effectively infinite for the rest of
    // the mission, so borrow one spawn and put the original count back.
    had_count = isdefined(spawner.count);
    if (had_count)
    {
        previous_count = spawner.count;
    }
    spawner.count = 1;

    actor = spawner stalingradspawn();

    if (had_count)
    {
        spawner.count = previous_count;
    }

    if (!isdefined(actor))
    {
        iprintln("^1Failed to spawn soldier (spawner exhausted)^7");
        return;
    }

    // Track what this script spawned so a level can be cleaned up without
    // touching actors the mission itself placed.
    if (!isdefined(level.overlord_spawned_actors))
    {
        level.overlord_spawned_actors = [];
    }
    level.overlord_spawned_actors[level.overlord_spawned_actors.size] = actor;

    // Distance in front of the player to place the actor, in game units.
    forward_distance = 180;
    forward = anglestoforward(player.angles);
    target_pos = player.origin + (forward[0] * forward_distance, forward[1] * forward_distance, 0);
    actor forceteleport(target_pos, player.angles + (0, 180, 0));
    iprintln("^2Spawned AI soldier (" + team + ")^7");
}
