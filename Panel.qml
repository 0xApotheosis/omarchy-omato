import QtQuick
import qs.Commons
import qs.Ui
import "TimerModel.js" as Model
import "components"

// The main timer view, deliberately minimal: countdown, controls, label and
// today's progress. Stats and settings open in their own window.
Panel {
  id: root
  moduleName: "md.omodoro"
  manageIpc: false

  property var service: null
  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  readonly property bool ready: service !== null
  readonly property string phase: ready ? service.phase : "idle"
  readonly property bool onBreak: phase === "short" || phase === "long"
  property bool confirmAbandon: false

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(fg, 1.4)
  readonly property color accent: Color.accent
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color phaseColor: !ready ? dim
    : service.inOvertime ? urgent
    : onBreak ? accent
    : service.paused || phase === "idle" ? dim : fg
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string phaseName: {
    if (!ready) return ""
    if (phase === "idle") return "Up next: " + Model.NAMES[service.upNext]
    if (service.inOvertime) return "Overtime"
    return Model.NAMES[phase] + (service.paused ? " · paused" : "")
  }

  readonly property string primaryText: !ready ? "" : service.inOvertime ? "Finish"
    : phase === "idle" ? "Start" : service.paused ? "Resume" : "Pause"
  readonly property string primaryIcon: !ready ? "" : service.inOvertime ? Model.G.finish
    : phase === "idle" || service.paused ? Model.G.play : Model.G.pause

  // ---- lifecycle (same contract omarchy.weather implements)
  function openFromHotkey() {
    root.controller.show()
    labelField.text = ready ? service.label : ""
  }

  function open() { openFromHotkey() }

  function close() {
    root.controller.hide()
    confirmAbandon = false
  }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  // The overlay takes exclusive keyboard focus, so the popup closes first.
  function openWindow(tab) {
    root.close()
    if (root.bar && root.bar.shell) root.bar.shell.summon("md.omodoro", JSON.stringify({ tab: tab }))
  }

  function primary() {
    if (!ready) return
    if (service.inOvertime) service.finish()
    else service.toggle()
  }

  function abandon() {
    if (!ready || !service.running) return
    if (!confirmAbandon) {
      confirmAbandon = true
      confirmTimer.restart()
      return
    }
    confirmAbandon = false
    service.abandon()
  }

  Timer {
    id: confirmTimer
    interval: 3000
    onTriggered: root.confirmAbandon = false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: labelField.activeFocus
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onActivateRequested: root.primary()
      onTextKey: function(t) {
        var k = t.toLowerCase()
        if (k === "s" && root.ready) root.service.skip()
        else if (k === "a") root.abandon()
        else if (k === "e") labelField.forceActiveFocus()
        else if (k === "t") root.openWindow("stats")
        else if (k === ",") root.openWindow("settings")
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Item {
          width: parent.width
          height: Math.max(title.implicitHeight, headerButtons.implicitHeight)

          Text {
            id: title
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Omodoro"
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          Row {
            id: headerButtons
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)

            PanelActionButton {
              iconText: Model.G.chart
              tooltipText: "Stats (t)"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.openWindow("stats")
            }

            PanelActionButton {
              iconText: Model.G.cog
              tooltipText: "Settings (,)"
              foreground: root.fg
              fontFamily: root.fontFamily
              onClicked: root.openWindow("settings")
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(190)

          ProgressRing {
            id: ring
            anchors.centerIn: parent
            width: parent.height
            height: parent.height
            progress: root.ready && root.service.running ? root.service.progress : 0
            thickness: Style.space(6)
            trackColor: Util.alpha(root.fg, 0.12)
            fillColor: root.phaseColor
          }

          Column {
            anchors.centerIn: parent
            spacing: Style.space(2)

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.ready ? Model.fmtClock(root.service.remaining) : "—"
              color: root.phaseColor
              font.family: root.fontFamily
              font.pixelSize: Math.round(Style.font.displayLarge * 1.6)
              font.bold: true
              font.features: { "tnum": 1 }
            }

            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              text: root.phaseName
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }
        }

        TextField {
          id: labelField
          width: parent.width
          placeholderText: Model.G.tag + "  What are you working on? (e)"
          foreground: root.fg
          font.family: root.fontFamily
          onAccepted: keyCatcher.forceActiveFocus()
          onEditingFinished: if (root.ready) root.service.setLabel(text)
          Keys.onEscapePressed: {
            text = root.ready ? root.service.label : ""
            keyCatcher.forceActiveFocus()
          }
        }

        Row {
          anchors.horizontalCenter: parent.horizontalCenter
          spacing: Style.space(8)

          Button {
            text: root.primaryText
            iconText: root.primaryIcon
            bordered: true
            selected: true
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.ready && (root.phase === "idle" || root.service.paused
              || root.service.inOvertime || root.service.canPause)
            tooltipText: "Space"
            onClicked: root.primary()
          }

          Button {
            text: "Skip"
            iconText: Model.G.skip
            bordered: true
            foreground: root.fg
            fontFamily: root.fontFamily
            enabled: root.ready && root.service.canSkip
            tooltipText: root.phase === "idle" ? "Skip the upcoming phase (s)" : "End this phase now (s)"
            onClicked: root.service.skip()
          }

          Button {
            visible: root.ready && root.service.running
            text: root.confirmAbandon ? "Really?" : "Abandon"
            iconText: Model.G.cancel
            bordered: true
            foreground: root.confirmAbandon ? root.urgent : root.fg
            fontFamily: root.fontFamily
            tooltipText: "Stop without counting it (a)"
            onClicked: root.abandon()
          }
        }

        PanelSeparator {
          foreground: root.fg
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          GoalDots {
            anchors.horizontalCenter: parent.horizontalCenter
            done: root.ready ? root.service.todayCount : 0
            goal: root.ready ? root.service.config.dailyGoal : 8
            doneColor: root.accent
            todoColor: Util.alpha(root.fg, 0.3)
            fontFamily: root.fontFamily
            fontSize: Style.font.body
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
              if (!root.ready) return ""
              var s = root.service
              var parts = [s.todayCount + " of " + s.config.dailyGoal + " today"]
              if (s.streak > 0) parts.push(Model.G.fire + " " + s.streak + "-day streak")
              if (s.config.strictMode) parts.push("strict")
              return parts.join("  ·  ")
            }
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
