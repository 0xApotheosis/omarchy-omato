import QtQuick
import Quickshell
import Quickshell.Io
import "TimerModel.js" as Model
import "Stats.js" as Stats
import "ServiceGuard.js" as Guard

// Owner of all Omodoro state. A `service` is mounted once per session, a
// `bar-widget` once per monitor, so the timer lives here and the widgets
// reach it through `bar.shell.serviceFor("md.omodoro")`.
//
// Timing is wall-clock: only `endsAt` (or `pausedRemaining`) is stored, so a
// plugin reload, shell restart, or suspend resumes exactly where it was.
Item {
  id: root

  // Injected by the shell.
  property var shell: null
  property var manifest: null

  readonly property string pluginId: "md.omodoro"
  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/md.omodoro"

  // ---- settings, inline on the bar entry in shell.json. Read from the file:
  //      the shell's barConfig snapshot only refreshes on plugin rescans.
  property var shellBar: null
  readonly property var rawSettings: Model.findEntry(shellBar || (shell ? shell.barConfig : null), pluginId)

  FileView {
    path: root.home + "/.config/omarchy/shell.json"
    blockLoading: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try { root.shellBar = JSON.parse(text()).bar || null } catch (e) { /* keep the last good read */ }
    }
  }
  readonly property var config: Model.readSettings(rawSettings)
  readonly property string dataDir: Model.expandHome(config.dataDir, home)

  function updateSettings(patch) {
    if (!shell || typeof shell.updateEntryInline !== "function") return false
    return shell.updateEntryInline(pluginId, Object.assign({}, rawSettings, patch))
  }

  // ---- timer state (persisted in timer.json)
  readonly property string phase: st.phase
  readonly property bool paused: st.paused
  readonly property string upNext: st.upNext
  readonly property string label: st.label
  readonly property int cycleCount: st.cycleCount

  property double now: Date.now()

  readonly property bool running: phase !== "idle"
  readonly property bool ticking: running && !paused
  readonly property int plannedSec: running ? st.plannedSec : Model.durationSec(upNext, config)
  readonly property int remaining: running
    ? Model.remainingSec(paused, st.pausedRemaining, st.endsAt, now)
    : plannedSec
  readonly property bool onBreak: phase === "short" || phase === "long"
  // Past the planned end: focus overtime, or extra rest on a break.
  readonly property bool inOvertime: running && remaining < 0
  readonly property bool inExtraRest: onBreak && inOvertime
  readonly property real progress: plannedSec > 0 ? Math.max(0, Math.min(1, 1 - remaining / plannedSec)) : 0
  readonly property bool locked: config.strictMode && phase === "focus" && !inOvertime
  readonly property bool canPause: running && !locked && !inOvertime
  readonly property bool canSkip: !locked

  // ---- history
  readonly property var sessions: history.sessions
  readonly property var index: history.index
  readonly property var todayStats: Stats.today(index, now)
  readonly property int todayCount: todayStats.pomodoros
  readonly property int streak: Stats.streak(index, config.dailyGoal, now)

  // Guided breathing before focus. Not persisted: a restart drops it.
  property real breathStartedAt: 0
  readonly property bool breathing: breathStartedAt > 0
  readonly property int breathMs: config.breaths * Model.BREATH_MS

  readonly property var summary: ({
    breathing: breathing, phase: phase, paused: paused, remaining: remaining, upNext: upNext,
    upNextSec: Model.durationSec(upNext, config), label: label,
    today: todayCount, goal: config.dailyGoal, streak: streak, mode: config.barMode
  })
  readonly property string barLabel: Model.barLabel(summary)
  readonly property string tooltip: Model.tooltip(summary)

  // ---- actions
  function start() {
    if (breathing) return finishBreath()
    if (paused) return resume()
    if (inExtraRest) complete("completed", Date.now())
    if (running) return false
    if (upNext === "focus" && config.breathe) beginBreath()
    else begin(upNext)
    return true
  }

  function beginBreath() {
    breathStartedAt = Date.now()
    breathTimer.restart()
    if (shell) shell.summon(pluginId, JSON.stringify({ mode: "breathe" }))
  }

  // Ends the lead-in, on time or early, and starts focus.
  function finishBreath() {
    if (!breathing) return false
    breathTimer.stop()
    breathStartedAt = 0
    begin("focus")
    return true
  }

  function cancelBreath() {
    if (!breathing) return false
    breathTimer.stop()
    breathStartedAt = 0
    return true
  }

  function begin(kind) {
    var planned = Model.durationSec(kind, config)
    var startMs = Date.now()
    st.paused = false
    st.plannedSec = planned
    st.startedAt = startMs
    st.endsAt = startMs + planned * 1000
    st.pausedRemaining = 0
    st.alerted = false
    now = startMs
    // Last: this starts the tick timer, which fires immediately.
    st.phase = kind
    if (kind === "focus" && config.dnd) claimDnd()
  }

  function pause() {
    if (!canPause || paused) return false
    st.pausedRemaining = remaining
    st.paused = true
    return true
  }

  function resume() {
    if (!paused) return false
    st.endsAt = Date.now() + st.pausedRemaining * 1000
    st.paused = false
    now = Date.now()
    return true
  }

  function toggle() {
    if (breathing || !running || inExtraRest) return start()
    if (inOvertime) return finish()
    return paused ? resume() : pause()
  }

  // Ends the current phase now. In overtime this is how focus is finished.
  function finish() {
    if (!running || locked) return false
    complete(inOvertime || phase !== "focus" ? "completed" : "skipped", Date.now())
    return true
  }

  function skip() {
    if (!canSkip) return false
    if (!running) {
      st.upNext = Model.nextPhase(upNext, upNext === "focus" ? cycleCount + 1 : cycleCount, config)
      return true
    }
    return finish()
  }

  function abandon() {
    if (breathing) return cancelBreath()
    if (!running) return false
    complete("abandoned", Date.now())
    return true
  }

  function resetCycle() {
    if (running) complete("abandoned", Date.now())
    st.cycleCount = 0
    st.upNext = "focus"
  }

  function setLabel(text) {
    st.label = String(text || "").trim().slice(0, 80)
  }

  function exportHistory() {
    return history.exportAll()
  }

  // Moves the history files, then points the setting at the new folder.
  function moveDataDir(path) {
    var target = Model.expandHome(String(path || "").trim(), home)
    if (!target || target === dataDir) return false
    pendingDataDir = String(path).trim()
    return history.moveTo(target)
  }
  property string pendingDataDir: ""

  // ---- phase transitions
  function complete(outcome, endMs, message) {
    var kind = phase
    var planned = st.plannedSec
    var left = Model.remainingSec(paused, st.pausedRemaining, st.endsAt, endMs)
    var actual = Math.max(0, planned - left)
    history.append({
      id: Model.uuid(),
      host: host,
      kind: kind,
      label: st.label,
      start: new Date(st.startedAt).toISOString(),
      end: new Date(endMs).toISOString(),
      plannedSec: planned,
      actualSec: actual,
      overtimeSec: Math.max(0, -left),
      outcome: outcome
    })

    var counted = kind === "focus" && outcome === "completed"
    var cycle = counted ? cycleCount + 1 : (kind === "long" ? 0 : cycleCount)
    st.cycleCount = cycle
    st.upNext = outcome === "abandoned" ? "focus" : Model.nextPhase(kind, cycle, config)
    st.phase = "idle"
    st.paused = false
    st.alerted = false
    var releasing = kind === "focus" && st.dndOwned
    if (releasing) st.dndOwned = false
    runEffects(releasing, message || null)
  }

  function endMessage(counting) {
    if (phase !== "focus")
      return { summary: "Break's over", body: "Extra rest is counting. Start the next focus when you're ready." }
    if (counting)
      return { summary: "Focus time's up", body: "Overtime is counting. Finish when you're ready." }
    var next = Model.nextPhase("focus", cycleCount + 1, config)
    return {
      summary: "Pomodoro done",
      body: (todayCount + 1) + " of " + config.dailyGoal + " today. Up next: " + Model.NAMES[next].toLowerCase() + "."
    }
  }

  // Breaks always count past their end as extra rest; focus only with the
  // overtime setting. Either stops counting after MAX_OVERTIME_SEC. A phase
  // that ran out while the shell was down stays silent.
  function onTick() {
    now = Date.now()
    if (!ticking || st.endsAt <= 0 || remaining > 0) return
    var fresh = now - st.endsAt < 60000
    if (phase !== "focus" || config.overtime) {
      if (!st.alerted) {
        st.alerted = true
        if (fresh) runEffects(false, endMessage(true))
      }
      if (-remaining >= Model.MAX_OVERTIME_SEC) complete("completed", st.endsAt + Model.MAX_OVERTIME_SEC * 1000)
      return
    }
    complete("completed", st.endsAt, fresh ? endMessage(false) : null)
  }

  // ---- side effects
  // One script, so DND is off before the end-of-focus notification lands.
  function runEffects(releaseDnd, message) {
    if (!releaseDnd && !message) return
    Quickshell.execDetached(["bash", "-c",
      "[ -n \"$1\" ] && omarchy-shell -q notifications setDnd off >/dev/null; "
      + "[ -n \"$2\" ] && notify-send -a Omodoro \"$2\" \"$3\"; "
      + "[ -n \"$4\" ] && exec pw-play \"$4\"; true",
      "omodoro", releaseDnd ? "1" : "", message ? message.summary : "", message ? message.body : "",
      message && config.sound ? config.soundFile : ""])
  }

  // Only turns DND off again if this plugin turned it on.
  function claimDnd() {
    if (dndProc.running) return
    dndProc.command = ["bash", "-c",
      "[ \"$(omarchy-shell notifications isDnd 2>/dev/null)\" = off ] && omarchy-shell -q notifications setDnd on >/dev/null && echo claimed"]
    dndProc.running = true
  }

  Process {
    id: dndProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.trim() !== "claimed") return
        // Focus may have ended while the claim was in flight.
        if (root.phase === "focus") st.dndOwned = true
        else root.runEffects(true, null)
      }
    }
  }

  // ---- machinery
  property string host: hostFile.text().trim() || "localhost"

  FileView {
    id: hostFile
    path: "/etc/hostname"
    blockLoading: true
    printErrors: false
  }

  HistoryStore {
    id: history
    dir: root.dataDir
    host: root.host
    onMoved: function(newDir, ok) {
      if (ok && root.pendingDataDir !== "") root.updateSettings({ dataDir: root.pendingDataDir })
      root.pendingDataDir = ""
    }
  }

  readonly property string historyError: history.error
  readonly property string lastExport: history.lastExport

  // Plain properties, read once at startup and written whenever any of them
  // changes. JsonAdapter's async write-back could revert fresh assignments.
  QtObject {
    id: st
    property string phase: "idle"
    property bool paused: false
    property string upNext: "focus"
    property string label: ""
    property int cycleCount: 0
    property int plannedSec: 0
    property real startedAt: 0
    property real endsAt: 0
    property int pausedRemaining: 0
    property bool alerted: false
    property bool dndOwned: false
  }

  readonly property var stateKeys: ["phase", "paused", "upNext", "label", "cycleCount", "plannedSec",
    "startedAt", "endsAt", "pausedRemaining", "alerted", "dndOwned"]

  FileView {
    id: stateFile
    path: root.stateDir + "/timer.json"
    blockLoading: true
    atomicWrites: true
    printErrors: false
  }

  function loadState() {
    var saved = {}
    try { saved = JSON.parse(stateFile.text() || "{}") } catch (e) { saved = {} }
    stateKeys.filter(k => saved[k] !== undefined && saved[k] !== null).forEach(k => { st[k] = saved[k] })
  }

  function persist() {
    if (!active) return
    var out = {}
    stateKeys.forEach(k => { out[k] = st[k] })
    stateFile.setText(JSON.stringify(out, null, 2) + "\n")
  }

  function commit() { Qt.callLater(persist) }

  Timer {
    interval: 1000
    running: root.active && root.ticking
    repeat: true
    triggeredOnStart: true
    onTriggered: root.onTick()
  }

  Timer {
    id: breathTimer
    interval: root.breathMs
    onTriggered: root.finishBreath()
  }

  // Keeps "today" honest across midnight while nothing is running.
  Timer {
    interval: 60000
    running: root.active && !root.ticking
    repeat: true
    onTriggered: root.now = Date.now()
  }

  // ---- single ownership (see ServiceGuard.js)
  property bool superseded: false
  property bool claimed: false
  readonly property bool active: claimed && !superseded

  Component.onCompleted: {
    loadState()
    stateKeys.forEach(k => st[k + "Changed"].connect(root.commit))
    Guard.claim(root)
    claimed = true
    Quickshell.execDetached(["mkdir", "-p", root.stateDir])
  }
  Component.onDestruction: Guard.release(root)

  // A superseded instance is destroyed on a later event-loop turn, and a
  // handler registered while the old one still holds the target is never
  // used. Registering a moment after claiming lets the old one go first.
  property bool ipcReady: false

  Timer {
    interval: 500
    running: root.active && !root.ipcReady
    onTriggered: root.ipcReady = true
  }

  Loader {
    active: root.active && root.ipcReady
    sourceComponent: IpcHandler {
      target: "md.omodoro"

      function start(): string { return root.start() ? "ok" : "noop" }
      function pause(): string { return root.pause() ? "ok" : "noop" }
      function resume(): string { return root.resume() ? "ok" : "noop" }
      function toggle(): string { return root.toggle() ? "ok" : "noop" }
      function skip(): string { return root.skip() ? "ok" : "noop" }
      function finish(): string { return root.finish() ? "ok" : "noop" }
      function abandon(): string { return root.abandon() ? "ok" : "noop" }
      function resetCycle(): void { root.resetCycle() }
      function setLabel(text: string): void { root.setLabel(text) }
      function status(): string { return root.tooltip }
      function version(): string { return root.manifest && root.manifest.version ? root.manifest.version : "" }
      function exportHistory(): string { return root.exportHistory() ? "ok" : "not ready" }
      function stats(): string { return root.shell && root.shell.summon(root.pluginId, "{\"tab\":\"stats\"}") ? "ok" : "unknown" }
      function settings(): string { return root.shell && root.shell.summon(root.pluginId, "{\"tab\":\"settings\"}") ? "ok" : "unknown" }
    }
  }
}
