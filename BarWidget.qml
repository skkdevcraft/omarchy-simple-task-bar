import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "io.github.librael-the-culprit.simple-task-bar"

  readonly property string stateDir: (Quickshell.env("HOME") || "") + "/.local/state/omarchy/taskbar"
  readonly property string pinnedPath: root.stateDir + "/pinned"

  LocalAppLibrary {
    id: appLibraryFallback
  }

  readonly property var appLibrary: root.bar && root.bar.shell && root.bar.shell.appLibrary ? root.bar.shell.appLibrary : appLibraryFallback

  readonly property color chroma: root.bar && root.bar.barForeground ? root.bar.barForeground : Color.foreground
  readonly property color hoverColor: Util.alpha(root.chroma, 0.12)
  readonly property color runningIndicatorColor: Util.alpha(root.chroma, 0.45)
  readonly property color activeIndicatorColor: Color.accent

  property var pinned: []
  property var items: []
  property var watched: ({})
  property var recentAddresses: []
  property var pidNames: ({})
  property var clientInfo: ({})
  property string pendingPid: ""

  function pidNameFor(pid) {
    pid = String(pid || "").trim()
    if (!pid) return ""
    var cached = root.pidNames[pid]
    if (cached) return cached
    if (root.pendingPid === pid || pidProc.running) return ""
    root.pendingPid = pid
    pidProc.command = ["bash", "-lc", "ps -o comm= -p " + pid + " 2>/dev/null"]
    pidProc.running = true
    return ""
  }

  property Process pidProc: Process {
    id: pidProc
    command: ["bash", "-lc", ""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var name = String(text || "").trim()
        var pid = root.pendingPid
        if (pid && name.length > 0) root.pidNames[pid] = name
        root.pendingPid = ""
        root.scheduleRefresh()
      }
    }
    onExited: {
      root.pendingPid = ""
    }
  }

  function refreshClientInfo() {
    if (clientsProc.running) return
    clientsProc.command = ["python3", "-c", "import subprocess,json; d=json.loads(subprocess.check_output(['hyprctl','-j','clients'], text=True)); print(json.dumps([{'address':w['address'],'pid':w['pid'],'class':w.get('class'),'initialClass':w.get('initialClass'),'initialTitle':w.get('initialTitle')} for w in d]))"]
    clientsProc.running = true
  }

  property Process clientsProc: Process {
    id: clientsProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyClientInfo(text)
    }
  }

  function applyClientInfo(text) {
    var arr = []
    try { arr = JSON.parse(String(text || "[]")) } catch (e) { arr = [] }
    var info = {}
    for (var i = 0; i < arr.length; i++) {
      var o = arr[i] || {}
      var addr = String(o["address"] || "")
      if (addr.indexOf("0x") === 0) addr = addr.slice(2)
      if (!addr) continue
      info[addr] = { pid: o["pid"], class: o["class"], initialClass: o["initialClass"], initialTitle: o["initialTitle"] }
    }
    var changed = JSON.stringify(info) !== JSON.stringify(root.clientInfo)
    root.clientInfo = info
    if (changed) {
      root.fingerprint = ""
      root.scheduleRefresh()
    }
  }

  property string fingerprint: ""
  property bool dirty: true

  property int iconSize: Math.round(Style.space(17))
  readonly property real buttonWidth: Math.round(Style.space(26))

  function normalizeDesktopId(id) {
    var value = String(id || "").trim()
    if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
    return value
  }

  function toplevelValues() {
    try { return Hyprland.toplevels.values || [] } catch (e) { return [] }
  }

  function unwrap(row) {
    while (row && typeof row === "object" && row.score !== undefined && row.entry && typeof row.entry === "object")
      row = row.entry
    return row
  }

  function appIdFrom(e) {
    var id = String(e && (e.id || e.desktopId) || "")
    if (root.appLibrary && typeof root.appLibrary.normalizeDesktopId === "function")
      return root.appLibrary.normalizeDesktopId(id)
    return root.normalizeDesktopId(id)
  }

  function entryForId(id) {
    id = String(id || "").trim().toLowerCase()
    if (!id || !root.appLibrary || typeof root.appLibrary.sortedEntries !== "function") return null
    var rows = root.appLibrary.sortedEntries("") || []
    for (var i = 0; i < rows.length; i++) {
      var e = root.unwrap(rows[i])
      if (!e) continue
      if (root.appIdFrom(e).toLowerCase() === id) return e
    }
    return null
  }

  function entryForLoose(key) {
    var want = String(key || "").toLowerCase()
    if (!want || !root.appLibrary || typeof root.appLibrary.sortedEntries !== "function") return null
    var rows = root.appLibrary.sortedEntries("") || []
    var best = null
    var bestScore = -1
    for (var i = 0; i < rows.length; i++) {
      var e = root.unwrap(rows[i])
      if (!e) continue
      var nid = root.appIdFrom(e).toLowerCase()
      if (!nid) continue
      var score = -1
      if (nid === want) score = 100
      else if (nid.indexOf(want) >= 0) score = 90
      else if (want.indexOf(nid) >= 0) score = 80
      if (score < 0 && want.length > 2) {
        var tokens = want.split(/[^a-z0-9._-]+/)
        for (var ti = 0; ti < tokens.length; ti++) {
          var tok = tokens[ti]
          if (tok.length < 3) continue
          if (nid === tok) score = 72
          else if (nid.indexOf(tok) >= 0) score = 60
          else if (tok.indexOf(nid) >= 0 && nid.length >= 3) score = 55
          if (score > bestScore) break
        }
      }
      if (score > bestScore) {
        bestScore = score
        best = e
      }
    }
    return best
  }

  function entryName(e) {
    if (root.appLibrary && typeof root.appLibrary.entryName === "function") return root.appLibrary.entryName(e)
    return String(e && (e.name || e.id) || "")
  }

  readonly property var iconAliases: {
    "org.omarchy.agent": "omarchy",
    "omarchy-agent": "omarchy",
    "org.omarchy.omarchy": "omarchy"
  }

  function iconFor(item) {
    if (!item) return ""
    var name = String(item.iconName || "")
    if (root.appLibrary && typeof root.appLibrary.iconSource === "function") {
      var src = root.appLibrary.iconSource(name)
      if (String(src || "").length > 0) return src
      var classIcon = String(item.classIcon || "")
      if (classIcon) {
        var alias = root.iconAliases[classIcon] || ""
        var src2 = root.appLibrary.iconSource(alias || classIcon)
        if (String(src2 || "").length > 0) return src2
      }
    }
    return Quickshell.iconPath("application-x-executable", true)
  }

  function windowKey(t) {
    var a = String(t && t.address || "")
    var ci = root.clientInfo[a]
    var o = t && t.lastIpcObject && typeof t.lastIpcObject === "object" ? t.lastIpcObject : null
    var cls = ""
    if (ci && String(ci.class || "").trim()) cls = String(ci.class).trim()
    if (!cls && ci && String(ci.initialClass || "").trim()) cls = String(ci.initialClass).trim()
    if (!cls && o && String(o["class"] || "").trim()) cls = String(o["class"]).trim()
    if (!cls && o && String(o["initialClass"] || "").trim()) cls = String(o["initialClass"]).trim()
    if (cls) return cls.toLowerCase()
    var pidTxt = ""
    if (ci && ci.pid != null) pidTxt = String(ci.pid)
    if (!pidTxt && o && o["pid"] != null) pidTxt = String(o["pid"])
    if (pidTxt) {
      var comm = root.pidNameFor(pidTxt)
      if (comm) return comm.toLowerCase()
    }
    var it = ""
    if (ci && String(ci.initialTitle || "").trim()) it = String(ci.initialTitle).trim()
    if (!it && o && String(o["initialTitle"] || "").trim()) it = String(o["initialTitle"]).trim()
    if (it) return it.toLowerCase()
    return String(t && t.title || "").trim().toLowerCase()
  }

  function isAliased(key) {
    var k = String(key || "").toLowerCase()
    if (!k) return false
    for (var a in root.iconAliases) if (String(a).toLowerCase() === k) return true
    if (k.indexOf("-agent") >= 0 || k.indexOf(".agent") >= 0) return true
    return false
  }

  function isExcludedWindow(t) {
    if (!t) return true
  
    var a = String(t.address || "")
    var ci = root.clientInfo[a]
    var o = t && t.lastIpcObject && typeof t.lastIpcObject === "object" ? t.lastIpcObject : null
    var values = []
    if (ci) { values.push(ci.class); values.push(ci.initialClass); values.push(ci.initialTitle) }
    if (o) { values.push(o["class"]); values.push(o["initialClass"]); values.push(o["initialTitle"]) }
    values.push(t.title)
    values.push(root.windowKey(t))
    for (var i = 0; i < values.length; i++) {
      var v = String(values[i] || "")
      if (v.indexOf("class:") === 0) return true
      if (root.excludedClassMatch(v)) return true
    }
    return false
  }

  function groupKeyFor(t) {
    var k = root.windowKey(t)
    if (!root.appLibrary || !k || root.isAliased(k)) return k
    var e = root.entryForId(k) || root.entryForLoose(k)
    if (e) return root.appIdFrom(e).toLowerCase()
    return k
  }

  function windowMinimized(t) {
    var ws = t && t.workspace ? t.workspace : null
    if (!ws) return false
    var name = String(ws.name || "")
    if (name.indexOf("special") === 0) return true
    return Number(ws.id) < 0
  }

  function scheduleRefresh() {
    root.dirty = true
    fingerTimer.restart()
  }

  function onToplevelSignal() {
    root.scheduleRefresh()
  }

  function armToplevel(t) {
    if (!t) return
    var a = String(t.address)
    if (!a || root.watched[a]) return
    root.watched[a] = t
    if (typeof t.workspaceChanged === "function" && typeof t.workspaceChanged.connect === "function")
      t.workspaceChanged.connect(root.onToplevelSignal)
    if (typeof t.activatedChanged === "function" && typeof t.activatedChanged.connect === "function")
      t.activatedChanged.connect(root.onToplevelSignal)
    if (typeof t.titleChanged === "function" && typeof t.titleChanged.connect === "function")
      t.titleChanged.connect(root.onToplevelSignal)
  }

  function pruneWatched(alive) {
    var keep = {}
    for (var i = 0; i < alive.length; i++) keep[String(alive[i].address)] = true
    var a
    for (a in root.watched) {
      if (!keep[a]) {
        var t = root.watched[a]
        if (t && t.workspaceChanged && typeof t.workspaceChanged.disconnect === "function")
          t.workspaceChanged.disconnect(root.onToplevelSignal)
        if (t && t.activatedChanged && typeof t.activatedChanged.disconnect === "function")
          t.activatedChanged.disconnect(root.onToplevelSignal)
        if (t && t.titleChanged && typeof t.titleChanged.disconnect === "function")
          t.titleChanged.disconnect(root.onToplevelSignal)
        delete root.watched[a]
      }
    }
  }

  function maybeRefresh() {
    if (!root.dirty) return
    root.refreshClientInfo()
    var tls = root.toplevelValues()
    root.armAll(tls)
    var active = Hyprland.activeToplevel
    if (active) {
      var addr = String(active.address)
      var rec = root.recentAddresses.slice()
      var at = rec.indexOf(addr)
      if (at >= 0) rec.splice(at, 1)
      rec.unshift(addr)
      root.recentAddresses = rec.slice(0, 40)
    }
    var finger = ""
    for (var i = 0; i < tls.length; i++) {
      var t = tls[i]
      var ws = t.workspace
      finger += String(t.address) + "|" + (ws ? String(ws.name) : "") + "|" + String(!!t.activated) + "|" + String(t.title || "") + ";"
    }
    finger += "|a=" + (active ? String(active.address) : "") + "|p=" + root.pinned.join(",")
    if (finger === root.fingerprint) { root.dirty = false; return }
    root.fingerprint = finger
    root.rebuild(tls)
    root.dirty = false
  }

  function armAll(tls) {
    for (var i = 0; i < tls.length; i++) root.armToplevel(tls[i])
    root.pruneWatched(tls)
  }

  function matchRunningGroup(running, wanted) {
    wanted = String(wanted || "").toLowerCase()
    if (!wanted || !running) return null
    if (running[wanted]) return running[wanted]
    var keys = Object.keys(running)
    var sameLength = null
    for (var i = 0; i < keys.length; i++) {
      var k = keys[i]
      if (!k) continue
      if (k === wanted) return running[k]
      var sub = k.indexOf(wanted) >= 0 || wanted.indexOf(k) >= 0
      if (!sub) continue
      if (k.length === wanted.length) return running[k]
      if (!sameLength) sameLength = running[k]
    }
    return sameLength
  }

  function liveWindowForKey(wanted) {
    wanted = String(wanted || "").toLowerCase()
    if (!wanted) return null
    var tls = root.toplevelValues()
    for (var i = 0; i < tls.length; i++) {
      if (root.isExcludedWindow(tls[i])) continue
      var key = root.groupKeyFor(tls[i])
      if (key === wanted || (key.indexOf(wanted) >= 0 || wanted.indexOf(key) >= 0))
        return { address: String(tls[i].address), minimized: root.windowMinimized(tls[i]) }
    }
    return null
  }

  function rebuild(tls) {
    var running = {}
    for (var i = 0; i < tls.length; i++) {
      var t = tls[i]
      if (root.isExcludedWindow(t)) continue
      var key = root.groupKeyFor(t)
      if (!key) key = "window"
      var group = running[key]
      if (!group) {
        group = { key: key, name: "", icon: "", desktopId: "", windows: [] }
        running[key] = group
      }
      group.windows.push({
        address: String(t.address),
        title: String(t.title || ""),
        activated: !!t.activated,
        minimized: root.windowMinimized(t)
      })
    }

    var keys = Object.keys(running)
    for (var k = 0; k < keys.length; k++) {
      var g = running[keys[k]]
      if (root.isAliased(g.key)) {
        g.name = g.windows.length > 0 ? g.windows[0].title : g.key
        g.icon = ""
        g.desktopId = ""
        continue
      }
      var e = root.entryForId(g.key) || root.entryForLoose(g.key)
      if (e) {
        g.desktopId = root.appIdFrom(e)
        g.name = root.entryName(e)
        g.icon = String(e.icon || "")
      } else {
        g.name = g.windows.length > 0 ? g.windows[0].title : g.key
        g.icon = ""
        g.desktopId = ""
      }
    }

    var out = []
    var seen = {}
    var pinnedMigrate = null
    var p
    for (p = 0; p < root.pinned.length; p++) {
      var pid = root.normalizeDesktopId(String(root.pinned[p]))
      if (!pid) continue
      // Pinned entries that begin with "class:" are never shown.
      if (pid.indexOf("class:") === 0) continue
      var entry = null
      var classKey = ""
      if (pid.indexOf("class:") === 0) {
        classKey = pid.slice(6)
        if (!root.isAliased(classKey)) {
          entry = classKey ? root.entryForLoose(classKey) : null
          if (entry) {
            var canonical = root.appIdFrom(entry)
            if (canonical && canonical.toLowerCase() !== pid.toLowerCase()) {
              if (!pinnedMigrate) pinnedMigrate = []
              pinnedMigrate.push({ at: p, to: canonical })
            }
          }
        }
      } else {
        entry = root.entryForId(pid)
      }
      var itemKey = entry ? root.appIdFrom(entry) : (classKey || pid)
      if (classKey && root.excludedClassMatch(classKey)) continue
      if (!classKey && root.excludedClassMatch(itemKey)) continue
      var runningGroup = root.matchRunningGroup(running, entry ? itemKey.toLowerCase() : classKey)
      var item = {
        key: itemKey,
        name: entry ? root.entryName(entry) : (classKey || itemKey),
        iconName: entry ? String(entry.icon || "") : "",
        desktopId: entry ? itemKey : "",
        classIcon: classKey || (entry ? "" : itemKey),
        _pinId: pid
      }
      if (!entry) item.launchName = classKey || itemKey
      item.pinned = true
      root.finishItem(item, runningGroup)
      out.push(item)
      seen[entry ? itemKey.toLowerCase() : (classKey ? classKey.toLowerCase() : pid.toLowerCase())] = true
    }
    if (pinnedMigrate && pinnedMigrate.length > 0) {
      var newPinned = root.pinned.slice()
      for (var m = 0; m < pinnedMigrate.length; m++) newPinned[pinnedMigrate[m].at] = pinnedMigrate[m].to
      root.pinned = newPinned
      root.savePinned()
    }
    for (var k2 = 0; k2 < keys.length; k2++) {
      var g2 = running[keys[k2]]
      var mergeKey = g2.desktopId ? g2.desktopId.toLowerCase() : g2.key
      if (seen[mergeKey]) continue
      var item2 = {
        key: g2.key,
        name: g2.name,
        iconName: g2.icon,
        desktopId: g2.desktopId,
        classIcon: g2.key
      }
      item2.pinned = false
      root.finishItem(item2, g2)
      out.push(item2)
    }
    root.items = out
  }

  function finishItem(item, group) {
    var windows = group ? group.windows : []
    var onScreen = 0
    var minCount = 0
    var anyActive = false
    for (var i = 0; i < windows.length; i++) {
      if (windows[i].minimized) minCount++
      else onScreen++
      if (windows[i].activated) anyActive = true
    }
    item.running = windows.length > 0
    item.onScreen = onScreen
    item.minimized = item.running && minCount === windows.length
    item.active = anyActive
    item.windows = windows
  }

  function pinnedIndexOf(id) {
    id = root.normalizeDesktopId(id)
    for (var i = 0; i < root.pinned.length; i++)
      if (root.normalizeDesktopId(root.pinned[i]) === id) return i
    return -1
  }

  function pinKey(item) {
    if (!item) return ""
    var d = root.normalizeDesktopId(String(item.desktopId || ""))
    if (d) return d
    var k = root.normalizeDesktopId(String(item.key || ""))
    return k ? "class:" + k : ""
  }

  function pinItem(item) {
    var id = root.pinKey(item)
    if (!id) return
    if (root.pinnedIndexOf(id) >= 0) return
    var next = root.pinned.slice()
    next.push(id)
    root.pinned = next
    root.savePinned()
    root.scheduleRefresh()
  }

  function unpinItem(item) {
    var id = String(item && item._pinId || root.pinKey(item))
    var next = []
    for (var i = 0; i < root.pinned.length; i++)
      if (root.normalizeDesktopId(root.pinned[i]) !== id) next.push(root.pinned[i])
    root.pinned = next
    root.savePinned()
    root.scheduleRefresh()
  }

  function launchItem(item) {
    if (!item) return
    var id = String(item.desktopId || "")
    if (id && root.appLibrary) {
      root.appLibrary.launch(id, item.name)
      return
    }
    var name = String(item.launchName || "")
    if (/^[a-zA-Z0-9._-]+$/.test(name) && !/^[.-]/.test(name) && root.bar && typeof root.bar.run === "function")
      root.bar.run("bash -lc " + Util.shellQuote(name + " &"))
  }

  function savePinned() {
    if (!root.bar || typeof root.bar.run !== "function") return
    var list = ""
    for (var i = 0; i < root.pinned.length; i++) list += "\"" + root.normalizeDesktopId(root.pinned[i]) + "\" "
    if (!list) list = "''"
    root.bar.run("bash -lc 'mkdir -p \"$HOME/.local/state/omarchy/taskbar\" && printf \"%s\\n\" " + list + " > \"$HOME/.local/state/omarchy/taskbar/pinned.tmp\" && mv -f \"$HOME/.local/state/omarchy/taskbar/pinned.tmp\" \"$HOME/.local/state/omarchy/taskbar/pinned\"'")
  }

  function applyPinned(text) {
    var raw = String(text || "")
    var ids = []
    var removed = false
    var lines = raw.split("\n")
    for (var i = 0; i < lines.length; i++) {
      var t = lines[i].trim()
      if (!t) continue
      // Drop any "class:" pin ids so they are never shown (and clean the file).
      if (t.indexOf("class:") === 0) { removed = true; continue }
      ids.push(root.normalizeDesktopId(t))
    }
    root.pinned = ids
    if (removed) root.savePinned()
    root.scheduleRefresh()
  }

  function focusedWorkspaceName() {
    var ws = Hyprland.focusedWorkspace
    if (ws && String(ws.name || "").length > 0 && String(ws.name).indexOf("special") !== 0)
      return String(ws.name)
    return "1"
  }

  function runHc(args) {
    if (!root.bar || typeof root.bar.run !== "function") return
    root.bar.run("hyprctl " + args)
  }

  function minimizeAddress(addr) {
    if (!addr) return
    root.runHc("dispatch " + Util.shellQuote("hl.dsp.window.move({ workspace = \"special:omarchy-taskbar\", follow = false, window = \"address:0x" + addr + "\" })"))
  }

  function restoreWindow(addr, focus) {
    if (!addr) return
    var ws = root.focusedWorkspaceName()
    var silent = focus ? "" : ", follow = false"
    root.runHc("dispatch " + Util.shellQuote("hl.dsp.window.move({ workspace = \"" + ws + "\"" + silent + ", window = \"address:0x" + addr + "\" })"))
  }

  function focusWindow(addr) {
    if (!addr) return
    root.runHc("dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"address:0x" + addr + "\" })"))
  }

  function clickItem(item) {
    if (!item) return
    if (!item.running) {
      if (root.liveWindowForKey(item.classIcon || item.key)) {
        root.scheduleRefresh()
        return
      }
      root.launchItem(item)
      return
    }
    if (item.minimized) {
      var focusAddr = root.restoreCandidate(item)
      for (var i = 0; i < item.windows.length; i++) {
        var w = item.windows[i]
        if (!w.minimized) continue
        root.restoreWindow(w.address, w.address === focusAddr)
      }
      return
    }
    if (item.active) {
      for (var j = 0; j < item.windows.length; j++) {
        var w2 = item.windows[j]
        if (w2.minimized) continue
        root.minimizeAddress(w2.address)
      }
      return
    }
    root.focusWindow(root.restoreCandidate(item))
  }

  function restoreCandidate(item) {
    for (var i = 0; i < root.recentAddresses.length; i++) {
      for (var j = 0; j < item.windows.length; j++) {
        if (item.windows[j].address === root.recentAddresses[i]) return item.windows[j].address
      }
    }
    for (var k = item.windows.length - 1; k >= 0; k--) {
      if (item.windows[k].minimized) return item.windows[k].address
    }
    return item.windows.length > 0 ? item.windows[item.windows.length - 1].address : ""
  }

  function itemTooltip(item) {
    if (!item) return ""
    var tip = item.name
    if (item.running && item.windows.length > 1)
      tip += "  (" + item.windows.length + " windows)"
    return tip
  }

  function openMenu(item, button) {
    if (!item) return
    menu.menuItem = item
    menu.anchorItem = button
    menu.open = true
  }

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    anchors.fill: parent
    spacing: Style.spacing.xs

    Repeater {
      model: root.items

      delegate: Item {
        id: taskDelegate
        required property var modelData
        required property int index

        readonly property var item: root.items[index]

        width: root.vertical ? root.barSize : root.buttonWidth
        height: root.vertical ? root.buttonWidth : root.barSize

        Rectangle {
          id: bgRect
          anchors.fill: parent
          radius: Style.cornerRadius
          color: "transparent"
        }

        Image {
          id: iconImage
          anchors.centerIn: parent
          width: Math.max(1, Math.min(root.iconSize, parent.width - Style.spacing.xs * 2))
          height: Math.max(1, Math.min(root.iconSize, parent.height - Style.spacing.xs * 2))
          source: root.iconFor(taskDelegate.item)
          sourceSize.width: root.iconSize * 2
          sourceSize.height: root.iconSize * 2
          fillMode: Image.PreserveAspectFit
          smooth: true
          opacity: taskDelegate.item.running
            ? (taskDelegate.item.active ? 1.0 : (taskDelegate.item.minimized ? 0.4 : 0.9))
            : 0.8
        }

        Rectangle {
          id: indicator
          visible: taskDelegate.item.running
          width: root.vertical ? Math.max(1, Math.round(Style.space(2))) : Math.round(Style.space(14))
          height: root.vertical ? Math.round(Style.space(14)) : Math.max(1, Math.round(Style.space(2)))
          radius: Math.max(1, Math.min(width, height) / 2)
          color: taskDelegate.item.active ? root.activeIndicatorColor : root.runningIndicatorColor
          x: root.vertical ? parent.width - width - Math.max(2, Style.spacing.xs) : parent.width / 2 - width / 2
          y: root.vertical ? parent.height / 2 - height / 2 : parent.height - height - Math.max(2, Style.spacing.xs)
        }

        Rectangle {
          id: pinnedDot
          visible: taskDelegate.item.pinned
          width: root.vertical ? Math.max(1, Math.round(Style.space(5))) : Math.round(Style.space(4))
          height: root.vertical ? Math.round(Style.space(4)) : Math.max(1, Math.round(Style.space(5)))
          radius: Math.max(1, Math.min(width, height) / 2)
          color: taskDelegate.item.running ? Util.alpha(root.chroma, 0.55) : root.chroma
          x: Math.max(2, Style.space(2))
          y: Math.max(2, Style.space(2))
        }

        MouseArea {
          id: taskMouse
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor

          onEntered: {
            bgRect.color = root.hoverColor
            if (root.bar) root.bar.showTooltip(taskDelegate, root.itemTooltip(taskDelegate.item))
          }
          onExited: {
            bgRect.color = "transparent"
            if (root.bar) root.bar.hideTooltip(taskDelegate)
          }
          onClicked: function(mouse) {
            if (mouse.button === Qt.RightButton) {
              root.openMenu(taskDelegate.item, taskDelegate)
              return
            }
            root.clickItem(taskDelegate.item)
          }
        }
      }
    }
  }

  PopupCard {
    id: menu
    bar: root.bar
    owner: root
    anchorItem: root
    contentWidth: Math.round(Style.space(180))
    contentHeight: Math.round(Style.space(56))
    property var menuItem: null

    onOpenChanged: if (open) Qt.callLater(function() { menuKeys.forceActiveFocus() })

    Item {
      id: menuKeys
      anchors.fill: parent
      visible: false
      focus: true
      Keys.onEscapePressed: menu.open = false
    }

    ColumnLayout {
      anchors.fill: parent
      spacing: Style.spacing.xs

      MenuAction {
        Layout.fillWidth: true
        label: root.menuLabel(menu.menuItem)
        visible: label !== ""
        onChosen: {
          menu.open = false
          if (!menu.menuItem) return
          if (menu.menuItem.pinned) root.unpinItem(menu.menuItem)
          else root.pinItem(menu.menuItem)
        }
      }
    }
  }

  Timer {
    id: fingerTimer
    interval: 120
    onTriggered: root.maybeRefresh()
  }

  Timer {
    id: pollTimer
    running: true
    interval: 1500
    repeat: true
    onTriggered: root.scheduleRefresh()
  }

  FileView {
    path: root.pinnedPath
    watchChanges: false
    printErrors: false
    onLoaded: root.applyPinned(text())
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { root.scheduleRefresh() }
  }

  Connections {
    target: Hyprland
    function onActiveToplevelChanged() { root.scheduleRefresh() }
    function onFocusedWorkspaceChanged() { root.scheduleRefresh() }
  }

  Component.onCompleted: Qt.callLater(function() {
    root.refreshClientInfo()
    root.scheduleRefresh()
  })

  function menuLabel(item) {
    if (!item) return ""
    return item.pinned ? "Unpin from taskbar" : "Pin to taskbar"
  }
}