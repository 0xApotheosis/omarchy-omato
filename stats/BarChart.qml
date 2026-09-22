import QtQuick
import qs.Commons

// Vertical bar chart over [{ label, title, value }]. An optional goal draws
// a guide line; hovering a bar shows its title and formatted value.
Column {
  id: chart

  property var model: []
  property real goal: 0
  property var format: v => String(v)
  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property real chartHeight: Style.space(110)
  property string emptyText: "Nothing yet"

  property int hovered: -1
  readonly property real maxValue: Math.max(goal, 1, ...model.map(m => m.value))
  readonly property real gap: model.length > 20 ? Style.space(2) : Style.space(6)
  readonly property real barWidth: model.length > 0 ? (width - gap * (model.length - 1)) / model.length : 0
  readonly property color dim: Qt.darker(foreground, 1.4)

  spacing: Style.space(4)

  Text {
    width: parent.width
    horizontalAlignment: Text.AlignRight
    text: {
      if (chart.hovered < 0 || chart.hovered >= chart.model.length) return " "
      var m = chart.model[chart.hovered]
      return m.title + "  ·  " + chart.format(m.value)
    }
    color: chart.dim
    font.family: chart.fontFamily
    font.pixelSize: Style.font.caption
  }

  Item {
    width: parent.width
    height: chart.chartHeight

    Row {
      anchors.fill: parent
      spacing: chart.gap

      Repeater {
        model: chart.model

        Item {
          id: slot
          required property var modelData
          required property int index
          readonly property bool hot: chart.hovered === index

          width: chart.barWidth
          height: parent.height

          Rectangle {
            anchors.fill: parent
            radius: Math.min(Style.cornerRadius, width / 2)
            color: Util.alpha(chart.foreground, slot.hot ? 0.08 : 0.04)
          }

          Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: slot.modelData.value > 0 ? Math.max(Style.space(2), parent.height * slot.modelData.value / chart.maxValue) : 0
            radius: Math.min(Style.cornerRadius, width / 2)
            color: slot.hot ? chart.accent : Util.alpha(chart.accent, 0.7)

            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onEntered: chart.hovered = slot.index
            onExited: if (chart.hovered === slot.index) chart.hovered = -1
          }
        }
      }
    }

    Rectangle {
      visible: chart.goal > 0
      width: parent.width
      height: 1
      y: parent.height - parent.height * chart.goal / chart.maxValue
      color: Util.alpha(chart.foreground, 0.35)
    }

    Text {
      anchors.centerIn: parent
      visible: !chart.model.some(m => m.value > 0)
      text: chart.emptyText
      color: chart.dim
      font.family: chart.fontFamily
      font.pixelSize: Style.font.caption
    }
  }

  Row {
    spacing: chart.gap

    Repeater {
      model: chart.model

      Text {
        required property var modelData
        width: chart.barWidth
        horizontalAlignment: Text.AlignHCenter
        text: modelData.label
        color: chart.dim
        font.family: chart.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
