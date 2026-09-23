.pragma library

// Pure timer policy and formatting. No Qt objects here.

// Must match manifest.json. Also the IPC target.
var PLUGIN_ID = "io.github.0xapotheosis.omato"

var DEFAULTS = {
  focusMinutes: 25,
  shortBreakMinutes: 5,
  longBreakMinutes: 15,
  longBreakEvery: 4,
  dailyGoal: 8,
  strictMode: false,
  overtime: false,
  breathe: false,
  breaths: 1,
  dnd: true,
  sound: true,
  soundFile: "/usr/share/sounds/freedesktop/stereo/complete.oga",
  dataDir: "~/.local/share/omato",
  barMode: "countdown+goal"
}

// Forgotten overtime or extra rest stops counting after this long.
var MAX_OVERTIME_SEC = 3600

// One guided breath before focus, in milliseconds.
var BREATH = { inhale: 4000, hold: 2000, exhale: 4000 }
var BREATH_MS = BREATH.inhale + BREATH.hold + BREATH.exhale

var G = {
  idle: String.fromCodePoint(0xF051B),     // md-timer_outline
  focus: String.fromCodePoint(0xF051F),    // md-timer_sand
  paused: String.fromCodePoint(0xF19A0),   // md-timer_sand_paused
  overtime: String.fromCodePoint(0xF1ACD), // md-timer_alert_outline
  short: String.fromCodePoint(0xF0176),    // md-coffee
  long: String.fromCodePoint(0xF04B2),     // md-sleep
  play: String.fromCodePoint(0xF040A),
  pause: String.fromCodePoint(0xF03E4),
  skip: String.fromCodePoint(0xF04AD),
  stop: String.fromCodePoint(0xF04DB),
  finish: String.fromCodePoint(0xF05E0),   // md-check_circle
  cancel: String.fromCodePoint(0xF073A),
  chart: String.fromCodePoint(0xF0128),
  cog: String.fromCodePoint(0xF0493),
  fire: String.fromCodePoint(0xF0238),
  tag: String.fromCodePoint(0xF04F9),
  dotOn: String.fromCodePoint(0xF0765),    // md-circle
  dotOff: String.fromCodePoint(0xF0766)    // md-circle_outline
}

var NAMES = { idle: "Ready", focus: "Focus", short: "Short break", long: "Long break" }

var toInt = (v, fallback, min, max) => {
  var n = parseInt(v, 10)
  return isNaN(n) ? fallback : Math.max(min, Math.min(max, n))
}

var toBool = (v, fallback) => v === undefined || v === null ? fallback : v === true || v === "true"

var toStr = (v, fallback) => v === undefined || v === null || String(v).trim() === "" ? fallback : String(v)

// The widget's inline shell.json entry, wherever it sits in the layout.
function findEntry(barConfig, id) {
  var layout = barConfig && barConfig.layout ? barConfig.layout : {}
  var found = ["left", "center", "right"]
    .map(s => Array.isArray(layout[s]) ? layout[s] : [])
    .reduce((all, section) => all.concat(section), [])
    .find(e => e && e.id === id)
  return found || { id: id }
}

function readSettings(raw) {
  var r = raw || {}
  var d = DEFAULTS
  return {
    focusMinutes: toInt(r.focusMinutes, d.focusMinutes, 1, 180),
    shortBreakMinutes: toInt(r.shortBreakMinutes, d.shortBreakMinutes, 1, 60),
    longBreakMinutes: toInt(r.longBreakMinutes, d.longBreakMinutes, 1, 120),
    longBreakEvery: toInt(r.longBreakEvery, d.longBreakEvery, 2, 12),
    dailyGoal: toInt(r.dailyGoal, d.dailyGoal, 1, 32),
    strictMode: toBool(r.strictMode, d.strictMode),
    overtime: toBool(r.overtime, d.overtime),
    breathe: toBool(r.breathe, d.breathe),
    breaths: toInt(r.breaths, d.breaths, 1, 5),
    dnd: toBool(r.dnd, d.dnd),
    sound: toBool(r.sound, d.sound),
    soundFile: toStr(r.soundFile, d.soundFile),
    dataDir: toStr(r.dataDir, d.dataDir),
    barMode: r.barMode === "countdown" ? "countdown" : "countdown+goal"
  }
}

function expandHome(path, home) {
  var p = String(path || "").replace(/\/+$/, "")
  if (p === "~") return home
  return p.indexOf("~/") === 0 ? home + p.slice(1) : p
}

function durationSec(phase, cfg) {
  if (phase === "short") return cfg.shortBreakMinutes * 60
  if (phase === "long") return cfg.longBreakMinutes * 60
  return cfg.focusMinutes * 60
}

// What follows `phase`, given how many focus sessions the cycle has
// completed after it ended.
function nextPhase(phase, cycleCount, cfg) {
  if (phase !== "focus") return "focus"
  return cycleCount > 0 && cycleCount % cfg.longBreakEvery === 0 ? "long" : "short"
}

// Seconds left; negative in focus overtime or extra rest.
function remainingSec(paused, pausedRemaining, endsAt, nowMs) {
  return paused ? pausedRemaining : Math.ceil((endsAt - nowMs) / 1000)
}

var pad = n => (n < 10 ? "0" : "") + n

function fmtClock(sec) {
  var over = sec < 0
  var s = Math.abs(Math.round(sec))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var body = (h > 0 ? h + ":" + pad(m) : String(m)) + ":" + pad(s % 60)
  return (over ? "+" : "") + body
}

function fmtDuration(sec) {
  var m = Math.round(Math.max(0, sec) / 60)
  if (m < 60) return m + "m"
  var h = Math.floor(m / 60)
  return h + "h" + (m % 60 ? " " + pad(m % 60) + "m" : "")
}

function glyph(phase, paused, overtime) {
  if (phase === "idle") return G.idle
  if (paused) return G.paused
  if (phase === "focus") return overtime ? G.overtime : G.focus
  return G[phase]
}

function barLabel(s) {
  var goal = s.mode === "countdown+goal" ? "  " + s.today + "/" + s.goal : ""
  if (s.phase === "idle") return G.idle + goal
  return glyph(s.phase, s.paused, s.remaining < 0) + " " + fmtClock(s.remaining) + goal
}

var overLabel = phase => phase === "focus" ? " overtime" : " extra rest"

function tooltip(s) {
  var parts = []
  if (s.breathing) parts.push("Breathing before focus")
  else if (s.phase === "idle") parts.push("Up next: " + NAMES[s.upNext] + " " + fmtClock(s.upNextSec))
  else parts.push(NAMES[s.phase] + (s.paused ? " (paused)" : "") + " · " + fmtClock(s.remaining) + (s.remaining < 0 ? overLabel(s.phase) : " left"))
  if (s.label) parts.push(s.label)
  parts.push(s.today + " of " + s.goal + " today")
  if (s.streak > 0) parts.push(s.streak + "-day streak")
  return parts.join(" · ")
}

// Random enough to dedupe records across machines.
function uuid() {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
    var r = Math.random() * 16 | 0
    return (c === "x" ? r : (r & 0x3) | 0x8).toString(16)
  })
}
