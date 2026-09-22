import QtQuick
import "../TimerModel.js" as Model

// Today's pomodoros against the daily goal: one dot per pomodoro, filled
// as they are done, with a "+n" once the goal is passed.
Row {
  id: dots

  property int done: 0
  property int goal: 8
  property color doneColor: "white"
  property color todoColor: "gray"
  property string fontFamily: ""
  property real fontSize: 12

  spacing: Math.round(fontSize * 0.3)

  Repeater {
    model: Math.min(dots.goal, 16)

    Text {
      required property int index
      text: index < dots.done ? Model.G.dotOn : Model.G.dotOff
      color: index < dots.done ? dots.doneColor : dots.todoColor
      font.family: dots.fontFamily
      font.pixelSize: dots.fontSize
    }
  }

  Text {
    visible: dots.done > dots.goal
    text: "+" + (dots.done - dots.goal)
    color: dots.doneColor
    font.family: dots.fontFamily
    font.pixelSize: dots.fontSize
    font.bold: true
  }
}
