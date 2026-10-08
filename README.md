# Overlord Extras (MW2CR VR)

Comprehensive companion suite, modular VR comfort settings, IPC developer CLI, release version switcher, and unified launcher for **[Overlord VR](https://github.com/Aeka0/Overlord)** (*Call of Duty: Modern Warfare 2 Campaign Remastered*).

---

## 🚀 Features

- **Unified Launcher & Process Lifecycle (`overlord.sh`)**
  - Auto-deploys extras and scripts to the game directory on launch.
  - Configures OpenXR runtime, WiVRn compositor socket pass-through, and GE-Proton / `umu-run` environment.
  - Graceful stop (`stop`) via IPC `quit` and SIGTERM, or force kill (`kill`).
- **Steam Shortcut Integration (`point-steam`)**
  - Seamlessly links the Steam custom game shortcut (`Call of Duty Modern Warfare 2 (2019) VR` / `steam://rungameid/17596034734578728960`) to `overlord.sh`.
  - Automatically manages Steam client shutdown and restart via `steamcli`.
- **Release Version Switcher**
  - Discovers official releases from [`Aeka0/Overlord`](https://github.com/Aeka0/Overlord).
  - Interactive release picker (`./overlord.sh switch`), list releases (`./overlord.sh --versions`), or headless install (`./overlord.sh --version v0.4.0-beta`).
  - Caches archives under `~/.cache/overlord-switcher/` and unwraps top-level archive folders during deployment.
- **In-Game VR Extras Menu (`overlord_extras`)**
  - Integrated into Options (`pc_controls`), Campaign Menu, and live in-game Pause Menu (`sp_pause_menu`).
  - **Camera & Comfort**: Native weapon/hand camera bob toggle, motion blur, lens flare, head stabilization.
  - **Gameplay & Immersion**: Physical reloads, closed bolt chambering (+1 in chamber), native pip ammo HUD, 2D HUD hiding.
  - **Rendering & Display**: Post-AA selection (`Off`, `FXAA`, `SMAA`), FPS display, desktop stream preview mode.
- **Developer & Agent IPC Bridge (`agent_ipc`)**
  - Bidirectional communication between host shell / AI agent and the in-game Lua engine.
  - Run console commands (`god`, `noclip`, `give cheytac`).
  - Live Lua evaluation (`--lua 'return Engine.GetDvarString("mapname")'`).
  - Dvar inspection and modification (`--dvar cg_fov 95`).
  - Interactive REPL shell (`./overlord.sh -i`).
- **Expanded Sandbox Armory & AI Spawner**
  - Dynamic active mission weapon detection and spawning.
  - Live AI combat actor spawner (Axis / Allies / Random).

---

## 🛠️ Usage

### Quick Start
```bash
# Launch game in VR (auto-deploys extras)
./overlord.sh

# View current game and Overlord status
./overlord.sh status

# Link Steam custom game shortcut to this launcher
./overlord.sh point-steam
```

### Version Switcher
```bash
# Interactive version picker
./overlord.sh switch

# List available upstream releases
./overlord.sh --versions

# Switch to a specific release tag
./overlord.sh --version v0.4.0-beta
```

### Agent & Host IPC CLI
```bash
# Send console command to running game
./overlord.sh god
./overlord.sh give m4a1

# Evaluate Lua expression
./overlord.sh --lua 'return Engine.GetDvarString("mapname")'

# Read or set dvars
./overlord.sh --dvar cg_fov 95

# Launch interactive REPL
./overlord.sh -i
```

### Process Management
```bash
# Gracefully stop the game
./overlord.sh stop

# Force-kill game processes and clear IPC files
./overlord.sh kill

# Remove deployed extras from game directory
./overlord.sh uninstall
```

---

## 📁 Repository Structure

```
overlord-extras/
├── overlord.sh                 # Master launcher, version switcher & IPC CLI
├── h2-mod/
│   ├── scripts/
│   │   └── actor_spawner.gsc   # Live AI combat actor spawner (GSC)
│   └── ui_scripts/
│       ├── overlord_extras/    # In-game VR settings menus (Comfort, Gameplay, Rendering)
│       │   ├── __init__.lua
│       │   ├── menu.lua
│       │   ├── comfort.lua
│       │   ├── gameplay.lua
│       │   ├── rendering.lua
│       │   └── cheats_option.lua
│       ├── agent_ipc/          # Bidirectional host-to-game IPC bridge
│       │   └── __init__.lua
│       └── cheats/             # Enhanced Sandbox, Armory & Spawner pause menu
│           └── __init__.lua
└── tools/
    ├── overlord-cmd.sh         # Standalone IPC CLI
    └── overlord-switcher.sh    # Standalone release switcher
```

---

## 📄 License

MIT License. See [LICENSE](LICENSE) for details.
