import QtQuick
import qs.Commons
import "../TimerModel.js" as Model

// Focus time per label, largest first, each with a proportional bar.
Column {
  id: breakdown

  property var rows: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  readonly property real maxSec: Math.max(1, ...rows.map(r => r.focusSec))
  readonly property color dim: Qt.darker(foreground, 1.4)

  spacing: Style.space(8)

  Text {
    visible: breakdown.rows.length === 0
    text: "Label a session in the panel to see it here."
    color: breakdown.dim
    font.family: breakdown.fontFamily
    font.pixelSize: Style.font.caption
  }

  Repeater {
    model: breakdown.rows

    Column {
      required property var modelData
      width: breakdown.width
      spacing: Style.space(3)

      Item {
        width: parent.width
        height: name.implicitHeight

        Text {
          id: name
          anchors.left: parent.left
          anchors.right: amount.left
          anchors.rightMargin: Style.space(8)
          text: modelData.label
          elide: Text.ElideRight
          color: breakdown.foreground
          font.family: breakdown.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        Text {
          id: amount
          anchors.right: parent.right
          text: modelData.pomodoros + "  ·  " + Model.fmtDuration(modelData.focusSec)
          color: breakdown.dim
          font.family: breakdown.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Rectangle {
        width: parent.width * modelData.focusSec / breakdown.maxSec
        height: Style.space(4)
        radius: height / 2
        color: Util.alpha(breakdown.accent, 0.75)
      }
    }
  }
}
