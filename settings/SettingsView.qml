import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui

// Settings, written straight to the widget's shell.json entry. The same
// keys are declared in manifest.json, so Omarchy's own settings UI agrees.
Item {
  id: view

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property var cfg: service ? service.config : ({})
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property int hostCount: service ? new Set(service.sessions.map(s => s.host)).size : 0

  function set(key, value) {
    if (!service) return
    var patch = {}
    patch[key] = value
    service.updateSettings(patch)
  }

  component Section: PanelSectionHeader {
    foreground: view.foreground
    fontFamily: view.fontFamily
  }

  component Minutes: NumberField {
    property string key: ""
    value: view.cfg[key] || 0
    foreground: view.foreground
    fontFamily: view.fontFamily
    onModified: function(v) { view.set(key, v) }
  }

  component SettingToggle: Toggle {
    property string key: ""
    width: parent ? parent.width : implicitWidth
    checked: view.cfg[key] === true
    foreground: view.foreground
    fontFamily: view.fontFamily
    onClicked: view.set(key, !checked)
  }

  component Note: Text {
    width: parent ? parent.width : implicitWidth
    color: view.dim
    font.family: view.fontFamily
    font.pixelSize: Style.font.caption
    wrapMode: Text.WordWrap
  }

  Flickable {
    id: flick
    anchors.fill: parent
    clip: true
    contentWidth: width
    contentHeight: column.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

    Column {
      id: column
      width: flick.width - Style.space(12)
      spacing: Style.space(14)

      Section { text: "Timer" }

      Flow {
        width: parent.width
        spacing: Style.space(16)

        Minutes { key: "focusMinutes"; label: "Focus (min)"; from: 1; to: 180 }
        Minutes { key: "shortBreakMinutes"; label: "Short break (min)"; from: 1; to: 60 }
        Minutes { key: "longBreakMinutes"; label: "Long break (min)"; from: 1; to: 120 }
        Minutes { key: "longBreakEvery"; label: "Long break every"; from: 2; to: 12 }
        Minutes { key: "dailyGoal"; label: "Daily goal"; from: 1; to: 32 }
      }

      Note { text: "New lengths apply from the next phase." }

      Section { text: "Behaviour" }

      Column {
        width: parent.width
        spacing: Style.space(8)

        SettingToggle {
          key: "strictMode"
          label: "Strict mode"
          description: "No pausing or skipping once focus starts. Abandon still works, after a confirm."
        }

        SettingToggle {
          key: "overtime"
          label: "Overtime"
          description: "Keep counting past zero at the end of focus until you finish it."
        }

        SettingToggle {
          key: "dnd"
          label: "Do Not Disturb while focusing"
          description: "Turned back off afterwards, unless it was already on."
        }

        SettingToggle {
          key: "sound"
          label: "Chime"
          description: "Play a sound with the notification at the end of each phase."
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Note { text: "Chime sound file" }

        TextField {
          width: parent.width
          text: view.cfg.soundFile || ""
          foreground: view.foreground
          onEditingFinished: view.set("soundFile", text.trim())
        }
      }

      Column {
        width: parent.width
        spacing: Style.space(6)

        Note { text: "Bar chip" }

        ButtonGroup {
          foreground: view.foreground
          fontFamily: view.fontFamily
          fontSize: Style.font.caption
          options: [{ value: "countdown", label: "Countdown" },
                    { value: "countdown+goal", label: "Countdown + today's goal" }]
          value: view.cfg.barMode || "countdown+goal"
          onChanged: function(value) { view.set("barMode", value) }
        }
      }

      Section { text: "History" }

      Column {
        width: parent.width
        spacing: Style.space(8)

        Note {
          text: "Folder for session history. Put it in Dropbox to sync and back it up; each machine writes only its own file, so there are no conflicted copies."
        }

        TextField {
          id: dirField
          width: parent.width
          text: view.cfg.dataDir || ""
          placeholderText: "~/Dropbox/Omarchy/omodoro"
          foreground: view.foreground
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Move history here"
            bordered: true
            foreground: view.foreground
            fontFamily: view.fontFamily
            enabled: view.service && dirField.text.trim() !== "" && dirField.text.trim() !== view.cfg.dataDir
            onClicked: view.service.moveDataDir(dirField.text)
          }

          Button {
            text: "Switch without moving"
            bordered: true
            foreground: view.foreground
            fontFamily: view.fontFamily
            enabled: view.service && dirField.text.trim() !== "" && dirField.text.trim() !== view.cfg.dataDir
            onClicked: view.set("dataDir", dirField.text.trim())
          }
        }

        Note {
          text: !view.service ? ""
            : view.service.historyError !== "" ? view.service.historyError
            : view.service.sessions.length + " sessions from " + view.hostCount + (view.hostCount === 1 ? " machine" : " machines")
              + " in " + view.service.dataDir
        }

        Row {
          spacing: Style.space(8)

          Button {
            text: "Export JSON + CSV"
            bordered: true
            foreground: view.foreground
            fontFamily: view.fontFamily
            enabled: view.service !== null
            onClicked: view.service.exportHistory()
          }

          Button {
            text: "Reset cycle"
            bordered: true
            foreground: view.foreground
            fontFamily: view.fontFamily
            tooltipText: "Start counting towards the next long break from zero"
            enabled: view.service !== null
            onClicked: view.service.resetCycle()
          }
        }

        Note {
          visible: text !== ""
          text: view.service && view.service.lastExport !== "" ? "Exported to " + view.service.lastExport : ""
        }
      }
    }
  }
}
