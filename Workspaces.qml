import QtQuick
import QtQuick.Layouts
import Quickshell
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

  // Window classes with no desktop entry at all to fall back to a real icon
  // instead of the generic application-x-executable glyph. org.omarchy.agent
  // is a fixed shared class every coding agent CLI launches under (see
  // omarchy-agent), so there's no single desktop entry to resolve to - reuse
  // the Claude icon the omarchy.agents bar panel itself ships, since Claude
  // is Omarchy's default agent.
  readonly property var manualIconOverrides: ({
    "org.omarchy.agent": "/usr/share/omarchy/shell/plugins/agents/assets/claude.svg",
  })

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
              required property var modelData

              readonly property string windowClass: (modelData.wayland && modelData.wayland.appId)
                || (modelData.lastIpcObject && modelData.lastIpcObject.class) || ""

              // Resolve through the app's desktop entry first, same as the Omarchy
              // app launcher menu does, since a window's app id often differs from
              // the icon name in its .desktop file (e.g. Slack, Obsidian).
              readonly property var desktopEntry: root.findDesktopEntry(windowClass)
              readonly property string iconName: (desktopEntry && desktopEntry.icon) || windowClass
              readonly property string overridePath: root.manualIconOverrides[windowClass] || ""

              width: cell.iconSize
              height: cell.iconSize
              source: overridePath !== "" ? Util.fileUrl(overridePath)
                : iconName !== "" ? Quickshell.iconPath(iconName, "application-x-executable") : ""
              fillMode: Image.PreserveAspectFit
              asynchronous: true
              smooth: true
              visible: status === Image.Ready

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
