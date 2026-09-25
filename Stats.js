.pragma library

// Pure aggregations over session records. No Qt objects here.
//
// A pomodoro is a completed focus session. Focus time counts every focus
// session, including abandoned and skipped ones, by its actual length.

var DAY_MS = 86400000
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

var pad = n => (n < 10 ? "0" : "") + n

var dayKey = d => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate())

var startOfDay = ms => {
  var d = new Date(ms)
  d.setHours(0, 0, 0, 0)
  return d
}

// Local calendar arithmetic, so DST days are neither skipped nor doubled.
var addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n)

var isPomodoro = s => s.kind === "focus" && s.outcome === "completed"

var emptyDay = () => ({ pomodoros: 0, focusSec: 0, extraRestSec: 0 })

var seconds = v => Math.max(0, Number(v) || 0)

// One pass over the records; every view reads from this. Breaks only
// contribute the rest they ran over.
function index(sessions) {
  var days = {}
  var hours = Array.from({ length: 24 }, () => 0)
  var labels = {}
  var totals = emptyDay()
  sessions.forEach(s => {
    var start = new Date(s.start)
    if (isNaN(start.getTime())) return
    var key = dayKey(start)
    var day = days[key] || (days[key] = emptyDay())
    if (s.kind !== "focus") {
      var extra = seconds(s.overtimeSec)
      day.extraRestSec += extra
      totals.extraRestSec += extra
      return
    }
    var label = s.label || "Unlabelled"
    var tag = labels[label] || (labels[label] = { label: label, pomodoros: 0, focusSec: 0 })
    var sec = seconds(s.actualSec)
    var done = isPomodoro(s) ? 1 : 0
    day.pomodoros += done
    day.focusSec += sec
    tag.pomodoros += done
    tag.focusSec += sec
    totals.pomodoros += done
    totals.focusSec += sec
    hours[start.getHours()] += sec
  })
  return { days: days, hours: hours, labels: labels, totals: totals }
}

var dayAt = (idx, d) => idx.days[dayKey(d)] || emptyDay()

function today(idx, nowMs) {
  return dayAt(idx, startOfDay(nowMs))
}

// Oldest first, ending today.
function perDay(idx, count, nowMs) {
  var end = startOfDay(nowMs)
  return Array.from({ length: count }, (_, i) => {
    var d = addDays(end, i - count + 1)
    var day = dayAt(idx, d)
    return {
      key: dayKey(d),
      label: count <= 7 ? WEEKDAYS[d.getDay()] : String(d.getDate()),
      title: WEEKDAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()],
      pomodoros: day.pomodoros,
      focusSec: day.focusSec,
      extraRestSec: day.extraRestSec
    }
  })
}

function sumDays(idx, count, nowMs) {
  return perDay(idx, count, nowMs).reduce((acc, d) => ({
    pomodoros: acc.pomodoros + d.pomodoros,
    focusSec: acc.focusSec + d.focusSec,
    extraRestSec: acc.extraRestSec + d.extraRestSec
  }), emptyDay())
}

// Consecutive days meeting the goal, ending today — or yesterday, while
// today's goal is still in reach.
function streak(idx, goal, nowMs) {
  var d = startOfDay(nowMs)
  if (dayAt(idx, d).pomodoros < goal) d = addDays(d, -1)
  var n = 0
  while (dayAt(idx, d).pomodoros >= goal) {
    n++
    d = addDays(d, -1)
  }
  return n
}

function bestStreak(idx, goal) {
  var keys = Object.keys(idx.days).filter(k => idx.days[k].pomodoros >= goal).sort()
  var best = 0
  var run = 0
  var prev = null
  keys.forEach(k => {
    var parts = k.split("-").map(Number)
    var d = new Date(parts[0], parts[1] - 1, parts[2])
    run = prev && dayKey(addDays(prev, 1)) === k ? run + 1 : 1
    best = Math.max(best, run)
    prev = d
  })
  return best
}

// 0..4, relative to the daily goal.
var level = (count, goal) => count <= 0 ? 0 : Math.min(4, Math.ceil(count / goal * 4))

// GitHub-style grid: 53 week columns of 7 days (Sunday first), ending with
// the current week. Month labels mark the first column of each month.
function yearHeatmap(idx, goal, nowMs) {
  var todayDate = startOfDay(nowMs)
  var first = addDays(todayDate, -(52 * 7 + todayDate.getDay()))
  return Array.from({ length: 53 }, (_, w) => {
    var days = Array.from({ length: 7 }, (_, i) => {
      var d = addDays(first, w * 7 + i)
      var day = dayAt(idx, d)
      return {
        key: dayKey(d),
        future: d > todayDate,
        pomodoros: day.pomodoros,
        level: level(day.pomodoros, goal),
        title: WEEKDAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
      }
    })
    var top = addDays(first, w * 7)
    return { month: top.getDate() <= 7 ? MONTHS[top.getMonth()] : "", days: days }
  })
}

// Focus time by the hour a session started.
function byHour(idx) {
  return idx.hours.map((sec, h) => ({
    label: h % 6 === 0 ? pad(h) : "",
    title: pad(h) + ":00",
    focusSec: sec
  }))
}

function byLabel(idx, limit) {
  return Object.keys(idx.labels)
    .map(k => idx.labels[k])
    .sort((a, b) => b.focusSec - a.focusSec)
    .slice(0, limit || 8)
}

// Spreadsheets execute a cell whose first character is = + - @, tab, or CR,
// including after whitespace they trim. History files are synced and can be
// edited, so prefix those cells and keep them as text.
var FORMULA = /^[\t\r ]*[=+\-@]|^[\t\r]/

var csvCell = v => {
  var s = v === undefined || v === null ? "" : String(v)
  if (FORMULA.test(s)) s = "'" + s
  return /[",\n\r]/.test(s) ? "\"" + s.replace(/"/g, "\"\"") + "\"" : s
}

var CSV_COLUMNS = ["id", "host", "kind", "label", "start", "end", "plannedSec", "actualSec", "overtimeSec", "outcome"]

function toCsv(sessions) {
  return [CSV_COLUMNS.join(",")]
    .concat(sessions.map(s => CSV_COLUMNS.map(c => csvCell(s[c])).join(",")))
    .join("\n") + "\n"
}
