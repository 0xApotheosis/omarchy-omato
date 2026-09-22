import QtQuick
import qs.Commons

// GitHub-style year grid from Stats.yearHeatmap: 53 week columns of seven
// days, shaded by how much of the daily goal each day reached.
Column {
  id: heatmap

  property var weeks: []
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family

  property var hoveredDay: null
  readonly property real gap: Style.space(2)
  readonly property real cell: weeks.length > 0 ? Math.floor((width - gap * (weeks.length - 1)) / weeks.length) : 0
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property var shades: [0.08, 0.3, 0.5, 0.75, 1]

  spacing: Style.space(4)

  Row {
    spacing: heatmap.gap

    Repeater {
      model: heatmap.weeks

      Text {
        required property var modelData
        width: heatmap.cell
        text: modelData.month
        clip: false
        color: heatmap.dim
        font.family: heatmap.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  Row {
    spacing: heatmap.gap

    Repeater {
      model: heatmap.weeks

      Column {
        required property var modelData
        spacing: heatmap.gap

        Repeater {
          model: modelData.days

          Rectangle {
            required property var modelData
            width: heatmap.cell
            height: heatmap.cell
            radius: Math.min(Style.cornerRadius, heatmap.cell / 4)
            visible: !modelData.future
            color: modelData.level === 0
              ? Util.alpha(heatmap.foreground, heatmap.shades[0])
              : Util.alpha(heatmap.accent, heatmap.shades[modelData.level])
            border.width: heatmap.hoveredDay === modelData ? 1 : 0
            border.color: heatmap.foreground

            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              onEntered: heatmap.hoveredDay = parent.modelData
              onExited: if (heatmap.hoveredDay === parent.modelData) heatmap.hoveredDay = null
            }
          }
        }
      }
    }
  }

  Text {
    width: parent.width
    horizontalAlignment: Text.AlignRight
    text: heatmap.hoveredDay
      ? heatmap.hoveredDay.title + "  ·  " + heatmap.hoveredDay.pomodoros + " pomodoro" + (heatmap.hoveredDay.pomodoros === 1 ? "" : "s")
      : " "
    color: heatmap.dim
    font.family: heatmap.fontFamily
    font.pixelSize: Style.font.caption
  }
}
