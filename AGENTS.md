# AGENTS.md — overlord-extras

Conventions and caveats for this repository. Everything here was verified
against the Overlord source tree, h2-mod's own shipped scripts, or a tool that
reproduces the engine's behaviour. Where something is unverified, it says so.

**Read this before editing Lua or GSC here.** Most of it is counter-intuitive,
and several entries exist because the stated-obvious version was wrong and
crashed the game.

> Reference paths below are relative to the Overlord source tree at
> `/run/media/system/Data/Projects/Overlord`, and to the game install at
> `.../Call of Duty Modern Warfare 2 Campaign Remastered`.

---

## 1. Run the gate

```bash
tools/check.sh
```

`bash -n`, shellcheck, shfmt, a Lua 5.1 parse check, luacheck, ruff, and a real
GSC compile. **A missing tool reports `SKIP` and is counted** — the gate still
exits 0, so read the skip count, not just the verdict. The tools live in the
`build-box` distrobox container and are wrapped onto the host by
`/run/media/system/Data/Scripts/setup-build-box.sh`.

There is no test suite and there cannot be one: the Lua runs in the game's
HavokScript VM and the GSC runs in the engine. The gate is all the static
verification that exists, so **never report Lua or GSC behaviour as verified
without having loaded the game.**

---

## 2. GSC

### `gsc-tool` is a real compiler — use it

```bash
gsc-tool --mode comp --game h2 --system pc --dry h2-mod/scripts/actor_spawner.gsc
```

MW2CR is the **h2** title on **pc**. This reproduces the engine's own compile
errors and exits non-zero on failure. `--mode parse` is syntax-only and misses
semantic errors, so always use `comp`.

### `main()` and `init()` are different load phases

From `src/client/component/gsc/script_loading.cpp`:

| Function | Called from | Phase |
| :--- | :--- | :--- |
| `main()` | `G_LoadStructs` | Load/precache. `level.player` does **not** exist yet. |
| `init()` | `Scr_LoadLevel` | After the level is up. |

Precaching goes in `main()`; a runtime watcher or anything touching the player
goes in `init()`. Both are picked up automatically if present.

### Load path

Scripts are loaded from `<search path>/scripts/*.gsc` and
`<search path>/scripts/<mapname>/*.gsc`. `h2-mod` is a registered search path
(`filesystem.cpp:36`), so `h2-mod/scripts/foo.gsc` loads as `scripts/foo`.

### A local declared inside a block is not visible after it

This does not compile — it is the error the game printed for this repo:

```gsc
// [ERROR]:compiler:scripts/actor_spawner:97:25:
//         local variable 'previous_count' not found
if (had_count) { previous_count = spawner.count; }
spawner.count = 1;
if (had_count) { spawner.count = previous_count; }   // not in scope
```

Declare it unconditionally at function scope instead. Assigning `undefined` to
an entity field **unsets** it, which is usually the correct "restore nothing".

### No file-scope constants

`MY_CONST = 0.2;` outside a function is not valid in this dialect. Use a local
at the point of use, or a `level.` field set during init.

### Verify every builtin against the h2 tables

`deps/gsc-tool/src/gsc/engine/h2_meth.cpp` and its siblings are the
authoritative list. Confirmed in use here: `stalingradspawn`, `forceteleport`,
`getspawnerteamarray`, `getspawnerarray`, `anglestoforward`, `iprintln`,
`randomint`, `precachemodel`, `spawnstruct`. A builtin from IW5 or T6 is not
necessarily present.

### Other rules

- `isdefined()` on every `level.*` / `self.*` / entity handle you did not set in
  the same function, and **again after every `wait`** — the entity may have died.
- Every long-lived thread needs `level endon("game_ended")` plus the relevant
  entity `endon`, registered **before the first `wait`**.
- Never loop without a `wait` inside; it hangs the server frame.
- Prefix anything you add to shared scope: `level.overlord_*`. `level` is one
  flat namespace shared with the stock mission scripts.
- Restore shared level state you borrow. Setting `spawner.count = 999` and
  walking away makes that spawner infinite for the rest of the mission.
- A dvar used as a command channel must be cleared **before** acting, so a
  failure cannot re-fire it next tick, and cleared at thread start so a stale
  value cannot carry across levels.
- Allman braces, 4 spaces, matching the stock scripts.

---

## 3. Lua / LUI

