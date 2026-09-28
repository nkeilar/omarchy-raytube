# Raytube

A Cast menu for the [Omarchy](https://omarchy.org) bar. Click the cast icon, pick
a TV, and your laptop screen (or a separate "TV desktop") appears on it with
sound. It works with an Apple TV over AirPlay and with a Chromecast.

The plugin is only the menu. The casting itself is done by the
[raytube](https://github.com/nkeilar/raytube) command-line tools, which the menu
calls (`raytube-cast` and `raytube-tv`).

![Raytube cast menu](preview.png)

_(preview.png is a placeholder until a screenshot is added.)_

## What the menu does

**CAST**

- **Screen | TV desktop**: choose what gets cast. *Screen* mirrors the laptop
  display. *TV desktop* casts a hidden second monitor instead, so the laptop
  screen stays private and you send only the windows you want to the TV.
  Switching during a cast restarts it on the same TV in the new mode.
- **One row per TV** found on the network. Click a row (or move to it with
  `j`/`k` and press Enter) to start or stop casting to it. Chromecasts are
  marked "· Cast", and AirPlay TVs that still need pairing are marked "· pair".
- **Sound sync − / +** (AirPlay only): delays the sound in 50 ms steps to match
  the picture. The change applies live.
- **720p / 1080p / 1440p** (AirPlay only): the picture size sent to the TV.
  720p and 1080p stay in sync; 1440p is sharper, but the TV may hold the
  picture back.
- **Re-sync TV** (AirPlay only): restarts the session, which always starts in
  sync.

**TV DESKTOP** (shown while the TV desktop is up)

- **Full / Split / PiP**: the layout of the current scene.
- **↻**: rotation on or off, with a countdown to the next scene.
- **Board / Browser / YouTube ⇄ TV app**: show the family board, open the TV
  browser, or hand the playing video to the Chromecast's own YouTube app and
  back.
- **Scene list**: click a scene to show it, and click its ↻ to add it to or
  remove it from the rotation.

While a cast is running, the bar icon changes to the "connected" cast glyph.

If the raytube tools aren't on `PATH`, the menu says so and links to the tools
repository instead of showing controls.

## Requirements

- The [raytube](https://github.com/nkeilar/raytube) tools installed, with
  `raytube-cast` and `raytube-tv` on `PATH` (for example in `~/.local/bin`).
- Omarchy 4 with the Lua Hyprland config.

## Install

```bash
omarchy plugin add https://github.com/nkeilar/omarchy-raytube --enable
```

Or by hand: copy this directory to `~/.config/omarchy/plugins/nathank.raytube/`,
then run `omarchy plugin enable nathank.raytube`.

The widget lands on the right of the bar. Move it with `omarchy bar move`.

To open the menu from a keybinding or a script:

```bash
omarchy-shell nathank.raytube toggle
```

## Remove

```bash
omarchy plugin remove nathank.raytube
```

That disables the plugin and deletes its directory. The plugin writes nothing
else except its own entry in `~/.config/omarchy/shell.json`, which is removed
when the plugin is disabled. The raytube tools' own settings are left alone.

## License

MIT. See [LICENSE](LICENSE).
