# Workspaces with Window Icons

An [Omarchy](https://omarchy.org/) shell bar widget — a fork of the built-in
`omarchy.workspaces` widget that also shows the icon of each running window
next to its workspace number. Click an icon to switch to that window's
workspace.

![Preview](preview.png)

## Install

```bash
omarchy plugin add https://github.com/deda/omarchy-workspaces-icons.git --enable
omarchy plugin disable omarchy.workspaces
```

## Manual install

```bash
git clone https://github.com/deda/omarchy-workspaces-icons.git ~/.config/omarchy/plugins/deda.workspaces-icons
omarchy plugin enable deda.workspaces-icons
omarchy plugin disable omarchy.workspaces
```

## Configuration

The workspace number uses the bar's own font size. To make it smaller or
larger than the rest of the bar, set an offset (in pixels, `-6` to `6`):

```bash
omarchy bar set deda.workspaces-icons fontSizeOffset -2
```

Or edit the widget's entry in `~/.config/omarchy/shell.json` directly, which
hot-reloads on save:

```json
{ "id": "deda.workspaces-icons", "fontSizeOffset": -2 }
```

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `fontSizeOffset` | integer, `-6`..`6` | `0` | Pixels added to the bar's font size for the workspace number. `0` matches the rest of the bar. |

## Update

```bash
omarchy plugin update deda.workspaces-icons
```

## Remove

```bash
omarchy plugin remove deda.workspaces-icons
```

## License

[MIT](LICENSE)
