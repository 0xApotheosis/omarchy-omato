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

  // Synced history is untrusted. One reader opens one file at a time, and
  // files keeps at most maxRecords across every machine, not per file.
  readonly property int maxFileBytes: 8 * 1024 * 1024
  readonly property int maxRecords: 20000
  readonly property int maxFiles: 32
  readonly property bool ownLoadable: ownName in sizes && sizes[ownName] <= maxFileBytes

  property bool dirReady: false
  property var files: ({})
  property var sizes: ({})
  property var stamps: ({})
  property var queue: []
  property string loadingName: ""
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
    queue = queue.concat([{ name: name, path: path, size: size }])
    pump()
  }

  function pump() {
    if (loadingName !== "" || queue.length === 0) return
    var next = queue[0]
    queue = queue.slice(1)
    if (next.size > maxFileBytes) {
      drop(next.name)
      pump()
      return
    }
    loadingName = next.name
    if (reader.path === next.path) reader.reload()
    else reader.path = next.path
  }

  function finishRead(name, text) {
    loadingName = ""
    reader.path = ""
    if (name !== "") ingest(name, text)
    pump()
  }

  function ingest(name, text) {
    if (name in sizes && sizes[name] > maxFileBytes) {
      drop(name)
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
    stamps = ({})
    queue = []
    loadingName = ""
    reader.path = ""
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

  // One reader for every machine's file. The folder listing is metadata;
  // file contents are opened only for the newest maxFiles, and only one
  // path is set at a time. A replace shows up as a new size or mtime.
  FileView {
    id: reader
    blockLoading: true
    blockAllReads: path === ""
    watchChanges: false
    printErrors: false
    onLoaded: {
      if (store.loadingName === "" || path === "") return
      var name = store.loadingName
      var body = text()
      store.finishRead(name, body)
      if (name === store.ownName && store.ownLoadable) ownFile.reload()
    }
    onLoadFailed: store.finishRead("", "")
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
