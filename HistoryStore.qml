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

  // Synced history is untrusted. Refuse a file before FileView reads it, and
  // keep only the newest records so a large file cannot stay resident.
  readonly property int maxFileBytes: 8 * 1024 * 1024
  readonly property int maxRecords: 20000
  readonly property bool ownLoadable: ownName in sizes && sizes[ownName] <= maxFileBytes

  property bool dirReady: false
  property var files: ({})
  property var sizes: ({})
  property var sessions: []
  readonly property var index: Stats.index(sessions)
  property var pending: []
  property string lastExport: ""
  property string error: ""

  signal moved(string newDir, bool ok)

  function parseLines(text) {
    var lines = String(text || "").split("\n")
    var out = []
    for (var i = lines.length - 1; i >= 0 && out.length < maxRecords; i--) {
      var line = lines[i].trim()
      if (line === "") continue
      try {
        var record = JSON.parse(line)
        if (record && typeof record.id === "string" && typeof record.start === "string")
          out.push(record)
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
    var found = false
    for (var i = 0; i < folder.count; i++) {
      var name = folder.get(i, "fileName")
      noteSize(name, folder.get(i, "fileSize"))
      if (name === ownName) found = true
    }
    if (!found) noteSize(ownName, 0)
    if (ready) flushPending()
  }

  function ingest(name, text) {
    if (name in sizes && sizes[name] > maxFileBytes) {
      drop(name)
      return
    }
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
    var merged = Object.keys(byId).map(id => byId[id]).sort((a, b) => a.start < b.start ? -1 : a.start > b.start ? 1 : 0)
    sessions = merged.length > maxRecords ? merged.slice(merged.length - maxRecords) : merged
  }

  function append(record) {
    if (!ready || !(ownName in sizes)) {
      pending = pending.concat([record])
      return
    }
    var line = JSON.stringify(record) + "\n"
    if (sizes[ownName] + line.length > maxFileBytes) {
      error = ownName + " is over the history size limit"
      return
    }
    var text = sizes[ownName] > 0 ? (ownFile.text() || "") : ""
    if (text !== "" && text.slice(-1) !== "\n") text += "\n"
    text += line
    ownFile.setText(text)
    noteSize(ownName, text.length)
    // FileView does not re-emit onLoaded for its own write.
    ingest(ownName, text)
  }

  function flushPending() {
    if (!(ownName in sizes) || sizes[ownName] > maxFileBytes) return
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
      "set -e; mkdir -p \"$2\"; for f in \"$1\"/sessions-*.jsonl; do [ -e \"$f\" ] || continue; "
      + "t=\"$2/${f##*/}\"; if [ -e \"$t\" ]; then cat \"$f\" >> \"$t\"; rm \"$f\"; else mv \"$f\" \"$t\"; fi; done",
      "omato-move", dir, newDir]
    moveProc.running = true
    return true
  }

  onDirChanged: {
    dirReady = false
    files = ({})
    sizes = ({})
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
    path: store.ready && store.ownLoadable ? store.ownPath : ""
    blockLoading: true
    blockAllReads: !store.ownLoadable
    atomicWrites: true
    watchChanges: false
    printErrors: false
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

  // Dropbox replaces files by rename, which a file watch can miss; the
  // folder model's modification time catches that case. fileSize is known
  // before path is set, so an oversized file is never read.
  Instantiator {
    model: folder
    delegate: FileView {
      required property string fileName
      required property string filePath
      required property int fileSize
      required property var fileModified

      readonly property bool loadable: fileSize <= store.maxFileBytes

      path: loadable ? filePath : ""
      Component.onCompleted: store.noteSize(fileName, fileSize)
      onFileSizeChanged: store.noteSize(fileName, fileSize)
      blockLoading: true
      blockAllReads: !loadable
      watchChanges: false
      printErrors: false
      onLoadableChanged: if (!loadable) store.drop(fileName)
      onFileModifiedChanged: sizeProbe.running = true
      onLoaded: if (loadable) store.ingest(fileName, text())
      Component.onDestruction: store.drop(fileName)

      // Stat before any reload. A synced replace can land before fileSize
      // updates, and watchChanges would read that file immediately.
      Process {
        id: sizeProbe
        command: ["stat", "-c", "%s", filePath]
        stdout: StdioCollector {
          waitForEnd: true
          onStreamFinished: {
            var size = parseInt(text.trim(), 10)
            if (isNaN(size)) return
            store.noteSize(fileName, size)
            if (size > store.maxFileBytes) return
            reload()
            if (fileName === store.ownName && store.ownLoadable) ownFile.reload()
          }
        }
      }
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
