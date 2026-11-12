# Workspaces with Window Icons

An [Omarchy](https://omarchy.org/) shell bar widget — a fork of the built-in
`omarchy.workspaces` widget that also shows the icon of each running window
next to its workspace number. Click an icon to switch to that window's
workspace.


## Multiple monitors

Requires [Omarchy 4.5](https://github.com/omacom/omarchy/pull/15655) or newer. Like the built-in widget, it follows Omarchy's
per-monitor workspaces: every monitor has its own workspaces 1-10 (Hyprland
numbers them in blocks of ten - 1-10, 11-20, ...), and each monitor's bar
shows only its own, labeled `1:`-`0:`, with the workspace that monitor is
showing highlighted. Workspaces left over from an unplugged monitor are
listed after a small gap.

![Preview](preview.png)

## Install

```bash
omarchy plugin add https://github.com/deda/omarchy-workspaces-icons.git --enable
omarchy plugin disable omarchy.workspaces
omarchy restart shell
```

## Manual install

```bash
git clone https://github.com/deda/omarchy-workspaces-icons.git ~/.config/omarchy/plugins/deda.workspaces-icons
omarchy plugin enable deda.workspaces-icons
omarchy plugin disable omarchy.workspaces
omarchy restart shell
```

The shell keeps an already-loaded widget's compiled QML, so after installing
or updating, restart it once to pick up the new code.

## Configuration

The workspace number uses the bar's own font size. To make it smaller or
larger than the rest of the bar, set an offset (in pixels, `-6` to `6`):

```bash
omarchy bar set deda.workspaces-icons fontSizeOffset -2
```

The window icons follow the bar's font size too (via the shell's spacing
scale). Nudge them the same way, in pixels from `-8` to `12`; they are capped
at the bar's height:

```bash
omarchy bar set deda.workspaces-icons iconSizeOffset 4
```

Or edit the widget's entry in `~/.config/omarchy/shell.json` directly, which
hot-reloads on save:

```json
{ "id": "deda.workspaces-icons", "fontSizeOffset": -2, "iconSizeOffset": 4 }
```

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `fontSizeOffset` | integer, `-6`..`6` | `0` | Pixels added to the bar's font size for the workspace number. `0` matches the rest of the bar. |
| `iconSizeOffset` | integer, `-8`..`12` | `0` | Pixels added to the window icons' default size (which scales with the bar's font size). `0` keeps the default; never exceeds the bar's height. |

## Update

```bash
omarchy plugin update deda.workspaces-icons
omarchy restart shell
```

## Remove

```bash
omarchy plugin remove deda.workspaces-icons
```

## License

[MIT](LICENSE). This plugin is a fork of Omarchy's built-in
`omarchy.workspaces` widget and keeps substantial portions of it, so
[LICENSE](LICENSE) carries both notices: this plugin's (Copyright (c) 2026
deda) and Omarchy's upstream MIT notice (Copyright (c) David Heinemeier
Hansson), reproduced in full.
