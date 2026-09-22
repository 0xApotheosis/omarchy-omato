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

  property bool dirReady: false
  property var files: ({})
  property var sessions: []
  readonly property var index: Stats.index(sessions)
  property var pending: []
  property string lastExport: ""
  property string error: ""

  signal moved(string newDir, bool ok)

  function parseLines(text) {
    return String(text || "").split("\n")
      .filter(line => line.trim() !== "")
      .map(line => { try { return JSON.parse(line) } catch (e) { return null } })
      .filter(r => r && typeof r.id === "string" && typeof r.start === "string")
  }

  function ingest(name, text) {
    var next = Object.assign({}, files)
    next[name] = parseLines(text)
    files = next
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
    sessions = Object.keys(byId).map(id => byId[id]).sort((a, b) => a.start < b.start ? -1 : a.start > b.start ? 1 : 0)
  }

  function append(record) {
    if (!ready) {
      pending = pending.concat([record])
      return
    }
    var text = ownFile.text() || ""
    if (text !== "" && text.slice(-1) !== "\n") text += "\n"
    text += JSON.stringify(record) + "\n"
    ownFile.setText(text)
    // FileView does not re-emit onLoaded for its own write.
    ingest(ownName, text)
  }

  function flushPending() {
    var queued = pending
    pending = []
    queued.forEach(append)
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
    var base = dir + "/exports/omodoro-" + stamp
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
      "set -e; mkdir -p \"$2\"; for f in \"$1\"/sessions-*.jsonl; do [ -e \"$f\" ] || continue; "
      + "t=\"$2/${f##*/}\"; if [ -e \"$t\" ]; then cat \"$f\" >> \"$t\"; rm \"$f\"; else mv \"$f\" \"$t\"; fi; done",
      "omodoro-move", dir, newDir]
    moveProc.running = true
    return true
  }

  onDirChanged: {
    dirReady = false
    files = ({})
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

  FileView {
    id: ownFile
    path: store.ready ? store.ownPath : ""
    blockLoading: true
    atomicWrites: true
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
  }

  FolderListModel {
    id: folder
    folder: store.dirReady ? "file://" + store.dir : ""
    nameFilters: ["sessions-*.jsonl"]
    showDirs: false
    showDotAndDotDot: false
  }

  // Dropbox replaces files by rename, which a file watch can miss; the
  // folder model's modification time catches that case.
  Instantiator {
    model: folder
    delegate: FileView {
      required property string fileName
      required property string filePath
      required property var fileModified

      path: filePath
      watchChanges: true
      printErrors: false
      onFileChanged: reload()
      onFileModifiedChanged: reload()
      onLoaded: store.ingest(fileName, text())
      Component.onDestruction: store.drop(fileName)
    }
  }

  FileView {
    id: exportJson
    preload: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: exportCsv
    preload: false
    atomicWrites: true
    printErrors: false
  }
}