The game runs **HavokScript**, a Lua 5.1 fork. No `goto`, no integer division,
no bitwise operators, no `table.unpack`; `loadstring` and `unpack` do exist.
Lint with `luacheck --std lua51`; the globals are declared in `.luacheckrc`.

### `Engine.*` is a dot call; `game.*` is a method call

This is the single most dangerous asymmetry here. In
`src/client/component/ui_scripting.cpp`, every function on the `game` table is
bound as `[](const game&, ...)` — including the zero-argument ones — so they are
**methods**:

```lua
local weapons = game:assetlist("weapon")          -- correct
local name    = game:getweapondisplayname(id)     -- correct
local weapons = game.assetlist("weapon")          -- WRONG: passes the string
                                                  -- where the table goes and
                                                  -- raises "table expected,
                                                  -- got string" out of LUI
```

`Engine.*` takes no self and stays a dot call. h2-mod's own
`branding/victoryscreen.lua` calls `game:openlink(...)`, confirming the colon.

`game:assetlist` **throws** on an unknown asset type, so wrap it in `pcall`.

### The real `Engine` surface

Read off every shipped module; there is nothing else to rely on:

```
Exec  ExecNow  GetDvar{Bool,Int,Float,String,Type}  SetDvar{Bool,Float,String}
Localize  ToUpperCase  PlaySound  GetLuiRoot  InFrontend  PopupClosed
GetBuildNumber  GetCurrentLanguage  GetSupportedLanguages  GetProfileData
GetMaterialAspectRatio  IsPC  IsMultiplayer  IsRightToLeftLanguage
ShouldShowSubtitlesOption  StreamingInstallMap  TableGetRowCount
TableLookupByRow
```

**There is no notification function.** `CG_GameMessage` is C++-only
(`src/client/game/symbols.hpp:25`) and never bound to Lua. Native cheat commands
print their own messages from C++; anything routed through `give`,
`spawn_xmodel` or a dvar is silent unless you show it yourself. This repo has a
single-slot `Toast` helper in `cheats/__init__.lua` for that. h2-mod's
`achievements/toast.lua` also defines a global `addnotification`, but it is a
5s/6s **queue** — unusable for rapid button presses.

Other host globals: `CoD.TextSettings.*`, `CoD.SFX.*`, `Colors.*`,
`RegisterMaterial`, `GenericButtonSettings`, `GenericMenuDims`, `H1MenuDims`,
and an `io` table that is **not** standard Lua `io` — it provides
`readfile`/`writefile`/`fileexists`/`removefile`.

### Feature-test before calling

A missing host function is a `nil` call that surfaces as an **access violation
out of the LUI dispatcher**, not a Lua error — this repo has the minidumps to
prove it. Use `type(x) == "function"`, not a truthiness check:

```lua
if type(Engine.SetDvarString) == "function" then ... end
```

### An unregistered dvar reads back `nil`

`nil .. "text"` is an error that propagates out of the dispatcher as an access
violation. Register the dvar first, and prefer `string.format("%s", v)` over
`..` for anything that could be nil — `%s` calls `tostring`, concatenation does
not.

### Registration appends; it does not replace

`LUI.addmenubutton` and `LUI.onmenuopen` both **append** a callback. Hot-reloading
a module with `dofile` therefore adds a duplicate menu entry every time. Every
module here guards re-entry with a `_G.<Name>Loaded` flag and returns early.
Menu *builders* registered by name (`LUI.MenuBuilder.registerType`,
`m_types_build[name]`) are safe to re-register.

`LUI` is in `globals`, not `read_globals`, in `.luacheckrc` — registering a menu
assigns into `LUI.MenuBuilder.m_types_build`.

### Module layout

Overlord's loader reads `h2-mod/ui_scripts/<dir>/__init__.lua`. Sibling
`require("name")` **does** work — h2-mod's `achievements/__init__.lua` does
`require("toast")` — but modules here are kept in one file anyway: one load, one
guard, one place to hot-reload. Do not repeat the old claim that sibling
`require` is impossible; it is false.

Load order is directory-alphabetical (`agent_ipc`, `cheats`, `overlord_extras`),
so **do not read another module's state at load time**. `cheats` reads
`overlord_cheats_enabled`, which `overlord_extras` registers — that works only
because the reads happen inside callbacks.

### Toast / UI element patterns

