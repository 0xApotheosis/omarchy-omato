import QtQuick
import qs.Commons
import "../TimerModel.js" as Model

// Guided breath before focus: a disc that fills on the in-breath, rests,
// and empties on the out-breath. Everything derives from wall-clock time,
// read once per frame, so it stays in step with the service's timer however
// late the window opens.
Item {
  id: view

  property real startedAt: 0
  property int breaths: 1
  property string label: ""
  property string nextText: ""
  property color accent: Color.accent
  property color foreground: Color.foreground
  property color base: Color.menu.background
  property string fontFamily: Style.font.family

  property real elapsed: 0

  readonly property var b: Model.BREATH
  readonly property int breath: Math.max(0, Math.min(breaths - 1, Math.floor(elapsed / Model.BREATH_MS)))
  readonly property real local: Math.max(0, elapsed - breath * Model.BREATH_MS)
  readonly property string stage: local < b.inhale ? "in" : local < b.inhale + b.hold ? "hold" : "out"
  readonly property real stageStart: stage === "in" ? 0 : stage === "hold" ? b.inhale : b.inhale + b.hold
  readonly property real stageLength: stage === "in" ? b.inhale : stage === "hold" ? b.hold : b.exhale
  readonly property real stageAt: Math.max(0, Math.min(stageLength, local - stageStart))
  readonly property real stageLeft: stageLength - stageAt

  // 0 = empty lungs, 1 = full. Sine easing: slow at the turns, like a breath.
  readonly property real level: stage === "in" ? ease(stageAt / b.inhale)
    : stage === "hold" ? 1 : 1 - ease(stageAt / b.exhale)

  readonly property string word: stage === "in" ? "Breathe in" : stage === "hold" ? "Hold" : "Breathe out"
  readonly property int count: Math.max(1, Math.ceil(stageLeft / 1000))
  // Each word fades in and out at the edges of its stage.
  readonly property real wordOpacity: Math.max(0, Math.min(1, stageAt / 350, stageLeft / 350))

  readonly property real maxSize: Math.min(width, height) * 0.46
  readonly property real minSize: maxSize * 0.42
  readonly property real size: minSize + (maxSize - minSize) * level

  function ease(p) {
    return 0.5 - 0.5 * Math.cos(Math.PI * Math.max(0, Math.min(1, p)))
  }

  FrameAnimation {
    running: view.visible && view.startedAt > 0
    onTriggered: view.elapsed = Date.now() - view.startedAt
  }

  component Disc: Rectangle {
    property real factor: 1
    anchors.centerIn: parent
    width: view.size * factor
    height: width
    radius: width / 2
  }

  Item {
    id: centre
    anchors.centerIn: parent
    anchors.verticalCenterOffset: -view.maxSize * 0.08
    width: view.maxSize * 1.6
    height: width

    Disc {
      factor: 1.55
      color: Util.alpha(view.accent, 0.04 + 0.05 * view.level)
    }

    Disc {
      factor: 1.25
      color: Util.alpha(view.accent, 0.08 + 0.08 * view.level)
    }

    // Opaque, so the wallpaper never shows through the text.
    Disc {
      color: Qt.tint(view.base, Util.alpha(view.accent, 0.16 + 0.2 * view.level))
      border.color: Util.alpha(view.accent, 0.6 + 0.4 * view.level)
      border.width: Math.max(1, Style.space(2))
    }

    Column {
      anchors.centerIn: parent
      spacing: Style.space(4)
      opacity: view.wordOpacity

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: view.word
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Math.round(Style.font.title * 2.2)
        font.weight: Font.Medium
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: view.count
        color: view.accent
        font.family: view.fontFamily
        font.pixelSize: Math.round(Style.font.displayLarge * 2)
        font.bold: true
        font.features: { "tnum": 1 }
      }
    }
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.top: centre.bottom
    anchors.topMargin: Style.space(8)
    spacing: Style.space(6)

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: Style.space(8)
      visible: view.breaths > 1

      Repeater {
        model: view.breaths
        Rectangle {
          required property int index
          width: Style.space(8)
          height: width
          radius: width / 2
          color: index <= view.breath ? view.accent : Util.alpha(view.foreground, 0.25)
          Behavior on color { ColorAnimation { duration: 300 } }
        }
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: view.label !== "" ? view.label + "  ·  " + view.nextText : view.nextText
      color: Qt.darker(view.foreground, 1.3)
      font.family: view.fontFamily
      font.pixelSize: Style.font.title
    }
  }

  Text {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(48)
    text: "Space to start now  ·  Esc to cancel"
    color: Qt.darker(view.foreground, 1.6)
    font.family: view.fontFamily
    font.pixelSize: Style.font.body
  }
}
