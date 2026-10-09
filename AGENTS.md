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
- **There is no error handling.** GSC has no `pcall`. A call on an undefined
  value is not catchable — it takes the script system down. `isdefined()` is the
  only tool, so guard rather than hope.
- `setdvar()` **creates** the name. Any dvar a script publishes must be
  `setdvar()`'d at thread start, before anything can read it, because reading an
  unregistered name crashes the game (§3). `player_state.gsc` does this for all
  eight `overlord_ps_*` names.
- Poll and publish as slowly as the task tolerates. This is VR; the frame budget
  is halved. 20Hz for a command channel that must feel instant
  (`actor_spawner`), 4Hz for state nobody reads per frame (`player_state`).
- A new `.gsc` file must be added to `GSC_SCRIPTS` in `overlord.sh`, or
  `uninstall` will leave it behind and `status` will not report it.

### GSC checklist

1. Runtime work in `init()`, precache in `main()`.
2. Locals declared before any `if` that a later block reads.
3. `endon` registered before the first `wait`; every loop has a `wait`.
4. `isdefined()` after every `wait`, on everything you did not just set.
5. Every published dvar `setdvar()`'d before first read.
6. Shared `level.*` state prefixed `overlord_` and restored if borrowed.
7. `gsc-tool --mode comp` passes — not `--mode parse`.
8. Listed in `GSC_SCRIPTS`.

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
single-slot `Toast` helper in `_common/__init__.lua` for that. h2-mod's
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

### Never read a dvar that might not exist

**Reading an unregistered dvar name crashes the game.** `Engine.GetDvarString`
on a name that was never registered faults inside the native accessor —
`0xC0000005`, an access violation in C++. Confirmed the hard way on 2026-10-09:
probing invented names (`vr_playerOrigin`, `vr_hmdPose`, `vr_status` …) to find
out which existed killed the process twice in 13 seconds.

Two things that look like protection and are not:

- **`pcall` does not catch it.** `pcall` catches *Lua* errors. The faulting
  frame is native, below Lua, so the process is gone before Lua regains
  control. A `pcall`-wrapped probe is exactly as fatal as a bare one.
- **`tostring()` does not help.** It guards the *result*; the fault happens
  during the *call*. Nothing ever reaches Lua to be stringified.

So there is no safe way to ask "does this dvar exist?" from Lua. The rule is to
never need to ask: **register by writing before anything reads.** Writing an
unknown name is safe — it creates it. `ui_scripts/_common` does this for every
`overlord_ps_*` name at UI load time, and `scripts/player_state.gsc` does it
again with `setdvar()` before its first read.

If you need to know whether a running game has a given name registered, decide
it **host-side** — `overlord.sh status --player` compares the process start time
against the deployed module's mtime — rather than probing in-game.

A separate, milder hazard once a dvar *is* registered: a read can still return
`nil`, and `nil .. "text"` is a Lua error that surfaces out of the LUI
dispatcher as an access violation too. Prefer `string.format("%s", v)` over
`..` for anything nilable — `%s` calls `tostring`, concatenation does not.

### Registration appends; it does not replace

`LUI.addmenubutton` and `LUI.onmenuopen` both **append** a callback. Hot-reloading
a module with `dofile` therefore adds a duplicate menu entry every time. Every
module here guards re-entry with a `_G.<Name>Loaded` flag and returns early.
Menu *builders* registered by name (`LUI.MenuBuilder.registerType`,
`m_types_build[name]`) are safe to re-register.

`LUI` is in `globals`, not `read_globals`, in `.luacheckrc` — registering a menu
assigns into `LUI.MenuBuilder.m_types_build`.

### Module layout and how to share code

Overlord's loader ([`ui_script_modules.hpp`](src/client/component/ui_script_modules.hpp))
only auto-executes `h2-mod/ui_scripts/<dir>/__init__.lua`, and only for a
directory that contains one. A directory without `__init__.lua` is invisible to
the loader.

**`require` resolves against the requiring module's own folder**, from the
*root* script, not the file currently running
([`ui_scripting.cpp:977`](src/client/component/ui_scripting.cpp:977)):

```cpp
const auto folder = globals.in_require_script.substr(0, ...find_last_of("/\\"));
const std::string target_script = folder + "/" + name_ + ".lua";
```

So:

- **Splitting inside a module folder works.** `require("foo")` →
  `<module dir>/foo.lua`; subdirectories work too (`require("util/math")`).
  h2-mod's own `achievements/__init__.lua` is just `require("toast")` +
  `require("menu")`. Do not repeat the old claim that sibling `require` is
  impossible; it is false.
- **Paths do not nest.** A file in `common/` doing `require("bar")` looks in
  `<module dir>/bar.lua`, because resolution is always from the root script.
