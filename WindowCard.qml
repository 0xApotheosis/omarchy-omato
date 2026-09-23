import QtQuick
import qs.Commons
import qs.Ui
import "stats"
import "settings"

// The stats and settings card inside the overlay window.
BorderSurface {
  id: card

  property var service: null
  property bool active: false
  property string tab: "stats"
  property color foreground: Color.menu.text
  property string family: Style.font.menuFamily

  signal tabChosen(string value)

  radius: Style.cornerRadius
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  padding: Style.spacing.panelPadding

  Keys.onPressed: function(event) {
    if (event.text === "1") { card.tabChosen("stats"); event.accepted = true }
    else if (event.text === "2") { card.tabChosen("settings"); event.accepted = true }
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
        color: card.foreground
        font.family: card.family
        font.pixelSize: Style.font.title
        font.weight: Font.Medium
      }

      ButtonGroup {
        id: tabRow
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        foreground: card.foreground
        fontFamily: card.family
        fontSize: Style.font.caption
        focusable: false
        options: [{ value: "stats", label: "Stats" }, { value: "settings", label: "Settings" }]
        value: card.tab
        onChanged: function(value) { card.tabChosen(value) }
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
        active: card.active && card.tab === "stats"
        visible: active
        sourceComponent: StatsView {
          service: card.service
          foreground: card.foreground
          fontFamily: card.family
        }
      }

      Loader {
        anchors.fill: parent
        active: card.active && card.tab === "settings"
        visible: active
        sourceComponent: SettingsView {
          service: card.service
          foreground: card.foreground
          fontFamily: card.family
        }
      }
    }
  }
}