Modelled on `achievements/toast.lua`, which is known to work:
`LUI.UIElement.new` / `UIText.new` / `UIImage.new` with anchor fields,
`element:setText`, `registerAnimationState(name, {...})`,
`animateToState(name, ms)`, `LUI.UITimer.new(ms, "event_name")` with
`LUI.UITimer.Reset`/`Stop`, `registerEventHandler`, `setPriority`, and attach to
`Engine.GetLuiRoot()` or `LUI.roots.UIRoot0`.

Wrap UI work in `pcall`. A cosmetic failure must never break the button that
raised it.

---

## 4. Where `give` actually puts a weapon

`give` is **not** replaced in VR, but it does not put anything in your hands:
`command.cpp` skips `G_SelectWeapon` whenever VR carry is active, so the weapon
enters the native inventory and the carry system assigns it a body slot.

`free_slot()` in `vr/gameplay/weapon_carry.hpp` tries **right waist → left waist
→ back → hidden overflow queue**, and `accepts()` gates the waist slots behind
`policy.waist`, which `vr/gameplay/weapon_carry_profiles.hpp` grants to an
**authored list, not the native weapon category** ("a native SMG category is not
a waist permit").

| Group | Destination |
| :--- | :--- |
| `beretta` `usp` `coltanaconda` `deserteagle` `colt45` `glock` | right hip → left hip → back |
| `tmp` `pp2000` `uzi` `ranger` `beretta393` | same |
| `ending_knife` `ending_knife_bloody` `h2_cheatcommandoknife` | same |
| `usp_laserdesignator` | its own abdominal slot; cannot be dropped |
| `at4` `stinger` `javelin` | back; right hand fires, left only supports |
| Every other firearm, including `m93r` `mp5k` `ump45` `p90` `kriss` | back, then **hidden** overflow |
| Grenades, mission props, cliffhanger picks, `h2_cheatpickaxe` | not in VR carry at all (`eligible()` rejects them) |

Two consequences worth remembering:

- **A second back-slot weapon is invisible.** Back-stowed weapons skip model
  submission; it is reachable only by reaching behind you.
- **The ceiling is 15** (`capacity = 15`, the engine ownership-array bound).
  `reconcile_instances` refuses past it and weapons stop being placed. No Lua
  call reports the current count, so the menu cannot show one — it offers
  `take all` next to the buttons that cause the problem instead.

`spawn_xmodel` is unrelated: it renders a **static** model client-side a short
distance ahead. No entity, no collision, no AI. `clear_spawned_xmodels` removes
them.

---

## 5. Shell

`overlord.sh` sets `IFS=$'\n\t'`, which makes `"$*"` and `"${arr[*]}"` join on a
**newline**. The IPC bridge is line-oriented and treats each line as a separate
command, so `cmd give m4` once arrived in game as `give` and `m4`. Use the
`join_words` helper for any join, and reject embedded newlines in a payload
rather than mangling it.

Use `pgrep -ax` (command **name** only), never bare `pgrep -f` — an agent's
command line contains the pattern and matches itself. The game's hosting process
is `h2_sp64_bnet_ship.exe`, not `MW2CR.exe`.

`tools/steam_shortcut.py` owns all Steam config writes. It backs up, is a no-op
when nothing changes, brace-matches instead of regexing, and refuses to write
unless its output parses back identically. Do not hand-roll VDF editing: the
previous regex would have deleted two unrelated `config.vdf` blocks, because
this appid also appears under `ShaderCacheSize` and `SizeOnDisk`. Steam stores
appid as a **signed int32**, so `4096896093` on disk parses as `-198071203`;
match both.

Shut Steam down with `steamcli client shutdown` before touching its config — a
running client rewrites both files on exit.

---

## 6. Deploying

```bash
./overlord.sh deploy        # sync h2-mod/ into the game folder
./overlord.sh status        # version, process, which modules are deployed
./overlord.sh --lua "dofile('h2-mod/ui_scripts/cheats/__init__.lua')"
```

Overlord's own packaging ships only `h2-mod/ui_scripts/vr_gameplay`, so
everything here is removed by a clean reinstall or a version switch.
`./overlord.sh switch` re-deploys automatically; a manual extract does not.

A deploy overwrites the game folder from the repo, so **commit before
deploying** — work edited only in the game folder has been lost that way.

---

## 7. Commits

Conventional Commits (`feat(cheats):`, `fix(launcher):`, `docs:`). End with:

```
Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
```

GitHub Actions never run under this account. `.github/workflows/check.yml`
therefore keeps `workflow_dispatch` live and every automatic trigger commented
out with a note saying why. Never add a status check that waits on a workflow.
