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

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
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

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      RowLayout {
        id: cell
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property var toplevels: workspace !== null ? workspace.toplevels.values : []
        readonly property bool occupied: toplevels.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property real iconSize: Style.space(10)

        spacing: Style.space(2)

        WidgetButton {
          bar: root.bar
          text: cell.focused ? "\uDB85\uDCFB" : (cell.modelData === 10 ? "0" : String(cell.modelData))
          opacity: cell.occupied || cell.focused ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(cell.modelData) }
        }

        Row {
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
              readonly property string iconName: (desktopEntry && desktopEntry.icon) || lookupClass
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
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.focusWorkspace(cell.modelData)
              }
            }
          }
        }
      }
    }
  }
}
