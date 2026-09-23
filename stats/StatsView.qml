import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui
import "../TimerModel.js" as Model
import "../Stats.js" as Stats

// History: headline numbers, the last week and month, the year, when in the
// day focus happens, and where it goes by label.
Item {
  id: view

  property var service: null
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family

  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property var idx: service ? service.index : Stats.index([])
  readonly property real now: service ? service.now : Date.now()
  readonly property int goal: service ? service.config.dailyGoal : 8

  readonly property var today: Stats.today(idx, now)
  readonly property var week: Stats.sumDays(idx, 7, now)
  readonly property int streak: Stats.streak(idx, goal, now)
  readonly property var days7: Stats.perDay(idx, 7, now).map(d => Object.assign({ value: d.pomodoros }, d))
  readonly property var days30: Stats.perDay(idx, 30, now).map(d => Object.assign({ value: d.pomodoros }, d))
  readonly property var hours: Stats.byHour(idx).map(h => Object.assign({ value: h.focusSec }, h))
  readonly property var plural: n => n + " pomodoro" + (n === 1 ? "" : "s")

  component StatTile: BorderSurface {
    id: tile
    property string title: ""
    property string value: ""
    property string note: ""

    color: Style.normalFillFor(view.foreground, view.accent)
    borderSpec: Border.controlSpec("normal", view.foreground, view.accent)
    radius: Style.cornerRadius
    padding: Style.space(8)
    implicitHeight: tileColumn.implicitHeight + padding * 2

    Column {
      id: tileColumn
      anchors { left: parent.left; right: parent.right; top: parent.top; margins: tile.padding }
      spacing: Style.space(1)

      Text {
        width: parent.width
        text: tile.title.toUpperCase()
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }

      Text {
        width: parent.width
        text: tile.value
        color: view.foreground
        font.family: view.fontFamily
        font.pixelSize: Style.font.heading
        font.bold: true
      }

      Text {
        width: parent.width
        text: tile.note
        color: view.dim
        font.family: view.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }

  component Section: PanelSectionHeader {
    foreground: view.foreground
    fontFamily: view.fontFamily
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

      Grid {
        id: tiles
        width: parent.width
        columns: 5
        spacing: Style.space(8)
        readonly property real tileWidth: (width - spacing * (columns - 1)) / columns

        StatTile {
          width: tiles.tileWidth
          title: "Today"
          value: view.today.pomodoros + " / " + view.goal
          note: Model.fmtDuration(view.today.focusSec) + " focused"
        }

        StatTile {
          width: tiles.tileWidth
          title: "Last 7 days"
          value: String(view.week.pomodoros)
          note: Model.fmtDuration(view.week.focusSec) + " focused"
        }

        StatTile {
          width: tiles.tileWidth
          title: "Streak"
          value: view.streak + (view.streak === 1 ? " day" : " days")
          note: "Best " + Stats.bestStreak(view.idx, view.goal)
        }

        StatTile {
          width: tiles.tileWidth
          title: "Extra rest"
          value: Model.fmtDuration(view.today.extraRestSec)
          note: Model.fmtDuration(view.week.extraRestSec) + " in 7 days"
        }

        StatTile {
          width: tiles.tileWidth
          title: "All time"
          value: String(view.idx.totals.pomodoros)
          note: Model.fmtDuration(view.idx.totals.focusSec) + " focused"
        }
      }

      Section { text: "Last 7 days" }

      BarChart {
        width: parent.width
        model: view.days7
        goal: view.goal
        format: view.plural
        foreground: view.foreground
        fontFamily: view.fontFamily
      }

      Section { text: "Last 30 days" }

      BarChart {
        width: parent.width
        model: view.days30
        goal: view.goal
        format: view.plural
        chartHeight: Style.space(80)
        foreground: view.foreground
        fontFamily: view.fontFamily
      }

      Section { text: "Past year" }

      Heatmap {
        width: parent.width
        weeks: Stats.yearHeatmap(view.idx, view.goal, view.now)
        foreground: view.foreground
        fontFamily: view.fontFamily
      }

      Row {
        width: parent.width
        spacing: Style.space(20)

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.space(10)

          Section { text: "Time of day" }

          BarChart {
            width: parent.width
            model: view.hours
            format: Model.fmtDuration
            chartHeight: Style.space(80)
            foreground: view.foreground
            fontFamily: view.fontFamily
          }
        }

        Column {
          width: (parent.width - parent.spacing) / 2
          spacing: Style.space(10)

          Section { text: "By label" }

          LabelBreakdown {
            width: parent.width
            rows: Stats.byLabel(view.idx, 6)
            foreground: view.foreground
            fontFamily: view.fontFamily
          }
        }
      }
    }
  }
}
