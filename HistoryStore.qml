import QtQuick
import Qt.labs.folderlistmodel
import Quickshell.Io
import "Stats.js" as Stats

// Session history, one append-only JSONL file per machine:
//   <dir>/sessions-<host>.jsonl
// Each machine writes only its own file and reads every machine's, so a
// synced folder (Dropbox) never sees two writers on one file and never
// produces conflicted copies. Records are deduped by id on merge.
Item {
  id: store

  property string dir: ""
  property string host: ""

  readonly property string ownName: "sessions-" + host + ".jsonl"
  readonly property string ownPath: dir + "/" + ownName
  readonly property bool ready: dirReady && host !== ""

  // Synced history is untrusted. Nothing from that directory enters the shell
  // through FileView: a read stops at maxFileBytes + 1 and is discarded unless
  // the whole file fits. Retained records are a fixed set of short fields.
  readonly property int maxFileBytes: 8 * 1024 * 1024
  readonly property int maxRecords: 20000
  readonly property int maxFiles: 32
  readonly property int maxLineLength: 1024

  property bool dirReady: false
  property var files: ({})
  property var sizes: ({})
  property var stamps: ({})
  property var queue: []
  property string loadingName: ""
  property int ioGen: 0
  property var sessions: []
  readonly property var index: Stats.index(sessions)
  property var pending: []
  property string lastExport: ""
  property string error: ""

  signal moved(string newDir, bool ok)

  function clip(value, max) {
    return typeof value === "string" && value.length > max ? value.slice(0, max) : (typeof value === "string" ? value : "")
  }

  function wholeNumber(value) {
    var n = Number(value)
    if (!isFinite(n) || n <= 0) return 0
    return Math.min(8640000, Math.round(n))
  }

  // Only the fields the timer writes. Anything else in a synced line is dropped.
  function normalize(raw) {
    if (!raw || typeof raw.id !== "string" || typeof raw.start !== "string") return null
    if (raw.id.length > 80 || raw.start.length > 40) return null
    return {
      id: raw.id,
      host: clip(raw.host, 64),
      kind: clip(raw.kind, 16),
      label: clip(raw.label, 80),
      start: raw.start,
      end: clip(raw.end, 40),
      plannedSec: wholeNumber(raw.plannedSec),
      actualSec: wholeNumber(raw.actualSec),
      overtimeSec: wholeNumber(raw.overtimeSec),
      outcome: clip(raw.outcome, 16)
    }
  }

  function parseLines(text) {
    var lines = String(text || "").split("\n")
    var out = []
    for (var i = lines.length - 1; i >= 0 && out.length < maxRecords; i--) {
      var line = lines[i].trim()
      if (line === "" || line.length > maxLineLength) continue
      try {
        var record = normalize(JSON.parse(line))
        if (record) out.push(record)
      } catch (e) {}
    }
    out.reverse()
    return out
  }

  function noteSize(name, size) {
    if (sizes[name] === size) return
    var next = Object.assign({}, sizes)
    next[name] = size
    sizes = next
    if (size > maxFileBytes) {
      drop(name)
      error = name + " is over the history size limit and was not loaded"
    }
  }

  function settleFolder() {
    if (folder.status !== FolderListModel.Ready) return
    var entries = []
    var found = false
    for (var i = 0; i < folder.count; i++) {
      var name = folder.get(i, "fileName")
      var entry = {
        name: name,
        path: folder.get(i, "filePath"),
        size: folder.get(i, "fileSize"),
        modified: modifiedMs(folder.get(i, "fileModified"))
      }
      if (name === ownName) found = true
      entries.push(entry)
    }
    entries.sort(function(a, b) { return b.modified - a.modified })
    var chosen = {}
    var opened = 0
    for (var j = 0; j < entries.length && opened < maxFiles; j++) {
      chosen[entries[j].name] = entries[j]
      opened++
    }
    if (found && !(ownName in chosen)) {
      for (var k = 0; k < entries.length; k++) {
        if (entries[k].name === ownName) chosen[ownName] = entries[k]
      }
    }
    if (!found) noteSize(ownName, 0)
    var kept = Object.assign({}, files)
    var removed = false
    Object.keys(kept).forEach(function(fileName) {
      if (!(fileName in chosen)) {
        delete kept[fileName]
        removed = true
      }
    })
    if (removed) {
      files = kept
      mergeDebounce.restart()
    }
    Object.keys(chosen).forEach(function(fileName) {
      var entry = chosen[fileName]
      noteSize(fileName, entry.size)
      var stamp = entry.size + ":" + entry.modified
      if (stamps[fileName] === stamp || loadingName === fileName) return
      var nextStamps = Object.assign({}, stamps)
      nextStamps[fileName] = stamp
      stamps = nextStamps
      enqueue(fileName, entry.path, entry.size)
    })
    if (ready) flushPending()
  }

  function modifiedMs(value) {
    if (!value) return 0
    var ms = value.getTime ? value.getTime() : new Date(value).getTime()
    return isNaN(ms) ? 0 : ms
  }

  function enqueue(name, path, size) {
    if (size > maxFileBytes || loadingName === name) return
    for (var i = 0; i < queue.length; i++) if (queue[i].name === name) return
    queue = queue.concat([{ name: name, path: path }])
    pump()
  }

  // The queued size is only a hint. The process below is the bound: it copies
  // at most maxFileBytes + 1 and exits without writing stdout when the file
  // does not fit, so a replace after the directory listing never reaches us.
  readonly property string boundedRead: "set -eu\n"
    + "file=$1; limit=$2; tmp=$(mktemp); trap 'rm -f -- \"$tmp\"' EXIT\n"
    + "[ -f \"$file\" ] || exit 0\n"
    + "head -c \"$((limit + 1))\" -- \"$file\" > \"$tmp\"\n"
    + "size=$(stat -c %s -- \"$tmp\")\n"
    + "[ \"$size\" -le \"$limit\" ] || exit 2\n"
    + "cat -- \"$tmp\"\n"

  readonly property string boundedAppend: "set -eu\n"
    + "file=$1; limit=$2; line=$3; dir=$(dirname -- \"$file\"); tmp=$(mktemp \"$dir/.omato-XXXXXX\")\n"
    + "trap 'rm -f -- \"$tmp\"' EXIT\n"
    + "if [ -f \"$file\" ]; then head -c \"$((limit + 1))\" -- \"$file\" > \"$tmp\"; fi\n"
    + "size=$(stat -c %s -- \"$tmp\"); [ \"$size\" -le \"$limit\" ] || exit 2\n"
    + "if [ \"$size\" -gt 0 ]; then last=$(tail -c 1 -- \"$tmp\" | od -An -tu1 | tr -d \" \"); [ \"$last\" = 10 ] || printf \"\\n\" >> \"$tmp\"; fi\n"
    + "printf \"%s\\n\" \"$line\" >> \"$tmp\"\n"
    + "size=$(stat -c %s -- \"$tmp\"); [ \"$size\" -le \"$limit\" ] || exit 2\n"
    + "cat -- \"$tmp\"; mv -f -- \"$tmp\" \"$file\"; trap - EXIT\n"

  function pump() {
    if (loadingName !== "" || appendProc.running || queue.length === 0) return
    var next = queue[0]
    queue = queue.slice(1)
    loadingName = next.name
    readProc.fileName = next.name
    readProc.generation = ioGen
    readProc.body = ""
    readProc.command = ["bash", "-c", boundedRead, "omato-read", next.path, String(maxFileBytes)]
    readProc.running = true
  }

  function afterIo() {
    if (pending.length > 0) flushPending()
    else pump()
  }

  function ingest(name, text) {
    if (String(text || "").length > maxFileBytes) {
      drop(name)
      error = name + " is over the history size limit and was not loaded"
      return
    }
    var next = Object.assign({}, files)
    next[name] = parseLines(text)
    var tagged = []
    Object.keys(next).forEach(function(fileName) {
      next[fileName].forEach(function(record) { tagged.push({ fileName: fileName, record: record }) })
    })
    tagged.sort(function(a, b) {
      return a.record.start < b.record.start ? -1 : a.record.start > b.record.start ? 1 : 0
    })
    if (tagged.length > maxRecords) tagged = tagged.slice(tagged.length - maxRecords)
    var kept = {}
    tagged.forEach(function(item) {
      var list = kept[item.fileName] || (kept[item.fileName] = [])
      list.push(item.record)
    })
    files = kept
    mergeDebounce.restart()
  }

  function drop(name) {
    if (!(name in files)) return
    var next = Object.assign({}, files)
    delete next[name]
    files = next
    mergeDebounce.restart()
  }

  function merge() {
    var byId = {}
    Object.keys(files).forEach(name => files[name].forEach(r => { byId[r.id] = r }))
    var merged = Object.keys(byId).map(id => byId[id]).sort((a, b) => a.start < b.start ? -1 : a.start > b.start ? 1 : 0)
    sessions = merged.length > maxRecords ? merged.slice(merged.length - maxRecords) : merged
  }

  function append(record) {
    if (!ready || !(ownName in sizes) || loadingName !== "" || appendProc.running) {
      pending = pending.concat([record])
      return
    }
    var clean = normalize(record)
    if (!clean) return
    var line = JSON.stringify(clean)
    if (line.length + 1 > maxFileBytes) {
      error = ownName + " is over the history size limit"
      return
    }
    appendProc.generation = ioGen
    appendProc.body = ""
    appendProc.command = ["bash", "-c", boundedAppend, "omato-append", ownPath, String(maxFileBytes), line]
    appendProc.running = true
  }

  function flushPending() {
    if (!(ownName in sizes) || sizes[ownName] > maxFileBytes || appendProc.running || loadingName !== "") return
    if (pending.length === 0) return
    var record = pending[0]
    pending = pending.slice(1)
    append(record)
  }

  function exportAll() {
    if (!ready) return false
    error = ""
    exportProc.command = ["mkdir", "-p", dir + "/exports"]
    exportProc.running = true
    return true
  }

  function writeExports() {
    var stamp = Qt.formatDateTime(new Date(), "yyyy-MM-dd-HHmmss")
    var base = dir + "/exports/omato-" + stamp
    exportJson.path = base + ".json"
    exportJson.setText(JSON.stringify({ exportedAt: new Date().toISOString(), sessions: sessions }, null, 2) + "\n")
    exportCsv.path = base + ".csv"
    exportCsv.setText(Stats.toCsv(sessions))
    lastExport = base + ".{json,csv}"
  }

  // Moves every machine's file; where the target already has one of the
  // same name, the two are concatenated (the merge dedupes by id).
  function moveTo(newDir) {
    if (!newDir || newDir === dir) return false
    moveProc.target = newDir
    moveProc.command = ["bash", "-c",
      "set -eu; limit=$3; mkdir -p -- \"$2\"; for f in \"$1\"/sessions-*.jsonl; do [ -e \"$f\" ] || continue; "
      + "tmp=$(mktemp); head -c \"$((limit + 1))\" -- \"$f\" > \"$tmp\"; src=$(stat -c %s -- \"$tmp\"); "
      + "if [ \"$src\" -gt \"$limit\" ]; then rm -f -- \"$tmp\"; continue; fi; "
      + "t=\"$2/${f##*/}\"; if [ -e \"$t\" ]; then dest=$(stat -c %s -- \"$t\"); "
      + "if [ \"$((src + dest))\" -gt \"$limit\" ]; then rm -f -- \"$tmp\"; exit 3; fi; "
      + "cat -- \"$tmp\" >> \"$t\"; rm -f -- \"$tmp\" \"$f\"; else mv -- \"$tmp\" \"$t\"; rm -f -- \"$f\"; fi; done",
      "omato-move", dir, newDir, String(maxFileBytes)]
    moveProc.running = true
    return true
  }

  onDirChanged: {
    dirReady = false
    files = ({})
    sizes = ({})
    stamps = ({})
    queue = []
    loadingName = ""
    ioGen = ioGen + 1
    sessions = []
    if (dir === "") return
    mkdirProc.command = ["mkdir", "-p", dir]
    mkdirProc.running = true
  }

  onReadyChanged: if (ready) flushPending()

  Timer {
    id: mergeDebounce
    interval: 50
    onTriggered: store.merge()
  }

  Process {
    id: mkdirProc
    onExited: function(code) {
      store.dirReady = code === 0
      store.error = code === 0 ? "" : "Cannot create " + store.dir
    }
  }

  Process {
    id: exportProc
    onExited: function(code) {
      if (code === 0) store.writeExports()
      else store.error = "Cannot create " + store.dir + "/exports"
    }
  }

  Process {
    id: moveProc
    property string target: ""
    onExited: function(code) { store.moved(target, code === 0) }
  }

  Process {
    id: readProc
    property string fileName: ""
    property int generation: 0
    property string body: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: readProc.body = text
    }
    onExited: function(code) {
      if (readProc.generation !== store.ioGen) return
      var name = readProc.fileName
      var body = readProc.body
      readProc.body = ""
      readProc.fileName = ""
      store.loadingName = ""
      if (code === 2) store.noteSize(name, store.maxFileBytes + 1)
      else if (code === 0 && name !== "") {
        store.noteSize(name, body.length)
        store.ingest(name, body)
      }
      store.afterIo()
    }
  }

  Process {
    id: appendProc
    property int generation: 0
    property string body: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: appendProc.body = text
    }
    onExited: function(code) {
      if (appendProc.generation !== store.ioGen) return
      var body = appendProc.body
      appendProc.body = ""
      if (code === 2) store.noteSize(store.ownName, store.maxFileBytes + 1)
      else if (code === 0) {
        store.noteSize(store.ownName, body.length)
        store.ingest(store.ownName, body)
      }
      store.afterIo()
    }
  }

  FolderListModel {
    id: folder
    folder: store.dirReady ? "file://" + store.dir : ""
    nameFilters: ["sessions-*.jsonl"]
    showDirs: false
    showDotAndDotDot: false
    onStatusChanged: store.settleFolder()
    onCountChanged: store.settleFolder()
  }

  Timer {
    interval: 2000
    running: store.dirReady
    repeat: true
    onTriggered: store.settleFolder()
  }

  FileView {
    id: exportJson
    preload: false
    blockAllReads: true
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: exportCsv
    preload: false
    blockAllReads: true
    atomicWrites: true
    printErrors: false
  }
}
