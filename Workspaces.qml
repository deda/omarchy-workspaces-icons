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

  // Match a running window back to the same desktop entry the app launcher
  // menu would show for it, so icons stay consistent with the launcher.
  // Desktop entries record the window class they expect under
  // StartupWMClass, which is often different from the entry's own id (e.g.
  // Obsidian's id is "obsidian" but StartupWMClass is "md.Obsidian") - byId()
  // and heuristicLookup() only match against id/name, not StartupWMClass, so
  // check that first.
  function findDesktopEntry(appId) {
    if (!appId) return null

    var lower = appId.toLowerCase()
    var values = DesktopEntries.applications.values || []
    var i, startupClass

    for (i = 0; i < values.length; i++) {
      startupClass = String(values[i].startupClass || "").toLowerCase()
      if (startupClass !== "" && startupClass === lower) return values[i]
    }

    // Some packaged apps report a runtime app id that only partially matches
    // their own StartupWMClass (e.g. Obsidian ships "md.Obsidian" but the
    // live window reports "md.obsidian.Obsidian") - allow a substring match
    // as a second pass before falling back to id/name-based lookups.
    for (i = 0; i < values.length; i++) {
      startupClass = String(values[i].startupClass || "").toLowerCase()
      if (startupClass !== "" && (lower.indexOf(startupClass) !== -1 || startupClass.indexOf(lower) !== -1))
        return values[i]
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

              width: cell.iconSize
              height: cell.iconSize
              source: iconName !== "" ? Quickshell.iconPath(iconName, "application-x-executable") : ""
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
