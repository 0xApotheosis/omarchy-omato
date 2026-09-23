import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "TimerModel.js" as Model
import "components"

// Stats and settings, kept out of the bar panel, and the breathing lead-in
// before focus. Summoned by the shell:
//   omarchy-shell shell summon md.omodoro '{"tab":"stats"}'
//   omarchy-shell shell summon md.omodoro '{"mode":"breathe"}'
Item {
  id: root

  // Injected by the shell's panel loader.
  property var shell: null
  property var manifest: null
  property var service: null

  property bool opened: false
  property bool shown: false
  property string mode: "window"
  property string tab: "stats"

  readonly property bool breathing: mode === "breathe"
  readonly property string family: Style.font.menuFamily
  readonly property color foreground: Color.menu.text

  function open(payloadJson) {
    var payload = {}
    try { payload = payloadJson ? JSON.parse(payloadJson) : {} } catch (e) { /* open anyway */ }
    root.mode = payload.mode === "breathe" ? "breathe" : "window"
    if (payload.tab === "stats" || payload.tab === "settings") root.tab = payload.tab
    hideTimer.stop()
    root.opened = true
    root.shown = true
    Qt.callLater(() => (root.breathing ? breath : card).forceActiveFocus())
  }

  function close() {
    hideTimer.stop()
    root.shown = false
    root.opened = false
  }

  // Fades out, then hands back to the shell.
  function dismiss() {
    if (!root.opened || hideTimer.running) return
    root.shown = false
    hideTimer.restart()
  }

  function handleEscape() {
    if (root.breathing && root.service && root.service.breathing) root.service.cancelBreath()
    else root.dismiss()
  }

  function startNow() {
    if (root.service) root.service.finishBreath()
  }

  Timer {
    id: hideTimer
    interval: 320
    onTriggered: {
      root.opened = false
      if (root.shell) root.shell.hide("md.omodoro")
    }
  }

  // The lead-in ended, was skipped, or was cancelled.
  Connections {
    target: root.service
    function onBreathingChanged() {
      if (root.breathing && !root.service.breathing) root.dismiss()
    }
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
      onActivated: root.handleEscape()
    }

    Item {
      anchors.fill: parent
      opacity: root.shown ? 1 : 0

      Behavior on opacity {
        NumberAnimation { duration: 320; easing.type: Easing.InOutSine }
      }

      Rectangle {
        anchors.fill: parent
        color: Color.menu.scrim
      }

      Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.breathing ? 0.6 : 0
      }

      MouseArea {
        anchors.fill: parent
        onClicked: root.breathing ? root.startNow() : root.dismiss()
      }

      BreathView {
        id: breath
        anchors.fill: parent
        visible: root.opened && root.breathing
        startedAt: root.service ? root.service.breathStartedAt : 0
        breaths: root.service ? root.service.config.breaths : 1
        label: root.service ? root.service.label : ""
        nextText: root.service
          ? Model.NAMES.focus + " " + Model.fmtClock(Model.durationSec("focus", root.service.config))
          : ""
        foreground: root.foreground
        fontFamily: root.family

        Keys.onPressed: function(event) {
          if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.startNow()
            event.accepted = true
          }
        }
      }

      WindowCard {
        id: card
        visible: !root.breathing
        anchors.centerIn: parent
        width: Math.min(Style.space(820), window.width - Style.gapsOut * 2)
        height: Math.min(Style.space(780), window.height - Style.gapsOut * 2)
        service: root.service
        active: root.opened && !root.breathing
        tab: root.tab
        foreground: root.foreground
        family: root.family
        onTabChosen: function(value) { root.tab = value }
      }
    }
  }
}
