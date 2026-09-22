import QtQuick
import qs.Commons
import qs.Ui

// Omodoro bar chip: phase glyph + countdown (+ today's goal progress).
// The service owns the timer; this widget renders it and hosts the panel.
// Left click opens the panel, middle click starts/pauses, right click skips.
BarWidget {
  id: root
  moduleName: "md.omodoro"

  readonly property var service: bar && bar.shell ? bar.shell.serviceFor("md.omodoro") : null

  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.service = root.service
    target.anchorItem = button
    target.hostWidget = root
  }

  function togglePanel() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  // shell.summon/hide/toggle contract: Bar.findPanelWidget requires
  // open/close/opened on the bar-widget root.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false

  function open() {
    if (panelLoader.item) panelLoader.item.openFromHotkey()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  readonly property real openPanelIndicatorWidth: button.labelWidth

  readonly property color baseForeground: bar ? bar.barForeground : Color.foreground
  readonly property bool onBreak: service ? service.phase === "short" || service.phase === "long" : false
  readonly property bool idle: service ? !service.running || service.paused : true

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()
  onSettingsChanged: injectPanel()
  onServiceChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.service ? root.service.barLabel : ""
    labelVisible: true
    hasVisualContent: text !== ""
    active: root.service ? root.service.inOvertime : false
    foreground: root.onBreak ? Color.accent
      : (root.idle ? Qt.darker(root.baseForeground, 1.55) : root.baseForeground)
    horizontalMargin: 8.75
    verticalPadding: 8.75
    tooltipText: root.service ? root.service.tooltip : "Omodoro"

    onPressed: function(b) {
      if (!root.service) return
      if (b === Qt.MiddleButton) root.service.toggle()
      else if (b === Qt.RightButton) root.service.skip()
      else root.togglePanel()
    }
  }
}