- **A module cannot `require` across into another module's directory.** There is
  no `..` sanitization on this path, unlike the GSC loader
  ([`script_loading.cpp:452`](src/client/component/gsc/script_loading.cpp:452)),
  so `require("../common/x")` might construct a valid path — but HKS rewrites
  the module name before the hook sees it (the shipped
  `require("LUI.common_menus.MarketingPopup")` arrives as `ui/LUI/...`), so
  whether `../` survives is **unverified**. Do not build on it.

**Cross-module sharing therefore goes through a global namespace.**
`ui_scripts/_common/__init__.lua` publishes `_G.OverlordCommon`
(`Claim`, `Exec`, `ExecNotify`, `Toast`, `SetDvarString`, `SetDvarBool`,
`GetDvarBool`, `GetDvarString`, `CreateDivider`, `AddButton`,
`AddChoiceButton`).

The leading underscore is load order, not decoration: `discover()` sorts the
directories, `_` is 0x5F and lowercase starts at 0x61, so `_common` runs before
`agent_ipc`, `cheats` and `overlord_extras`. That guarantee is what lets
consumers bind the table at load time:

```lua
local common = _G.OverlordCommon
if not common then
    print("[Overlord X] ui_scripts/_common did not load; not registered")
    return
end
if not common.Claim("X") then return end
local Toast = common.Toast
```

**Never call `menu:AddButton` directly.** Its real signature is positional and
mostly `nil` — `(label, callback, nil, true, nil, { desc_text = ... })` — and
only two of those six arguments ever vary here. Every call site goes through
`common.AddButton`, conventionally bound as `local Button = common.AddButton`:

```lua
Button(menu, "^3Assault Rifles^7", "M4A1, AK-47, SCAR-H, ...", function()
    LUI.FlowManager.RequestAddMenu(nil, "cheats_ar_menu")
end)
```

Note the description comes **before** the callback, which is the opposite of the
underlying call. `_common/__init__.lua` holds the one remaining raw
`menu:AddButton` — the helper's own body. A `grep -rn ':AddButton(' h2-mod/`
turning up a second hit means a call site was added by hand.

**Fail loudly, never degrade silently** — a half-registered menu is worse than
one that says why it is absent. If you add a module that must load before
`_common`, the underscore trick stops being enough and the binding has to become
lazy (`local c = _G.OverlordCommon` inside each call).

Load order still matters for *state*: **do not read another module's dvars or
globals at load time.** `cheats` reads `overlord_cheats_enabled`, which
`overlord_extras` registers and sorts after it — that works only because the
read happens inside a callback.

### Toast / UI element patterns

Modelled on `achievements/toast.lua`, which is known to work:
`LUI.UIElement.new` / `UIText.new` / `UIImage.new` with anchor fields,
`element:setText`, `registerAnimationState(name, {...})`,
`animateToState(name, ms)`, `LUI.UITimer.new(ms, "event_name")` with
`LUI.UITimer.Reset`/`Stop`, `registerEventHandler`, `setPriority`, and attach to
`Engine.GetLuiRoot()` or `LUI.roots.UIRoot0`.

Wrap UI work in `pcall`. A cosmetic failure must never break the button that
raised it.

### Every module announces itself

The **last** line of a module is a `print` banner. Put it last so that seeing it
in the console proves every registration above it ran — a banner at the top only
proves the file was opened. Together with the loud early `return` on a missing
`_common`, this makes the console log self-diagnosing: for each module you see
either the banner, or the reason it bailed, never silence.

```lua
print("[Overlord Cheats] Cheats & Sandbox menu registered")
```

`cheats` had no banner until 2026-10-09, and a successful load was
indistinguishable from an early return.

### Lua / LUI checklist

1. `local common = _G.OverlordCommon`, loud `return` if absent, then
   `common.Claim(name)`.
2. Dvars registered **by writing**; never probed, not even via
   `GetDvarType` (§3 "Never read a dvar that might not exist").
3. Every `Engine.*` call feature-tested with `type(...) == "function"`.
4. `game:method()` — colon, never `game.method()`.
5. Buttons via `common.AddButton`; no raw `menu:AddButton` outside `_common`.
6. Another module's dvars and globals read **inside callbacks only**, never at
   load time.
7. UI work wrapped in `pcall`.
8. `string.format("%s", v)` over `..` for anything nilable.
9. Module `print` banner on the last line.
10. New module directory added to `UI_SCRIPT_MODULES` in `overlord.sh`.
11. `luacheck` and `luac5.1` clean via the gate.

Code sent over the IPC bridge is **one line** — the bridge is line-oriented and
rejects embedded newlines rather than silently truncating.

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
