# tools/

## `steam_shortcut.py`

Rewrites Steam's `shortcuts.vdf` and `config.vdf` so the non-Steam-game entry
runs `overlord.sh` natively instead of through Proton. Invoked by
`overlord.sh point-steam`; it is not meant to be run by hand.

```bash
python3 tools/steam_shortcut.py point \
  --shortcuts ~/.local/share/Steam/userdata/<id>/config/shortcuts.vdf \
  --appid 4096896093 --appname "Call of Duty Modern Warfare 2 (2019) VR" \
  --exe /path/to/overlord.sh --start-dir /path/to/game/ --launch-options launch

python3 tools/steam_shortcut.py clear-compat \
  --config ~/.local/share/Steam/config/config.vdf --appid 4096896093
```

Both actions back the file up first, are no-ops when nothing would change, and
refuse to write when the content they produced does not parse back to what they
intended. Shut Steam down (`steamcli client shutdown`) before running either —
a running client rewrites both files on exit.

## Removed

`overlord-cmd.sh` and `overlord-switcher.sh` were standalone copies of the IPC
client and the release switcher, both of which `overlord.sh` now implements. They
had drifted out of sync, and `overlord-switcher.sh` resolved its game directory
to its own folder, so running it from the repository extracted an Overlord
release into `tools/`. Use `overlord.sh` instead:

| Removed | Replacement |
| :--- | :--- |
| `overlord-cmd.sh god` | `overlord.sh cmd god` |
| `overlord-cmd.sh --lua '…'` | `overlord.sh --lua '…'` |
| `overlord-cmd.sh -i` | `overlord.sh -i` |
| `overlord-switcher.sh --list` | `overlord.sh --versions` |
| `overlord-switcher.sh --version <tag>` | `overlord.sh --version <tag>` |
| `overlord-switcher.sh` (interactive) | `overlord.sh switch` |
