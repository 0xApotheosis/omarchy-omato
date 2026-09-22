import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "stats"
import "settings"

// Stats and settings, kept out of the bar panel. Summoned by the shell:
//   omarchy-shell shell summon md.omodoro '{"tab":"stats"}'
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property string tab: "stats"

  readonly property string family: Style.font.menuFamily
  readonly property color foreground: Color.menu.text
  readonly property var borderSpec: Border.surfaceSpec(
    "menu", "border", Color.menu.border, Math.max(1, Style.space(2)))

  function open(payloadJson) {
    try {
      var payload = payloadJson ? JSON.parse(payloadJson) : {}
      if (payload.tab === "stats" || payload.tab === "settings") root.tab = payload.tab
    } catch (e) {
      // Not worth refusing to open over.
    }
    root.opened = true
    Qt.callLater(() => card.forceActiveFocus())
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell) root.shell.hide("md.omodoro")
  }

  PanelWindow {
    id: window
    visible: root.opened
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    WlrLayershell.namespace: "omodoro"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore

    Shortcut {
      sequence: "Escape"
      onActivated: root.dismiss()
    }

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(820), window.width - Style.gapsOut * 2)
      height: Math.min(Style.space(780), window.height - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: root.borderSpec
      padding: Style.spacing.panelPadding
      focus: true

      Keys.onPressed: function(event) {
        if (event.text === "1") { root.tab = "stats"; event.accepted = true }
        else if (event.text === "2") { root.tab = "settings"; event.accepted = true }
      }

      MouseArea { anchors.fill: parent }

      Item {
        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset

        Item {
          id: header
          anchors { top: parent.top; left: parent.left; right: parent.right }
          height: Math.max(heading.implicitHeight, tabRow.implicitHeight)

          Text {
            id: heading
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Omodoro"
            color: root.foreground
            font.family: root.family
            font.pixelSize: Style.font.title
            font.weight: Font.Medium
          }

          ButtonGroup {
            id: tabRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            foreground: root.foreground
            fontFamily: root.family
            fontSize: Style.font.caption
            focusable: false
            options: [{ value: "stats", label: "Stats" }, { value: "settings", label: "Settings" }]
            value: root.tab
            onChanged: function(value) { root.tab = value }
          }
        }

        PanelSeparator {
          id: rule
          anchors { top: header.bottom; left: parent.left; right: parent.right }
          anchors.topMargin: Style.space(12)
        }

        Item {
          anchors { top: rule.bottom; bottom: parent.bottom; left: parent.left; right: parent.right }
          anchors.topMargin: Style.space(14)

          Loader {
            anchors.fill: parent
            active: root.opened && root.tab === "stats"
            visible: active
            sourceComponent: StatsView {
              service: root.service
              foreground: root.foreground
              fontFamily: root.family
            }
          }

          Loader {
            anchors.fill: parent
            active: root.opened && root.tab === "settings"
            visible: active
            sourceComponent: SettingsView {
              service: root.service
              foreground: root.foreground
              fontFamily: root.family
            }
          }
        }
      }
    }
  }
}
