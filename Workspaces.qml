// Fork of Omarchy's built-in omarchy.workspaces bar widget
// (https://github.com/omacom/omarchy), Copyright (c) David Heinemeier
// Hansson, MIT License. Modifications Copyright (c) 2026 deda, MIT License.
// See LICENSE for both notices in full.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "omarchy.workspaces"

  // Omarchy 4.5+ per-monitor workspaces (mirrors the stock omarchy.workspaces
  // widget): every monitor has workspaces 1-10 of its own, which Hyprland
  // numbers in a block of ten per monitor - 1-10, 11-20, and so on (see
  // $OMARCHY_PATH/default/hypr/monitor-workspaces.lua). Each bar shows its own
  // monitor's block, labeled 1-10, and highlights the workspace that monitor
  // shows, whichever monitor has focus.
  readonly property int slots: 10

  readonly property var monitor: {
    var window = root.QsWindow.window
    var screen = window ? window.screen : null
    return screen ? Hyprland.monitorFor(screen) : Hyprland.focusedMonitor
  }
  readonly property string monitorName: root.monitor ? root.monitor.name : ""

  // Connector -> block, from the state file Hyprland keeps them in
  // (one "<block>\t<connector>\t<identity>" line per monitor ever seen).
  property var blocks: ({})

  function readBlocks(text) {
    var next = {}
    var lines = String(text || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var fields = lines[i].split("\t")
      if (fields.length >= 3 && fields[1] !== "") next[fields[1]] = parseInt(fields[0], 10)
    }
    root.blocks = next
  }

  FileView {
    path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readBlocks(text())
    onLoadFailed: root.readBlocks("")
  }

  function blockOf(id) {
    return Math.floor((id - 1) / root.slots)
  }

  function slotOf(id) {
    return (id - 1) % root.slots + 1
  }

  function activeWorkspaceId() {
    return root.monitor && root.monitor.activeWorkspace ? root.monitor.activeWorkspace.id : -1
  }

  // Until Hyprland has written the state file, the workspace a monitor shows
  // is in its own block.
  readonly property int block: {
    var block = root.blocks[root.monitorName]
    if (block !== undefined) return block
    var active = root.activeWorkspaceId()
    return active > 0 ? root.blockOf(active) : 0
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  // The first five of the monitor's own block, and any of the rest that
  // exist. After them come workspaces that are only visiting: those of an
  // unplugged monitor, which had no room to join this one's block.
  function workspaceIds() {
    var base = root.block * root.slots
    var ids = [base + 1, base + 2, base + 3, base + 4, base + 5]
    var guests = []
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id <= 0) continue
      if (root.blockOf(id) === root.block) {
        if (ids.indexOf(id) === -1) ids.push(id)
      } else if (values[i].monitor && values[i].monitor.name === root.monitorName) {
        guests.push(id)
      }
    }

    ids.sort(function(left, right) { return left - right })
    guests.sort(function(left, right) { return left - right })
    return ids.concat(guests)
  }

  function dispatch(expression) {
    if (root.bar) root.bar.run("hyprctl dispatch " + Util.shellQuote(expression))
  }

  // Own-block workspaces go through Omarchy's per-monitor helper (slot +
  // monitor), the same thing Super + <n> does; guests are addressed by id.
  function focusWorkspace(id) {
    if (root.blockOf(id) === root.block) {
      root.dispatch("o.workspaces.focus(" + root.slotOf(id) + ", \"" + root.monitorName + "\")")
    } else {
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = event ? String(event.name) : ""
      // Quickshell credits every workspace switch to the focused monitor, as
      // the event doesn't say which one switched, and misses the workspace a
      // monitor falls back to when its own is moved away. Moving workspaces
      // between monitors switches the others, so ask Hyprland for the truth.
      // Every bar shares what Hyprland answers, so only the focused monitor's
      // bar asks after a plain switch.
      var switched = name === "workspacev2" && root.monitor !== null && root.monitor.focused
      if (switched || name === "moveworkspacev2" || name === "changeworkspaceid") {
        Hyprland.refreshMonitors()
        Hyprland.refreshWorkspaces()
      }
    }
  }

  // Dot-separated class segments, lowercased (e.g. "md.Obsidian" -> ["md", "obsidian"]).
  function classSegments(value) {
    return String(value || "").toLowerCase().split(".").filter(function(s) { return s.length > 0 })
  }

  // True if `needle` appears as a contiguous, whole-segment run inside `haystack`.
  // Segment-based so "obs" doesn't match inside "md.obsidian.obsidian" the way a
  // raw substring check would (that's how OBS Studio's StartupWMClass, "obs",
  // used to get matched instead of Obsidian's).
  function segmentsContain(haystack, needle) {
    if (needle.length === 0 || needle.length > haystack.length) return false
    for (var start = 0; start <= haystack.length - needle.length; start++) {
      var match = true
      for (var j = 0; j < needle.length; j++) {
        if (haystack[start + j] !== needle[j]) { match = false; break }
      }
      if (match) return true
    }
    return false
  }

  // Omarchy webapps launch via `omarchy-launch-webapp <url>` (Chrome --app
  // mode), which has no StartupWMClass at all - Chrome instead generates a
  // class embedding the site's hostname (e.g. "chrome-discord.com__..." for
  // https://discord.com/...). Extract that hostname from the entry's Exec so
  // it can be matched against the live window class.
  function webappHostname(entry) {
    var exec = String(entry.execString || "")
    var execMatch = exec.match(/omarchy-launch-(?:or-focus-)?webapp\s+"?(https?:\/\/[^\s"]+)/)
    if (!execMatch) return ""
    var hostMatch = execMatch[1].match(/^https?:\/\/([^\/]+)/)
    if (!hostMatch) return ""
    return hostMatch[1].replace(/^www\./, "").toLowerCase()
  }

  // org.omarchy.agent is a fixed class every coding agent CLI shares (see
  // omarchy-agent), so there's no desktop entry to resolve an icon from.
  // Only Claude and Codex ship a dedicated mark in the agents bar panel's own
  // assets; any other/undetected agent falls back to Claude's, since it's
  // Omarchy's default.
  readonly property string agentIconsPath: "/usr/share/omarchy/shell/plugins/agents/assets/"
  readonly property var knownAgentBinaries: ["claude", "codex", "copilot", "crush", "grok", "omp", "pi"]

  function agentIconNameFor(binary) {
    return binary === "codex" ? "codex" : "claude"
  }

  // omarchy-launch-tui defaults an unlabeled command's class to
  // "org.omarchy.<binary>" (e.g. "org.omarchy.yazi" for `omarchy-launch-tui
  // yazi`) unless the caller passes its own --app-id, as omarchy-agent does.
  // That prefixed class never matches a real desktop entry or icon-theme
  // name, so strip it back to the bare binary name to look up instead.
  function tuiBinaryName(appId) {
    var match = /^org\.omarchy\.(.+)$/.exec(String(appId || ""))
    return match ? match[1] : ""
  }

  // A window picks its own app id, and the icon lookup doesn't treat it as a
  // plain name: QIcon::fromTheme reads an absolute name as a file path, the
  // theme loader joins it onto icon directories (so "../" escapes them), and
  // Quickshell's icon provider parses "?path=" / "?fallback=" out of it. Only
  // let a raw app id through as an icon name when it looks like one.
  function isThemeIconName(value) {
    return /^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/.test(String(value || ""))
  }

  // Descend up to 5 levels of children from the window's PID looking for a
  // known agent binary (the window's own PID is usually the terminal
  // emulator's, with the agent CLI running as its child/grandchild).
  function agentDetectScript(pid) {
    return "frontier=" + pid + "; for d in 1 2 3 4 5; do "
      + "frontier=$(pgrep -P \"$frontier\" | tr '\\n' ',' | sed 's/,$//'); "
      + "[ -z \"$frontier\" ] && break; "
      + "for p in $(echo \"$frontier\" | tr ',' ' '); do "
      + "c=$(ps -o comm= -p \"$p\" 2>/dev/null); "
      + "case \"$c\" in " + root.knownAgentBinaries.join("|") + ") echo \"$c\"; exit 0;; esac; "
      + "done; done"
  }

  // Match a running window back to the same desktop entry the app launcher
  // menu would show for it, so icons stay consistent with the launcher.
  function findDesktopEntry(appId) {
    if (!appId) return null

    var lower = appId.toLowerCase()
    var appSegments = classSegments(appId)
    var values = DesktopEntries.applications.values || []
    var i, entry, startupClass, hostname

    // 1. Exact StartupWMClass match.
    for (i = 0; i < values.length; i++) {
      startupClass = String(values[i].startupClass || "").toLowerCase()
      if (startupClass !== "" && startupClass === lower) return values[i]
    }

    // 2. StartupWMClass as a contiguous run of segments within the live app
    // id (e.g. Obsidian ships "md.Obsidian" but the live window reports
    // "md.obsidian.Obsidian").
    for (i = 0; i < values.length; i++) {
      startupClass = String(values[i].startupClass || "")
      if (startupClass === "") continue
      var startupSegments = classSegments(startupClass)
      if (segmentsContain(appSegments, startupSegments) || segmentsContain(startupSegments, appSegments))
        return values[i]
    }

    // 3. Omarchy webapp hostname match (Discord, WhatsApp, etc.).
    for (i = 0; i < values.length; i++) {
      hostname = webappHostname(values[i])
      if (hostname !== "" && lower.indexOf(hostname) !== -1) return values[i]
    }

    return DesktopEntries.byId(appId) || DesktopEntries.heuristicLookup(appId) || null
  }

  // Workspace numbers inherit the bar's font size. `fontSizeOffset` nudges
  // them relative to it - negative shrinks, positive grows - so the setting
  // keeps tracking the shell's `[font] base-size` instead of pinning a pixel
  // size that stops matching once that base size changes.
  readonly property int fontSizeOffset: {
    var offset = Math.round(Number(root.setting("fontSizeOffset", 0)))
    return isFinite(offset) ? Math.max(-6, Math.min(6, offset)) : 0
  }

  readonly property real numberFontSize: Math.max(1, Style.font.body + root.fontSizeOffset)

  // Window icons default to the shell's spacing scale (`Style.space(10)`,
  // which tracks `[font] base-size`). `iconSizeOffset` nudges them relative
  // to that, the same way `fontSizeOffset` does for the numbers, and the
  // result is capped at the bar's thickness so a large offset can't spill
  // out of the bar.
  readonly property int iconSizeOffset: {
    var offset = Math.round(Number(root.setting("iconSizeOffset", 0)))
    return isFinite(offset) ? Math.max(-8, Math.min(12, offset)) : 0
  }

  readonly property real iconSize: Math.max(4, Math.min(root.barSize, Style.space(10) + root.iconSizeOffset))

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(6)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        id: cell
        required property int modelData
        required property int index

        readonly property var workspace: root.workspaceById(modelData)
        readonly property var toplevels: workspace !== null ? workspace.toplevels.values : []
        readonly property bool occupied: toplevels.length > 0
        // The workspace this bar's monitor shows - not the globally focused
        // one - so every monitor's bar keeps its own highlight.
        readonly property bool shown: root.monitor !== null && root.monitor.activeWorkspace !== null
          && root.monitor.activeWorkspace.id === modelData
        readonly property int slot: root.slotOf(modelData)
        readonly property bool firstGuest: root.blockOf(modelData) !== root.block && index > 0
          && root.blockOf(root.workspaceIds()[index - 1]) === root.block
        readonly property real iconSize: root.iconSize

        // A gap sets visiting workspaces apart from the monitor's own.
        Layout.leftMargin: firstGuest && !root.vertical ? Style.space(6) : 0
        Layout.topMargin: firstGuest && root.vertical ? Style.space(6) : 0

        implicitWidth: row.implicitWidth
        implicitHeight: row.implicitHeight

        Rectangle {
          anchors.centerIn: parent
          width: row.implicitWidth - Style.space(4)
          height: Math.min(parent.height, cell.iconSize + Style.space(4))
          radius: Style.space(3)
          color: root.bar ? root.bar.barForeground : Color.foreground
          visible: cell.shown
        }

        RowLayout {
          id: row
          anchors.fill: parent
          spacing: 0

          WidgetButton {
            id: numberButton
            Layout.alignment: Qt.AlignVCenter
            bar: root.bar
            text: cell.slot === root.slots ? "0:" : String(cell.slot) + ":"
            foreground: cell.shown ? Color.bar.background : (root.bar ? root.bar.barForeground : Color.foreground)
            useActiveColor: false
            fontSize: root.numberFontSize
            opacity: cell.occupied || cell.shown ? 1 : 0.5
            horizontalMargin: 6
            verticalPadding: 6
            // Fixed slot so the numbers stay on a common grid, but it has
            // to grow past that grid when a larger font makes the label
            // outrun it - otherwise the number spills into the icons.
            fixedWidth: root.vertical ? root.barSize
              : Math.max(Style.space(20), numberButton.labelWidth + numberButton.scaledHorizontalMargin * 2)
            fixedHeight: root.barSize
            onPressed: function() { root.focusWorkspace(cell.modelData) }
          }

          Row {
            id: icons
            Layout.alignment: Qt.AlignVCenter
            spacing: Style.space(2)
            visible: !root.vertical && cell.toplevels.length > 0

            Repeater {
              model: cell.toplevels

              Image {
                id: icon
                required property var modelData

                readonly property string windowClass: (modelData.wayland && modelData.wayland.appId)
                  || (modelData.lastIpcObject && modelData.lastIpcObject.class) || ""
                readonly property int windowPid: (modelData.lastIpcObject && modelData.lastIpcObject.pid) || 0
                readonly property bool isAgentWindow: windowClass === "org.omarchy.agent"
                property string detectedAgentBinary: ""
                readonly property string windowTitle: modelData.title || ""
                // Bar.showTooltip() only actually shows the tooltip if the target
                // exposes a `tooltipHovered` property (see how WidgetButton does
                // it) - a plain Image has none, so without this the call above
                // silently no-ops every time.
                readonly property bool tooltipHovered: hoverArea.containsMouse

                // Unwrap omarchy-launch-tui's "org.omarchy.<binary>" convention
                // (org.omarchy.agent is handled separately, see isAgentWindow) so
                // lookups use the plain binary name a desktop entry or icon
                // theme would actually recognize.
                readonly property string lookupClass: (!isAgentWindow && windowClass.indexOf("org.omarchy.") === 0)
                  ? root.tuiBinaryName(windowClass)
                  : windowClass

                // Resolve through the app's desktop entry first, same as the Omarchy
                // app launcher menu does, since a window's app id often differs from
                // the icon name in its .desktop file (e.g. Slack, Obsidian).
                readonly property var desktopEntry: root.findDesktopEntry(lookupClass)
                // A desktop entry's Icon= is trusted as is. The raw app id is
                // not (see isThemeIconName): anything that doesn't look like an
                // icon name gets the fixed generic icon instead.
                readonly property string iconName: (desktopEntry && desktopEntry.icon) ? desktopEntry.icon
                  : root.isThemeIconName(lookupClass) ? lookupClass
                  : lookupClass !== "" ? "application-x-executable"
                  : ""
                readonly property string overridePath: isAgentWindow
                  ? root.agentIconsPath + root.agentIconNameFor(detectedAgentBinary) + ".svg"
                  : ""

                width: cell.iconSize
                height: cell.iconSize
                source: overridePath !== "" ? Util.fileUrl(overridePath)
                  : iconName !== "" ? Quickshell.iconPath(iconName, "application-x-executable") : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                visible: status === Image.Ready

                Process {
                  running: icon.isAgentWindow && icon.windowPid > 0
                  command: ["bash", "-c", root.agentDetectScript(icon.windowPid)]
                  stdout: SplitParser {
                    onRead: function(line) {
                      var trimmed = String(line || "").trim()
                      if (trimmed !== "") icon.detectedAgentBinary = trimmed
                    }
                  }
                }

                MouseArea {
                  id: hoverArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.focusWorkspace(cell.modelData)
                  onEntered: if (root.bar) root.bar.showTooltip(icon, icon.windowTitle)
                  onExited: if (root.bar) root.bar.hideTooltip(icon)
                }
              }
            }
          }

          // Mirrors the empty space WidgetButton's centered label leaves inside
          // its fixed-width box, so the badge gets the same breathing room after
          // the rightmost icon as it does before the workspace number.
          Item {
            Layout.alignment: Qt.AlignVCenter
            visible: icons.visible
            width: icons.visible ? Math.max(0, (numberButton.width - numberButton.labelWidth) / 2) : 0
          }
        }
      }
    }
  }
}
