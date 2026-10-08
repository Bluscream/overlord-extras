// Live AI Actor Spawner for Modern Warfare 2 Campaign Remastered / Overlord
// Listens to dvar 'cheat_spawn_ai' (e.g. "axis", "allies", "any") and spawns AI actors in front of the player.

main()
{
    thread watch_spawner_dvar();
}

watch_spawner_dvar()
{
    level endon("game_ended");
    for (;;)
    {
        team_cmd = getdvar("cheat_spawn_ai");
        if (isdefined(team_cmd) && team_cmd != "")
        {
            setdvar("cheat_spawn_ai", "");
            spawn_actor_near_player(team_cmd);
        }
        wait 0.2;
    }
}

spawn_actor_near_player(team)
{
    player = level.player;
    if (!isdefined(player))
    {
        return;
    }

    spawners = [];
    if (team == "axis" || team == "enemy")
    {
        spawners = getspawnerteamarray("axis");
    }
    else if (team == "allies" || team == "friendly")
    {
        spawners = getspawnerteamarray("allies");
    }

    if (spawners.size == 0)
    {
        spawners = getspawnerarray();
    }

    if (spawners.size == 0)
    {
        iprintln("^1No spawners found in this map^7");
        return;
    }

    spawner_idx = randomint(spawners.size);
    spawner = spawners[spawner_idx];
    spawner.count = 999;

    actor = spawner stalingradspawn();
    if (isdefined(actor))
    {
        forward = anglestoforward(player.angles);
        target_pos = player.origin + (forward[0] * 180, forward[1] * 180, 0);
        actor forceteleport(target_pos, player.angles + (0, 180, 0));
        iprintln("^2Spawned AI soldier (" + team + ")^7");
    }
    else
    {
        iprintln("^1Failed to spawn soldier (spawner exhausted)^7");
    }
}
