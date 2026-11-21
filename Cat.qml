// Navbar Pets — colourful pixel-art companions for the Omarchy bar.
//
// The plugin is a `kind: "panel"` with `keepLoaded: true`, so the shell mounts
// it at startup and it lives for the whole session. It draws a transparent
// overlay strip over every connected monitor's bar (via `Variants` on
// `Quickshell.screens`) on `WlrLayer.Overlay`, and is click-through everywhere
// except the small Food Dot and settled pets.
//
// All decision-making lives in Brain.js, which is pure and unit-tested.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs.Commons
import "Brain.js" as Brain
import "Frames.js" as Frames

Item {
  id: root

  // Injected by the shell host.
  property var shell: null
  property var manifest: null
  property string omarchyPath: ""

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "io.github.pradeepjung45.navbar-pets"
  readonly property string assetDir: {
    var dir = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    if (dir === "") return ""
    return (dir.indexOf("file://") === 0 ? dir : "file://" + dir) + "/assets"
  }
  readonly property string helper: {
    var dir = manifest && manifest.__sourceDir ? String(manifest.__sourceDir) : ""
    if (dir === "") return ""
    return dir.replace(/^file:\/\//, "") + "/bin/navbar-cat-cursor"
  }

  // The shell assigns `manifest` after the component is constructed, so paths
  // derived from it are empty until `ready` turns true.
  readonly property bool ready: assetDir !== "" && helper !== ""

  // ---------------------------------------------------------------- config

  // Settings live inline on this plugin's entry in shell.json's `plugins[]`.
  // Third-party plugins receive a capability-scoped PluginShellApi where writes
  // go strictly through `shell.updateEntryInline(pluginId, settings)`. We watch
  // shell.json via FileView and re-parse whenever `pluginId` updates after
  // `manifest` is injected at startup so saved pets and settings always survive
  // restarts and reboots.
  property var fileConfig: ({})
  property var localOverrides: ({})
  property int configRevision: 0
  property string _rawShellJson: ""
  property bool _shellFileLoaded: false
  property string barBackgroundLook: "opaque"
  readonly property bool barIsTranslucent: barBackgroundLook === "none" || barBackgroundLook === "glassy"

  FileView {
    id: shellConfigFile
    path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      root._shellFileLoaded = true
      root._rawShellJson = String(text() || "")
      root.loadConfigFromFile(root._rawShellJson)
    }
    onFileChanged: reload()
  }

  onPluginIdChanged: {
    if (root._shellFileLoaded && root._rawShellJson !== "") {
      root.loadConfigFromFile(root._rawShellJson)
    } else {
      shellConfigFile.reload()
    }
  }

  onReadyChanged: {
    if (ready && !root._shellFileLoaded) {
      shellConfigFile.reload()
    }
  }

  function loadConfigFromFile(raw) {
    var found = ({})
    var barBg = "opaque"
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      if (parsed && parsed.bar && typeof parsed.bar === "object") {
        if (parsed.bar.background) barBg = String(parsed.bar.background)
        else if (parsed.bar.transparent === true) barBg = "none"
      }
      var list = parsed && Array.isArray(parsed.plugins) ? parsed.plugins : []
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].id || "") === root.pluginId) {
          found = list[i]
          break
        }
      }
    } catch (e) {}
    root.barBackgroundLook = barBg
    root.fileConfig = found
    var remaining = ({})
    for (var k in root.localOverrides) {
      if (JSON.stringify(found[k]) !== JSON.stringify(root.localOverrides[k])) {
        remaining[k] = root.localOverrides[k]
      }
    }
    root.localOverrides = remaining
    root.configRevision++
    root.nudge()
  }

  readonly property var config: {
    var rev = root.configRevision
    var out = ({})
    var settings = shell && shell.shellConfig ? shell.shellConfig.plugins : null
    if (Array.isArray(settings)) {
      for (var i = 0; i < settings.length; i++) {
        if (settings[i] && String(settings[i].id || "") === root.pluginId) {
          for (var sk in settings[i]) out[sk] = settings[i][sk]
          break
        }
      }
    }
    for (var fk in fileConfig) out[fk] = fileConfig[fk]
    for (var lk in localOverrides) out[lk] = localOverrides[lk]
    return out
  }

  readonly property real speed: {
    var rev = root.configRevision
    var s = Number(config.speed)
    return s > 0 ? Math.max(0.25, Math.min(3.0, s)) : 1.0
  }
  readonly property bool pettable: {
    var rev = root.configRevision
    return config.pettable !== false
  }
  readonly property bool chaseCursor: {
    var rev = root.configRevision
    return config.chaseCursor !== false
  }
  readonly property int sleepAfter: {
    var rev = root.configRevision
    return Number(config.sleepAfter) > 0 ? Number(config.sleepAfter) : 180
  }
  readonly property var reactions: {
    var rev = root.configRevision
    return config.reactions && typeof config.reactions === "object" ? config.reactions : ({})
  }
  readonly property int catSize: {
    var rev = root.configRevision
    var sz = Number(config.size)
    return sz > 0 ? Math.max(12, Math.min(64, Math.round(sz))) : 24
  }

  // Keep the `characters` array reference stable unless the actual character
  // list changes so switching themes or settings never tears down and resets
  // active pet delegates.
  property var characters: ["neko"]

  function syncCharacters() {
    var raw = config.characters
    var out = []
    if (Array.isArray(raw)) {
      for (var i = 0; i < raw.length; i++) {
        var c = String(raw[i] || "")
        if (Frames.CHARACTERS.indexOf(c) !== -1 && out.indexOf(c) === -1) {
          out.push(c)
        }
      }
    }
    if (out.length === 0) {
      var wanted = String(config.character || "neko")
      out.push(Frames.CHARACTERS.indexOf(wanted) !== -1 ? wanted : "neko")
    }
    if (out.join(",") !== root.characters.join(",")) {
      root.characters = out
    }
  }

  onConfigRevisionChanged: syncCharacters()

  readonly property string character: characters[0] || "neko"
  onCharactersChanged: root.nudge()

  readonly property bool pounce: {
    var rev = root.configRevision
    return config.pounce !== false
  }
  readonly property bool showFoodDot: {
    var rev = root.configRevision
    return config.foodDot !== false
  }
  readonly property bool autoPlay: {
    var rev = root.configRevision
    return config.autoPlay !== false
  }
  readonly property string backdrop: {
    var rev = root.configRevision
    var b = String(config.backdrop || "none").toLowerCase()
    var allowed = ["none", "forest", "mountain", "space", "beach", "castle"]
    return allowed.indexOf(b) !== -1 ? b : "none"
  }
  readonly property string backdropStyle: {
    var rev = root.configRevision
    var s = String(config.backdropStyle || "clear-zones").toLowerCase()
    var allowed = ["clear-zones", "horizon", "full"]
    return allowed.indexOf(s) !== -1 ? s : "clear-zones"
  }
  readonly property real backdropOpacity: {
    var rev = root.configRevision
    var o = Number(config.backdropOpacity)
    return isFinite(o) && o > 0 ? Math.max(0.15, Math.min(0.90, o)) : 0.55
  }
  readonly property bool avoidWidgets: {
    var rev = root.configRevision
    return config.avoidWidgets !== false
  }
  readonly property var avoidEdges: avoidWidgets ? ({ left: 0.13, right: 0.22 }) : null
  readonly property real avoidCenter: config.avoidCenter !== undefined
    ? Math.max(0, Math.min(0.9, Number(config.avoidCenter)))
    : (avoidWidgets ? 0.24 : 0.2)
  readonly property bool rhythm: config.rhythm !== false
  readonly property int stirEvery: Number(config.stirEvery) > 0 ? Number(config.stirEvery) : 150
  readonly property int stirFor: Number(config.stirFor) > 0 ? Number(config.stirFor) : 25

  // Keep the overlay window strictly confined to the bar strip so animals never
  // drop down below the navbar.
  readonly property int headroom: 0

  // ------------------------------------------------------------ bar state

  readonly property var bar: shell ? shell.bar : null
  readonly property string barPosition: bar ? String(bar.position) : "top"
  readonly property bool vertical: barPosition === "left" || barPosition === "right"
  readonly property int barSize: bar && bar.barSize ? bar.barSize : 26
  readonly property bool barHidden: bar ? bar.barHidden === true : false

  // ------------------------------------------------------------- monitors

  // Default to "all" so attaching external monitors displays pets and navbar
  // themes on every monitor's bar automatically. Users can also set
  // `monitor: "focused"` or pin a specific output name (e.g. "DP-1").
  readonly property string monitorMode: {
    var rev = root.configRevision
    var wanted = String(config.monitor || "all").trim()
    return wanted !== "" ? wanted : "all"
  }
  readonly property string focusedMonitorName: {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }
  readonly property var catScreen: {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    var target = (monitorMode !== "all" && monitorMode !== "focused")
      ? monitorMode
      : focusedMonitorName
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name) === target) return screens[i]
    }
    return screens[0]
  }

  // --------------------------------------------------------- world inputs

  property bool pointerKnown: false
  property real pointerX: 0
  property real pointerY: 0
  property real lastPointerMoveAt: 0
  property var workspaceEvent: null
  property real notifyAt: -1
  property real themeChangedAt: -1

  readonly property var notifications: shell && shell.serviceFor
    ? shell.serviceFor("omarchy.notifications") : null
  readonly property var popupModel: notifications && notifications.popupModel
    ? notifications.popupModel : null
  property int _popupCount: 0

  Connections {
    target: root.popupModel
    function onCountChanged() {
      var n = root.popupModel ? root.popupModel.count : 0
      if (n > root._popupCount && root.reactions.notification !== false) {
        root.notifyAt = Date.now()
        root.nudge()
      }
      root._popupCount = n
    }
  }

  readonly property color themeInk: Color.bar.text
  property bool _themeSeen: false
  onThemeInkChanged: {
    if (_themeSeen && reactions.theme !== false) {
      themeChangedAt = Date.now()
      nudge()
    }
    _themeSeen = true
  }

  readonly property bool musicPlaying: {
    if (reactions.music === false) return false
    var players = Mpris.players ? Mpris.players.values : []
    for (var i = 0; i < players.length; i++) {
      if (players[i] && players[i].isPlaying) return true
    }
    return false
  }

  readonly property bool charging: {
    if (reactions.charging === false) return false
    var device = UPower.displayDevice
    return !!(device && device.isPresent && !UPower.onBattery)
  }

  readonly property int chaseMargin: 12

  function pointerOnBarFor(scr) {
    if (!scr || !pointerKnown) return false
    var sx = scr.x, sy = scr.y
    var sw = scr.width, sh = scr.height
    if (pointerX < sx || pointerX > sx + sw || pointerY < sy || pointerY > sy + sh) return false
    var depth = barSize + chaseMargin
    if (barPosition === "top") return pointerY - sy <= depth
    if (barPosition === "bottom") return (sy + sh) - pointerY <= depth
    if (barPosition === "left") return pointerX - sx <= depth
    return (sx + sw) - pointerX <= depth
  }

  function pointerAlongBarFor(scr) {
    if (!scr) return 0
    return vertical ? pointerY - scr.y : pointerX - scr.x
  }

  // ------------------------------------------------ shared species helpers

  function treatKindFor(charId) {
    var c = String(charId || "")
    if (c === "dog" || c.indexOf("dog-") === 0) return "bone"
    if (c.indexOf("rat-") === 0) return "cheese"
    if (c === "panda" || c.indexOf("panda-") === 0) return "bamboo"
    if (c.indexOf("horse-") === 0) return "apple"
    if (c.indexOf("bird-") === 0) return "berry"
    if (c.indexOf("fairy-") === 0) return "star"
    return "fish"
  }

  function speciesSpeedFactor(charId) {
    if (charId === "horse-brown" || charId === "horse-white" || charId === "fairy-unicorn") return 1.24
    if (charId === "bird-blue" || charId === "bird-parrot") return 1.22
    if (charId === "rat-gray" || charId === "rat-white") return 1.18
    if (charId === "fairy-pixie" || charId === "fairy-dragon") return 1.12
    if (charId === "dog" || charId.indexOf("dog-") === 0) return 1.08
    if (charId === "panda" || charId === "panda-red") return 0.78
    return 1.0
  }

  function isBirdChar(charId) {
    return charId === "bird-blue" || charId === "bird-parrot"
  }

  function isHeavyLandChar(charId) {
    return charId === "horse-brown"
      || charId === "horse-white"
      || charId === "fairy-unicorn"
      || charId === "panda"
      || charId === "panda-red"
  }

  // --------------------------------------------------- cross-monitor bus

  signal nudgeAll()
  signal feedRequested(string targetScreenName, var atPos)
  signal playRequested(string targetScreenName, real durationMs)

  property var _awakeByScreen: ({})
  property bool allSleeping: false

  function reportScreenAwake(scrName, isAwake) {
    if (!scrName) return
    var next = ({})
    var anyAwake = false
    for (var k in _awakeByScreen) {
      if (k !== scrName) {
        next[k] = _awakeByScreen[k]
        if (next[k]) anyAwake = true
      }
    }
    if (isAwake !== null && isAwake !== undefined) {
      next[scrName] = !!isAwake
      if (next[scrName]) anyAwake = true
    }
    _awakeByScreen = next
    allSleeping = !anyAwake
  }

  function nudge() {
    if (!barHidden) nudgeAll()
  }

  function dropFood(atPos, screenName) {
    var target = (screenName !== undefined && screenName !== null) ? String(screenName) : ""
    feedRequested(target, atPos)
    return "fed"
  }

  function startPlay(durationMs, screenName) {
    var dur = Number(durationMs) > 0 ? Number(durationMs) : 11000
    var target = (screenName !== undefined && screenName !== null) ? String(screenName) : ""
    playRequested(target, dur)
    return "playing"
  }

  function openMenuOn(scr, anchor) {
    catMenu.menuScreen = scr ? scr : root.catScreen
    catMenu.anchorPos = isFinite(Number(anchor)) ? Number(anchor) : 200
    catMenu.open = true
    return "ok"
  }

  // --------------------------------------------------------- cursor feed

  Process {
    id: cursorFeed
    running: root.ready && root.chaseCursor && !root.barHidden
    command: [root.helper]
    stdinEnabled: true

    stdout: SplitParser {
      onRead: function (line) {
        var parts = String(line).trim().split(/\s+/)
        if (parts.length < 2) return
        var x = parseInt(parts[0], 10)
        var y = parseInt(parts[1], 10)
        if (isNaN(x) || isNaN(y)) return
        root.pointerX = x
        root.pointerY = y
        root.pointerKnown = true
        root.lastPointerMoveAt = Date.now()
        root.nudge()
      }
    }
  }

  readonly property int cursorInterval: allSleeping ? 500 : 100
  onCursorIntervalChanged: if (cursorFeed.running) cursorFeed.write(cursorInterval + "\n")

  // ------------------------------------------------------- event sources

  Connections {
    target: Hyprland
    function onFocusedWorkspaceChanged() {
      var workspace = Hyprland.focusedWorkspace
      if (!workspace) return
      var id = Number(workspace.id)
      if (root._lastWorkspaceId >= 0 && id !== root._lastWorkspaceId) {
        root.workspaceEvent = { at: Date.now(), dir: id > root._lastWorkspaceId ? 1 : -1 }
        root.nudge()
      }
      root._lastWorkspaceId = id
    }
  }
  property int _lastWorkspaceId: -1

  onMusicPlayingChanged: nudge()
  onChargingChanged: nudge()
  onBarPositionChanged: nudge()
  onBarHiddenChanged: if (!barHidden) nudge()

  readonly property int tickMs: 33

  Component.onCompleted: {
    syncCharacters()
    lastPointerMoveAt = Date.now()
    var workspace = Hyprland.focusedWorkspace
    if (workspace) _lastWorkspaceId = Number(workspace.id)
    nudge()
  }

  // ------------------------------------------------------------- settings

  // Writes go strictly through the shell's scoped `updateEntryInline` API.
  function setSettings(patch) {
    if (!root._shellFileLoaded) {
      var raw = String(shellConfigFile.text() || "")
      if (raw !== "") {
        root._shellFileLoaded = true
        root._rawShellJson = raw
        root.loadConfigFromFile(raw)
      }
    }

    var nextOverrides = ({})
    for (var ok in root.localOverrides) nextOverrides[ok] = root.localOverrides[ok]
    for (var pk in patch) nextOverrides[pk] = patch[pk]
    root.localOverrides = nextOverrides
    root.configRevision++
    root.nudge()

    var merged = ({ id: root.pluginId })
    for (var ck in root.config) merged[ck] = root.config[ck]
    for (var mk in patch) merged[mk] = patch[mk]

    if (shell && typeof shell.updateEntryInline === "function") {
      shell.updateEntryInline(root.pluginId, merged)
    }
  }

  function setSetting(key, value) {
    if (key === "dropFood") {
      var foodScreen = catMenu.menuScreen ? String(catMenu.menuScreen.name || "") : ""
      root.dropFood(null, foodScreen)
      return
    }
    if (key === "startPlay") {
      var playScreen = catMenu.menuScreen ? String(catMenu.menuScreen.name || "") : ""
      root.startPlay(value, playScreen)
      return
    }
    if (key === "toggleCharacter") {
      root.toggleCharacter(value)
      return
    }
    if (key === "onlyOneCharacter") {
      var list = root.characters
      var keep = list.length > 0 ? list[list.length - 1] : "neko"
      root.setSettings({ characters: [keep], character: keep })
      return
    }
    if (key === "character") {
      var wanted = String(value || "neko")
      root.setSettings({ characters: [wanted], character: wanted })
      return
    }
    var patch = ({})
    patch[key] = value
    root.setSettings(patch)
  }

  CatMenu {
    id: catMenu
    cat: root
    onChose: function (key, value) { root.setSetting(key, value) }
  }

  function open(payload) {
    return openMenu()
  }

  function close() {
    catMenu.open = false
    return "ok"
  }

  function openMenu() {
    var scr = root.catScreen
    var center = scr ? Math.round((root.vertical ? scr.height : scr.width) * 0.25) : 200
    return root.openMenuOn(scr, center)
  }

  function toggleCharacter(name) {
    var wanted = String(name || "")
    if (Frames.CHARACTERS.indexOf(wanted) === -1) {
      return "unknown character: " + wanted + " (" + Frames.CHARACTERS.join(", ") + ")"
    }
    var next = root.characters.slice()
    var idx = next.indexOf(wanted)
    if (idx !== -1) {
      if (next.length > 1) next.splice(idx, 1)
    } else {
      next.push(wanted)
    }
    root.setSettings({ characters: next, character: next[0] })
    return next.join(",")
  }

  function setCharacters(csv) {
    var parts = String(csv || "").split(",")
    var next = []
    for (var i = 0; i < parts.length; i++) {
      var c = parts[i].trim()
      if (Frames.CHARACTERS.indexOf(c) !== -1 && next.indexOf(c) === -1) {
        next.push(c)
      }
    }
    if (next.length === 0) return "no valid characters (" + Frames.CHARACTERS.join(", ") + ")"
    root.setSettings({ characters: next, character: next[0] })
    return next.join(",")
  }

  function setCharacter(name) {
    var wanted = String(name || "")
    if (wanted.indexOf(",") !== -1) {
      return root.setCharacters(wanted)
    }
    if (Frames.CHARACTERS.indexOf(wanted) === -1) {
      return "unknown character: " + wanted + " (" + Frames.CHARACTERS.join(", ") + ")"
    }
    root.setSettings({ characters: [wanted], character: wanted })
    return wanted
  }

  function setSize(px) {
    var val = Math.round(Number(px))
    if (!isFinite(val) || val < 12 || val > 64) return "invalid size (12..64)"
    root.setSetting("size", val)
    return String(val)
  }

  function setBackdrop(name) {
    var b = String(name || "none").toLowerCase().trim()
    var allowed = ["none", "forest", "mountain", "space", "beach", "castle"]
    if (allowed.indexOf(b) === -1) {
      return "unknown backdrop: " + b + " (" + allowed.join(", ") + ")"
    }
    root.setSetting("backdrop", b)
    return b
  }

  ShellIpc {
    id: ipcHandler
    target: root.pluginId

    function openMenu(): string {
      return root.openMenu()
    }

    function feed(): string {
      return root.dropFood()
    }

    function play(): string {
      return root.startPlay(11000)
    }

    function toggleCharacter(name: string): string {
      return root.toggleCharacter(name)
    }

    function setCharacters(csv: string): string {
      return root.setCharacters(csv)
    }

    function setCharacter(name: string): string {
      return root.setCharacter(name)
    }

    function setSize(px: int): string {
      return root.setSize(px)
    }

    function setBackdrop(name: string): string {
      return root.setBackdrop(name)
    }

    function getCharacter(): string {
      return root.characters.join(",")
    }
  }

  // ------------------------------------------------ per-monitor windows

  Variants {
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: window
        required property var modelData

        screen: modelData
        readonly property string screenName: modelData ? String(modelData.name || "") : ""
        readonly property bool screenEnabled: modelData !== null && (
          root.monitorMode === "all"
          || (root.monitorMode === "focused"
              ? (root.catScreen && String(modelData.name) === String(root.catScreen.name))
              : String(modelData.name) === root.monitorMode)
        )
        visible: screenEnabled && !root.barHidden
        color: "transparent"

        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "io.github.pradeepjung45.navbar-pets"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: root.barPosition !== "bottom"
          bottom: root.barPosition !== "top"
          left: root.barPosition !== "right"
          right: root.barPosition !== "left"
        }
        implicitWidth: root.vertical ? root.barSize + root.headroom : 0
        implicitHeight: root.vertical ? 0 : root.barSize + root.headroom

        readonly property real barLength: modelData
          ? (root.vertical ? modelData.height : modelData.width)
          : 0
        readonly property real stripCentre: root.vertical
          ? (root.barPosition === "left" ? root.barSize / 2 : window.width - root.barSize / 2)
          : (root.barPosition === "top" ? root.barSize / 2 : window.height - root.barSize / 2)
        readonly property real feederPos: Math.max(root.catSize, Math.round(barLength * 0.24))

        // Per-monitor animation, pet state, food, and bouncing ball state
        property int animTick: 0
        property int maskRevision: 0
        property var _actors: ({})
        property bool windowSleeping: false

        property bool foodActive: false
        property real foodPos: 0
        property real foodAmount: 0
        property string foodWinner: ""
        property string foodKind: "fish"
        property bool foodEating: false
        property int _foodDropSeq: 0

        property real playUntil: -1
        property real playSpot: 0
        property bool ballActive: false
        property real ballPos: 0
        property real ballY: 0
        property real ballVx: 0
        property real ballVy: 0
        property real ballLastHitAt: 0

        function wakeWindow() {
          if (window.visible && !ticker.running) ticker.running = true
        }

        function localDropFood(atPos) {
          if (!window.visible || window.barLength <= 0) return
          var maxPos = Math.max(0, window.barLength - root.catSize)
          var list = root.characters
          var now = Date.now()
          var actor0 = _ensureActor(root.character, 0, maxPos)
          var picked = (atPos !== undefined && atPos !== null && isFinite(Number(atPos)))
            ? Number(atPos)
            : Brain.pickSpot(actor0.brainState, maxPos, window.barLength, root.avoidCenter, root.avoidEdges)
          foodPos = Math.max(root.catSize, Math.min(window.barLength - root.catSize, picked))
          foodAmount = 1.0
          foodWinner = ""
          foodEating = false
          var targetChar = list.length > 0 ? list[_foodDropSeq % list.length] : root.character
          _foodDropSeq++
          foodKind = root.treatKindFor(targetChar)
          for (var i = 0; i < list.length; i++) {
            var a = _ensureActor(list[i], i, maxPos)
            a.alertUntil = now + 550
          }
          foodActive = true
          ballActive = false
          playUntil = -1
          wakeWindow()
        }

        function localStartPlay(durationMs) {
          if (!window.visible || window.barLength <= 0) return
          var maxPos = Math.max(0, window.barLength - root.catSize)
          var now = Date.now()
          var baseDur = Number(durationMs) > 0 ? Number(durationMs) : 11000
          var list = root.characters
          var actor0 = _ensureActor(root.character, 0, maxPos)
          var launchPos = Brain.pickSpot(actor0.brainState, maxPos, window.barLength, root.avoidCenter, root.avoidEdges)
          var dir = launchPos < window.barLength * 0.5 ? 1 : -1
          ballPos = Math.max(root.catSize, Math.min(window.barLength - root.catSize, launchPos))
          ballY = Math.max(8, root.barSize * 0.65)
          ballVx = dir * (135 + (now % 45))
          ballVy = 78
          ballLastHitAt = 0
          ballActive = true
          for (var i = 0; i < list.length; i++) {
            var a = _ensureActor(list[i], i, maxPos)
            a.mood = "play"
            a.alertUntil = now + 450
            a.playCenter = Math.max(root.catSize * 2, Math.min(maxPos - root.catSize * 2, launchPos + (i - (list.length - 1) / 2) * 55))
            a.moodUntil = now + baseDur + (i % 3) * 1400
          }
          playSpot = launchPos
          playUntil = now + baseDur
          wakeWindow()
        }

        function _ensureActor(charId, index, maxPos) {
          var actor = _actors[charId]
          if (!actor) {
            var charIdx = Math.max(0, Frames.CHARACTERS.indexOf(charId))
            var scrHash = 0
            for (var s = 0; s < screenName.length; s++) scrHash = (scrHash * 31 + screenName.charCodeAt(s)) & 0xFFFF
            var seed = (Date.now() + scrHash * 4099 + (index + 1) * 104729 + charIdx * 7919) % 2147483647
            var bState = Brain.freshState(seed > 0 ? seed : 987654321)
            var initialPos = Brain.pickSpot(bState, maxPos, window.barLength, root.avoidCenter, root.avoidEdges)
            var initialMoods = ["play", "wander", "rest"]
            var initMood = initialMoods[(index + charIdx + scrHash) % 3]
            actor = {
              pos: initialPos,
              pose: "stop",
              bob: false,
              settled: false,
              lift: 0,
              pettedAt: -1,
              brainState: bState,
              speedScale: 0.85 + ((index * 37 + charIdx * 19 + scrHash) % 24) / 100,
              animOffset: (index * 5 + charIdx * 3 + scrHash) & 0xff,
              mood: initMood,
              moodUntil: Date.now() + (initMood === "rest" ? 16000 : 4500) + ((index * 1900 + charIdx * 900) % 6500),
              playCenter: initialPos,
              restLimitMs: 2800 + ((index * 1300 + charIdx * 700) % 5500),
              heartUntil: -1,
              alertUntil: -1
            }
            _actors[charId] = actor
          }
          return actor
        }

        function step() {
          if (!window.visible || window.barLength <= 0) {
            ticker.running = false
            return
          }

          var now = Date.now()
          var dt = root.tickMs / 1000
          var maxPos = Math.max(0, window.barLength - root.catSize)
          var onBar = root.pointerOnBarFor(window.modelData)
          var pPos = root.pointerAlongBarFor(window.modelData)
          var list = root.characters
          var count = list.length
          var everyIdle = count > 0
          var minWakeIn = Infinity
          var eatingCount = 0

          var globalPlay = !foodActive && now < playUntil

          if (ballActive) {
            if (!globalPlay || foodActive) {
              ballActive = false
            } else {
              ballPos += ballVx * dt
              var ballMin = 8
              var ballMax = Math.max(ballMin, window.barLength - 8)
              if (ballPos <= ballMin) {
                ballPos = ballMin
                ballVx = Math.abs(ballVx) * 0.82
              } else if (ballPos >= ballMax) {
                ballPos = ballMax
                ballVx = -Math.abs(ballVx) * 0.82
              }
              ballVy -= 360 * dt
              ballY += ballVy * dt
              var maxBallY = Math.max(6, root.barSize - 10)
              if (ballY > maxBallY) {
                ballY = maxBallY
                ballVy = -Math.abs(ballVy) * 0.5
              }
              if (ballY <= 0) {
                ballY = 0
                if (Math.abs(ballVy) > 22) {
                  ballVy = Math.abs(ballVy) * 0.68
                } else {
                  ballVy = 0
                  ballVx *= 0.96
                }
              }
              playSpot = Math.max(0, Math.min(maxPos, ballPos - root.catSize / 2))
              everyIdle = false
            }
          }

          for (var i = 0; i < count; i++) {
            var charId = list[i]
            var actor = _ensureActor(charId, i, maxPos)
            var delegate = petRepeater.itemAt(i)
            var hovered = delegate && delegate.hovered === true

            if (foodActive && foodWinner === "" && Math.abs((actor.pos + root.catSize / 2) - foodPos) <= root.catSize * 0.65) {
              foodWinner = charId
            }
            var chasingFood = foodActive && (foodWinner === "" || foodWinner === charId)

            if (ballActive && now - ballLastHitAt > 550
                && Math.abs((actor.pos + root.catSize / 2) - ballPos) <= root.catSize * 0.6
                && ballY <= 7) {
              var kickDir = (ballPos < window.barLength * 0.25) ? 1
                : (ballPos > window.barLength * 0.75 ? -1 : (ballVx >= 0 ? -1 : 1))
              ballVx = kickDir * (125 + ((now + i * 37) % 65))
              ballVy = 85 + ((now + i * 19) % 35)
              ballLastHitAt = now
              actor.heartUntil = now + 800
            }

            if (!chasingFood && !globalPlay && now >= actor.moodUntil) {
              var roll = Brain.nextRandom ? Brain.nextRandom(actor.brainState) : Math.random()
              var durRoll = Brain.nextRandom ? Brain.nextRandom(actor.brainState) : Math.random()
              if (root.autoPlay && roll < 0.34) {
                actor.mood = "play"
                actor.brainState.nextStirAt = null
                actor.playCenter = Brain.pickSpot(actor.brainState, maxPos, window.barLength, root.avoidCenter, root.avoidEdges)
                actor.moodUntil = now + 4500 + Math.round(durRoll * 4500)
              } else if (roll < 0.70) {
                actor.mood = "wander"
                actor.brainState.nextStirAt = null
                actor.restLimitMs = 1500 + Math.round(durRoll * 4500)
                actor.moodUntil = now + 5500 + Math.round(durRoll * 6000)
              } else {
                actor.mood = "rest"
                actor.moodUntil = now + 16000 + Math.round(durRoll * 12000)
              }
            }

            var wantsCursor = onBar && root.chaseCursor && !catMenu.open && !chasingFood && !ballActive
            var actorPlaying = !chasingFood && !wantsCursor && (globalPlay || (root.autoPlay && actor.mood === "play"))
            var actorResting = !chasingFood && !wantsCursor && !actorPlaying && actor.mood === "rest"

            var spread = (i - (count - 1) / 2) * (root.catSize + 4)
            var charPointerPos = Math.max(root.catSize / 2, Math.min(window.barLength - root.catSize / 2, pPos + spread))
            var centerForPlay = globalPlay ? playSpot : actor.playCenter
            var playRadius = Math.max(root.catSize * 2, Math.min(110, maxPos * 0.15))
            var playWave = Math.sin(now / (1250 / actor.speedScale) + i * 2.15)
            var charPlayTarget = ballActive
              ? Math.max(0, Math.min(maxPos, ballPos - root.catSize / 2 + (i % 3 - 1) * 6))
              : Math.max(0, Math.min(maxPos, centerForPlay + playWave * playRadius))
            var leapSin = Math.sin(now / 520 + i * 1.9)
            var charIsBird = root.isBirdChar(charId)
            var charIsHeavyLand = root.isHeavyLandChar(charId)
            var charPlayLift = charIsBird
              ? (leapSin > 0.35 ? ((leapSin - 0.35) / 0.65) * 0.75 : 0.25)
              : (charIsHeavyLand
                  ? 0
                  : (leapSin > 0.80 ? ((leapSin - 0.80) / 0.20) * 0.45 : 0))

            var holdForClick = catMenu.open || (!actorPlaying && actor.settled && hovered)

            var decision = Brain.decide({
              now: now,
              axis: root.vertical ? "v" : "h",
              edge: root.barPosition,
              barLength: window.barLength,
              catSize: root.catSize,
              x: actor.pos,
              food: chasingFood ? { active: true, pos: foodPos } : null,
              play: actorPlaying ? { active: true, target: charPlayTarget, lift: charPlayLift } : null,
              soloRest: actorResting,
              pointer: wantsCursor ? { onBar: true, pos: holdForClick ? (actor.pos + root.catSize / 2) : charPointerPos } : null,
              pettedAt: actor.pettedAt >= 0 ? actor.pettedAt : null,
              lastPointerMoveAt: root.lastPointerMoveAt,
              music: root.musicPlaying,
              charging: root.charging && (now - root.lastPointerMoveAt > root.sleepAfter * 1000),
              workspaceEvent: root.workspaceEvent,
              notifyAt: root.notifyAt >= 0 ? root.notifyAt : null,
              notifying: root.reactions.notification !== false && root.popupModel !== null
                && root.popupModel.count > 0,
              themeChangedAt: root.themeChangedAt >= 0 ? root.themeChangedAt : null,
              hour: new Date().getHours(),
              config: {
                chaseCursor: root.chaseCursor,
                pettable: root.pettable,
                sleepAfter: root.sleepAfter,
                pounce: root.pounce && !charIsHeavyLand,
                rhythm: root.rhythm,
                avoidCenter: root.avoidCenter,
                avoidWidgets: root.avoidWidgets,
                stirEvery: root.stirEvery,
                stirFor: root.stirFor,
                lively: true,
                restLimitMs: actor.restLimitMs,
                reactions: root.reactions,
              },
            }, actor.brainState)

            actor.brainState = decision.state

            if (decision.reason === "eat" && foodWinner === "") {
              foodWinner = charId
            }

            var targetPos = decision.target
            if (decision.reason === "notification" && count > 1) {
              var notifyOffset = i * (root.catSize + 4)
              targetPos = root.vertical
                ? Math.min(maxPos, targetPos + notifyOffset)
                : Math.max(0, targetPos - notifyOffset)
            }

            var speciesMult = root.speciesSpeedFactor(charId)
            var isSprinting = false
            if (decision.snap) {
              actor.pos = targetPos
            } else {
              var stepSpeed = decision.reason === "food"
                ? 92
                : (ballActive
                    ? 88
                    : (decision.reason === "play"
                        ? 68
                        : (decision.gait === "run" ? 64 : (decision.gait === "walk" ? 34 : 0))))
              var stepPx = stepSpeed * speciesMult * actor.speedScale * root.speed * dt
              var delta = targetPos - actor.pos
              if (stepPx > 0 && Math.abs(delta) > 0.5) {
                actor.pos = Math.abs(delta) <= stepPx
                  ? targetPos
                  : actor.pos + (delta > 0 ? stepPx : -stepPx)
                isSprinting = stepSpeed >= 64
              }
            }
            actor.pos = Math.max(0, Math.min(maxPos, actor.pos))
            actor.pose = decision.pose
            actor.bob = decision.bob
            actor.lift = decision.lift
            actor.settled = decision.gait === "idle"

            if (delegate) {
              delegate.catPos = actor.pos
              delegate.catPose = actor.pose
              delegate.catBob = actor.bob
              delegate.catLift = actor.lift
              delegate.catSettled = actor.settled
              delegate.animOffset = actor.animOffset
              delegate.showHeart = now < actor.heartUntil
              delegate.heartProgress = now < actor.heartUntil ? 1 - (actor.heartUntil - now) / 1000 : 0
              delegate.showAlert = (chasingFood || ballActive) && now < actor.alertUntil
              delegate.isDancing = decision.reason === "music"
              delegate.isSprinting = isSprinting
            }

            if (foodActive && foodWinner === charId && (decision.reason === "eat" || Math.abs((actor.pos + root.catSize / 2) - foodPos) <= root.catSize * 0.8)) {
              eatingCount = 1
            }
            if (!decision.idle || actorPlaying || now < actor.heartUntil || now < actor.alertUntil) everyIdle = false
            if (decision.idle && decision.wakeIn > 0 && decision.wakeIn < minWakeIn) {
              minWakeIn = decision.wakeIn
            }
          }

          foodEating = foodActive && eatingCount > 0
          if (foodActive) {
            everyIdle = false
            if (eatingCount > 0) {
              foodAmount = Math.max(0, foodAmount - 0.42 * dt)
              if (foodAmount <= 0) {
                var winnerActor = foodWinner !== "" ? _actors[foodWinner] : null
                if (winnerActor) {
                  winnerActor.pettedAt = now - 2500
                  winnerActor.heartUntil = now + 1000
                }
                foodActive = false
                foodWinner = ""
                foodEating = false
              }
            }
          }
          if (globalPlay) everyIdle = false

          if (windowSleeping !== everyIdle) {
            windowSleeping = everyIdle
            root.reportScreenAwake(screenName, !everyIdle)
          }

          if (root.workspaceEvent && now - root.workspaceEvent.at > 4000) root.workspaceEvent = null
          if (root.notifyAt >= 0 && now - root.notifyAt > 20000) root.notifyAt = -1
          if (root.themeChangedAt >= 0 && now - root.themeChangedAt > 4000) root.themeChangedAt = -1

          if (everyIdle) {
            ticker.running = false
            animTick = 0
            if (isFinite(minWakeIn) && minWakeIn > 0) {
              stirAlarm.interval = Math.max(1000, Math.round(minWakeIn))
              stirAlarm.restart()
            }
          }
        }

        Timer {
          id: ticker
          interval: root.tickMs
          repeat: true
          running: false
          onTriggered: window.step()
        }

        Timer {
          id: animator
          interval: window.windowSleeping ? 900 : 185
          repeat: true
          running: window.visible && (ticker.running || window.windowSleeping)
          onTriggered: window.animTick = (window.animTick + 1) & 0xff
        }

        Timer {
          id: stirAlarm
          repeat: false
          onTriggered: window.wakeWindow()
        }

        Connections {
          target: root
          function onNudgeAll() { window.wakeWindow() }
          function onFeedRequested(targetName, atPos) {
            if (targetName === "" || targetName === window.screenName) {
              window.localDropFood(atPos)
            }
          }
          function onPlayRequested(targetName, durationMs) {
            if (targetName === "" || targetName === window.screenName) {
              window.localStartPlay(durationMs)
            }
          }
        }

        onVisibleChanged: {
          if (visible) {
            root.reportScreenAwake(screenName, true)
            wakeWindow()
          } else {
            ticker.running = false
            root.reportScreenAwake(screenName, null)
          }
        }

        Component.onCompleted: {
          if (visible) {
            root.reportScreenAwake(screenName, true)
            wakeWindow()
          }
        }

        Component.onDestruction: {
          root.reportScreenAwake(screenName, null)
        }

        function hitBoxAt(idx) {
          var rev = window.maskRevision
          if (idx >= petRepeater.count) return null
          var item = petRepeater.itemAt(idx)
          return (item && item.maskActive) ? item.hitBox : null
        }

        // Click-through everywhere the pets and feeder dot are not.
        mask: Region {
          Region { item: (window.visible && root.showFoodDot) ? feederHitBox : null }
          Region { item: window.hitBoxAt(0) }
          Region { item: window.hitBoxAt(1) }
          Region { item: window.hitBoxAt(2) }
          Region { item: window.hitBoxAt(3) }
          Region { item: window.hitBoxAt(4) }
          Region { item: window.hitBoxAt(5) }
          Region { item: window.hitBoxAt(6) }
          Region { item: window.hitBoxAt(7) }
          Region { item: window.hitBoxAt(8) }
          Region { item: window.hitBoxAt(9) }
          Region { item: window.hitBoxAt(10) }
          Region { item: window.hitBoxAt(11) }
          Region { item: window.hitBoxAt(12) }
          Region { item: window.hitBoxAt(13) }
          Region { item: window.hitBoxAt(14) }
          Region { item: window.hitBoxAt(15) }
          Region { item: window.hitBoxAt(16) }
          Region { item: window.hitBoxAt(17) }
          Region { item: window.hitBoxAt(18) }
          Region { item: window.hitBoxAt(19) }
        }

        // Optional scenic navbar backdrop (Forest, Mountain, Space, Beach, Castle).
        // When Omarchy's bar is transparent/glassy, a dedicated WlrLayer.Bottom
        // window renders this behind the bar text instead; on opaque bars it
        // renders here with GPU-masked widget clear-zones or horizon trim.
        ScenicBackdrop {
          id: navbarBackdrop
          z: 0
          visible: !root.barIsTranslucent && root.backdrop !== "none" && window.visible && !root.vertical
          anchors.fill: parent
          styleMode: root.backdropStyle
          backdropAlpha: root.backdropOpacity
          animTick: window.animTick
        }

        // Small clickable "Food Dot" on each monitor's bar.
        Item {
          id: feederHitBox
          z: 4
          visible: root.showFoodDot && window.visible
          width: 18
          height: 18
          x: root.vertical
            ? Math.round(window.stripCentre - width / 2)
            : Math.round(window.feederPos - width / 2)
          y: root.vertical
            ? Math.round(window.feederPos - height / 2)
            : Math.round(window.stripCentre - height / 2)

          Rectangle {
            anchors.centerIn: parent
            width: feederMouse.containsMouse ? 10 : 8
            height: width
            radius: width / 2
            color: "#F49238"
            border.width: 1.5
            border.color: "#562812"

            Rectangle {
              width: 3; height: 3; radius: 1.5
              x: 2; y: 2
              color: "#FFE2B2"
            }
          }

          MouseArea {
            id: feederMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: function (mouse) {
              if (mouse.button === Qt.RightButton) {
                root.openMenuOn(window.modelData, window.feederPos)
                return
              }
              window.localDropFood()
            }
          }
        }

        // Dropped species-matched treat on this monitor's bar floor.
        Item {
          id: droppedFoodItem
          z: 1
          visible: window.foodActive && window.visible
          readonly property real scaleFactor: 0.4 + 0.6 * window.foodAmount
          readonly property int baseW: window.foodKind === "bone" || window.foodKind === "fish" ? 16 : 13
          readonly property int baseH: window.foodKind === "bamboo" ? 15 : 12
          width: Math.max(6, Math.round(baseW * scaleFactor))
          height: Math.max(6, Math.round(baseH * scaleFactor))
          x: root.vertical
            ? Math.round(window.stripCentre - width / 2)
            : Math.round(window.foodPos - width / 2)
          y: root.vertical
            ? Math.round(window.foodPos - height / 2)
            : Math.max(0, Math.round(root.barSize - height - 1))

          // Fish treat (Cats)
          Item {
            visible: window.foodKind === "fish"
            anchors.fill: parent
            Rectangle {
              width: Math.max(5, parent.width - 4)
              height: Math.max(4, parent.height - 2)
              anchors.verticalCenter: parent.verticalCenter
              x: 0
              radius: height / 2
              color: (window.animTick & 1) ? "#38BDF8" : "#0EA5E9"
              border.width: 1.2
              border.color: "#0C4A6E"
              Rectangle {
                width: 2; height: 2; radius: 1
                x: 2; y: Math.max(1, Math.round(parent.height * 0.3))
                color: "#0F172A"
              }
            }
            Rectangle {
              width: 4
              height: Math.max(4, parent.height - 3)
              anchors.verticalCenter: parent.verticalCenter
              anchors.right: parent.right
              radius: 1
              color: "#FB7185"
              border.width: 1
              border.color: "#881337"
            }
          }

          // Bone treat (Dogs)
          Item {
            visible: window.foodKind === "bone"
            anchors.fill: parent
            Rectangle {
              width: 5; height: Math.max(5, parent.height - 2)
              anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
              radius: 2.5; color: "#FEF3C7"; border.width: 1.2; border.color: "#78350F"
            }
            Rectangle {
              width: 5; height: Math.max(5, parent.height - 2)
              anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
              radius: 2.5; color: "#FEF3C7"; border.width: 1.2; border.color: "#78350F"
            }
            Rectangle {
              width: Math.max(4, parent.width - 4)
              height: Math.max(4, Math.round(parent.height * 0.52))
              anchors.centerIn: parent
              radius: 1.5; color: "#FFFBEB"; border.width: 1.2; border.color: "#78350F"
            }
          }

          // Cheese wedge (Rats)
          Rectangle {
            visible: window.foodKind === "cheese"
            anchors.fill: parent
            radius: 3; color: "#FACC15"; border.width: 1.4; border.color: "#713F12"
            Rectangle { width: 3; height: 3; radius: 1.5; x: 2; y: 2; color: "#CA8A04" }
            Rectangle {
              width: 2; height: 2; radius: 1
              anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 2
              color: "#CA8A04"
            }
          }

          // Bamboo shoot (Pandas)
          Item {
            visible: window.foodKind === "bamboo"
            anchors.fill: parent
            Rectangle {
              width: Math.max(5, Math.round(parent.width * 0.58))
              height: parent.height
              anchors.horizontalCenter: parent.horizontalCenter
              radius: 2; color: "#4ADE80"; border.width: 1.2; border.color: "#14532D"
              Rectangle { width: parent.width; height: 1.5; y: Math.round(parent.height * 0.48); color: "#166534" }
            }
            Rectangle {
              width: 4; height: 3; radius: 1.5
              anchors.right: parent.right; y: 2
              color: "#22C55E"; border.width: 1; border.color: "#14532D"
            }
          }

          // Crisp Apple / Berry (Horses & Birds)
          Item {
            visible: window.foodKind === "apple" || window.foodKind === "berry"
            anchors.fill: parent
            Rectangle {
              width: parent.width
              height: Math.max(5, parent.height - 2)
              anchors.bottom: parent.bottom
              radius: width / 2
              color: window.foodKind === "berry" ? "#E11D48" : "#EF4444"
              border.width: 1.3; border.color: "#450A0A"
              Rectangle { width: 3; height: 3; radius: 1.5; x: 2; y: 2; color: "#FECDD3" }
            }
            Rectangle {
              width: 4; height: 3; radius: 1.5
              anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter
              color: "#22C55E"; border.width: 1; border.color: "#14532D"
            }
          }

          // Magic Star Crystal (Fairy-tale creatures)
          Item {
            visible: window.foodKind === "star"
            anchors.fill: parent
            Rectangle {
              width: Math.max(6, parent.width - 2); height: width
              anchors.centerIn: parent; rotation: 45; radius: 2
              color: (window.animTick & 1) ? "#FDE047" : "#C084FC"
              border.width: 1.3; border.color: "#4C1D95"
              Rectangle { width: 3; height: 3; radius: 1.5; anchors.centerIn: parent; color: "#FFFFFF" }
            }
          }

          // Animated munching crumbs while the winning pet eats
          Repeater {
            model: window.foodEating ? 3 : 0
            Rectangle {
              required property int index
              width: 2.5; height: 2.5; radius: 1.25
              color: (index === 0) ? "#FDE047" : "#FB923C"
              x: Math.round(droppedFoodItem.width / 2 + ((index - 1) * 5) + (((window.animTick + index) & 1) ? 1 : -1))
              y: Math.round(droppedFoodItem.height * 0.2 - (((window.animTick + index) & 1) ? 3 : 0))
            }
          }
        }

        // Bouncing pixel tennis ball toy tossed when Play is clicked.
        Item {
          id: playBallItem
          z: 2
          visible: window.ballActive && window.visible && !root.vertical
          width: 10
          height: 10
          x: Math.round(window.ballPos - width / 2)
          y: Math.max(0, Math.round(root.barSize - height - 2 - window.ballY))

          Rectangle {
            width: Math.max(4, Math.round(8 - window.ballY * 0.25))
            height: 2; radius: 1
            color: "#000000"
            opacity: Math.max(0.08, 0.28 - window.ballY * 0.012)
            anchors.horizontalCenter: parent.horizontalCenter
            y: Math.round(parent.height + window.ballY)
          }

          Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: "#A3E635"
            border.width: 1.3
            border.color: "#365314"

            Rectangle {
              width: parent.width - 3; height: 1.5
              anchors.centerIn: parent
              rotation: (window.ballPos * 4) % 360
              color: "#FEFCE8"
            }

            Rectangle {
              width: 2.5; height: 2.5; radius: 1.25
              x: 2; y: 1.5
              color: "#FFFFFF"
            }
          }
        }

        Repeater {
          id: petRepeater
          model: root.characters
          onCountChanged: {
            window.maskRevision++
            Qt.callLater(window.step)
          }

          Item {
            id: petItem
            z: 3
            required property string modelData
            required property int index

            property real catPos: 0
            property string catPose: "stop"
            property bool catBob: false
            property real catLift: 0
            property bool catSettled: false
            property int animOffset: 0
            property bool showHeart: false
            property real heartProgress: 0
            property bool showAlert: false
            property bool isDancing: false
            property bool isSprinting: false

            readonly property bool isBird: modelData === "bird-blue"
              || modelData === "bird-parrot"
            readonly property bool isFairyPixie: modelData === "fairy-pixie"
            readonly property bool isDragon: modelData === "fairy-dragon"
            readonly property bool isFlying: petItem.isBird
              && !petItem.catSettled
              && petItem.catPose !== "sleep"
              && petItem.catPose !== "stop"
              && petItem.catPose !== "wash"
              && petItem.catPose !== "yawn"

            readonly property bool hovered: hitMouse.containsMouse
            readonly property bool maskActive: window.visible && (catSettled || hovered)
            property alias hitBox: hitBoxItem

            onMaskActiveChanged: window.maskRevision++
            Component.onCompleted: {
              var existing = window._actors[modelData]
              if (existing) {
                catPos = existing.pos
                catPose = existing.pose
                catBob = existing.bob
                catLift = existing.lift
                catSettled = existing.settled
                animOffset = existing.animOffset
              }
              window.maskRevision++
            }

            readonly property real wingLift: petItem.isFlying
              ? (((window.animTick + petItem.animOffset) & 1) ? 3 : 2)
              : 0
            readonly property real hopUp: Math.round(petItem.catLift * (petItem.isBird ? 3 : 2)) + wingLift
            readonly property int bobOffset: petItem.catBob ? (((window.animTick + petItem.animOffset) & 1) ? -1 : 0) : 0
            readonly property real baseCrossPos: root.vertical
              ? (window.stripCentre - sprite.width / 2)
              : (root.barSize - sprite.height)
            readonly property real rawCrossPos: baseCrossPos - hopUp + bobOffset
            readonly property real crossPos: Math.max(
              Math.min(0, root.barSize - sprite.height),
              Math.min(Math.max(0, root.barSize - sprite.height), rawCrossPos)
            )

            // Subtle ground shadow under the pet's paws on the bar floor.
            Rectangle {
              visible: !root.vertical
              width: Math.max(6, Math.round(root.catSize * (petItem.isFlying ? 0.36 : (0.58 - petItem.catLift * 0.12))))
              height: 3; radius: 1.5
              color: "#000000"
              opacity: petItem.isFlying ? 0.14 : 0.22
              x: Math.round(sprite.x + (sprite.width - width) / 2)
              y: Math.max(0, root.barSize - 3)
            }

            // Subtle gallop dust puffs behind sprinting land animals.
            Item {
              visible: !root.vertical && petItem.isSprinting && !petItem.isBird
                && (petItem.catPose === "left" || petItem.catPose === "right")
              readonly property int trailDir: petItem.catPose === "right" ? -1 : 1
              Rectangle {
                width: 3; height: 3; radius: 1.5
                color: "#E7E5E4"
                opacity: ((window.animTick + petItem.animOffset) & 1) ? 0.65 : 0.25
                x: Math.round(sprite.x + (parent.trailDir < 0 ? -3 : sprite.width + 1))
                y: Math.max(0, root.barSize - 4)
              }
              Rectangle {
                width: 2; height: 2; radius: 1
                color: "#D6D3D1"
                opacity: ((window.animTick + petItem.animOffset) & 1) ? 0.30 : 0.60
                x: Math.round(sprite.x + (parent.trailDir < 0 ? -7 : sprite.width + 5))
                y: Math.max(0, root.barSize - 6)
              }
            }

            // Fairy sparkle dust trailing gently behind a moving Fairy.
            Item {
              visible: !root.vertical && petItem.isFairyPixie && !petItem.catSettled
                && (petItem.catPose === "left" || petItem.catPose === "right")
              readonly property int trailDir: petItem.catPose === "right" ? -1 : 1
              Rectangle {
                width: 2.5; height: 2.5; radius: 1.25
                color: ((window.animTick + petItem.animOffset) & 1) ? "#FEF08A" : "#67E8F9"
                opacity: 0.9
                x: Math.round(sprite.x + (parent.trailDir < 0 ? -4 : sprite.width + 2))
                y: Math.max(1, Math.round(sprite.y + sprite.height * 0.45))
              }
              Rectangle {
                width: 2; height: 2; radius: 1
                color: "#F9A8D4"
                opacity: ((window.animTick + petItem.animOffset) & 1) ? 0.45 : 0.85
                x: Math.round(sprite.x + (parent.trailDir < 0 ? -8 : sprite.width + 6))
                y: Math.max(1, Math.round(sprite.y + sprite.height * 0.28))
              }
            }

            // Tiny warm fire embers flickering behind a sprinting Dragon.
            Rectangle {
              visible: !root.vertical && petItem.isDragon && petItem.isSprinting
                && (petItem.catPose === "left" || petItem.catPose === "right")
              width: 3; height: 3; radius: 1.5
              color: ((window.animTick + petItem.animOffset) & 1) ? "#FDE047" : "#FB923C"
              opacity: 0.9
              x: Math.round(sprite.x + (petItem.catPose === "right" ? sprite.width + 1 : -4))
              y: Math.max(1, Math.round(sprite.y + sprite.height * 0.42))
            }

            CatSprite {
              id: sprite

              width: root.catSize
              height: root.catSize
              devicePixels: root.catSize * (window.modelData ? window.modelData.devicePixelRatio : 1)
              assetDir: root.assetDir
              character: petItem.modelData

              pose: petItem.catPose
              animTick: (window.animTick + petItem.animOffset) & 0xff
              fillColor: Color.bar.text
              inkColor: Color.bar.background

              x: root.vertical ? Math.round(petItem.crossPos) : Math.round(petItem.catPos)
              y: root.vertical ? Math.round(petItem.catPos) : Math.round(petItem.crossPos)
            }

            // Floating music notes while dancing to active media playback.
            Text {
              visible: petItem.isDancing && !petItem.showHeart && !petItem.showAlert
              readonly property int mPhase: (window.animTick + petItem.animOffset) & 1
              textFormat: Text.PlainText
              text: mPhase === 0 ? "♪" : "♫"
              color: mPhase === 0 ? "#A78BFA" : "#38BDF8"
              style: Text.Outline
              styleColor: "#0F172A"
              font.pixelSize: 10
              font.bold: true
              x: Math.round(sprite.x + sprite.width * (mPhase === 0 ? 0.58 : 0.28))
              y: Math.max(0, Math.round(sprite.y - 2 - mPhase * 2))
            }

            // Floating "zzZ" bubble while curled up sleeping.
            Text {
              visible: petItem.catPose === "sleep" && !petItem.showHeart && !petItem.showAlert
              readonly property int zPhase: (window.animTick + petItem.animOffset) % 3
              textFormat: Text.PlainText
              text: zPhase === 0 ? "z" : (zPhase === 1 ? "zZ" : "zzZ")
              color: "#93C5FD"
              style: Text.Outline
              styleColor: "#0F172A"
              font.pixelSize: 9
              font.bold: true
              x: Math.round(sprite.x + sprite.width * 0.62)
              y: Math.max(0, Math.round(sprite.y - 1 - zPhase))
            }

            // Brief "!" alert when spotting freshly dropped food or ball.
            Text {
              visible: petItem.showAlert && !petItem.showHeart
              textFormat: Text.PlainText
              text: "!"
              color: "#FBBF24"
              style: Text.Outline
              styleColor: "#1E1B4B"
              font.pixelSize: 11
              font.bold: true
              x: Math.round(sprite.x + sprite.width / 2 - width / 2)
              y: Math.max(0, Math.round(sprite.y - 2))
            }

            // Tiny floating heart when petted, batting the ball, or winning food.
            Text {
              visible: petItem.showHeart
              textFormat: Text.PlainText
              text: "♥"
              color: "#F43F5E"
              style: Text.Outline
              styleColor: "#4C0519"
              font.pixelSize: 11
              font.bold: true
              opacity: Math.max(0, 1 - petItem.heartProgress)
              x: Math.round(sprite.x + sprite.width / 2 - width / 2)
              y: Math.max(0, Math.round(sprite.y - 2 - petItem.heartProgress * 6))
            }

            Item {
              id: hitBoxItem
              readonly property int pad: 6

              width: root.vertical ? Math.max(root.catSize, root.barSize) : (root.catSize + pad * 2)
              height: root.vertical ? (root.catSize + pad * 2) : Math.max(root.catSize, root.barSize)
              x: root.vertical
                ? Math.max(0, Math.min(window.width - width, Math.round(window.stripCentre - width / 2)))
                : Math.max(0, Math.min(window.width - width, Math.round(sprite.x - pad)))
              y: root.vertical
                ? Math.max(0, Math.min(window.height - height, Math.round(sprite.y - pad)))
                : Math.max(0, Math.min(window.height - height, Math.round(window.stripCentre - height / 2)))

              MouseArea {
                id: hitMouse
                anchors.fill: parent
                enabled: petItem.maskActive
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: function (mouse) {
                  if (mouse.button === Qt.RightButton) {
                    var anchor = root.vertical
                      ? sprite.y + sprite.height / 2
                      : sprite.x + sprite.width / 2
                    root.openMenuOn(window.modelData, anchor)
                    return
                  }
                  if (root.pettable) {
                    var actor = window._ensureActor(petItem.modelData, petItem.index, Math.max(0, window.barLength - root.catSize))
                    var now = Date.now()
                    actor.pettedAt = now
                    actor.heartUntil = now + 1000
                    window.wakeWindow()
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  // Dedicated behind-the-bar scenic layer for transparent/glassy Omarchy bars.
  // Sits on WlrLayer.Bottom (physically behind the WlrLayer.Top bar's clock,
  // battery, and icons) so text and icons float cleanly above vivid scenery.
  Variants {
    id: behindBackdropVariants
    model: Quickshell.screens

    delegate: Component {
      PanelWindow {
        id: behindWin
        required property var modelData
        screen: modelData
        readonly property bool screenEnabled: modelData !== null && (
          root.monitorMode === "all"
          || (root.monitorMode === "focused"
              ? (root.catScreen && String(modelData.name) === String(root.catScreen.name))
              : String(modelData.name) === root.monitorMode)
        )
        visible: root.barIsTranslucent && root.backdrop !== "none" && screenEnabled && !root.vertical && !root.barHidden
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "io.github.pradeepjung45.navbar-pets-backdrop"
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        anchors {
          top: root.barPosition !== "bottom"
          bottom: root.barPosition !== "top"
          left: true
          right: true
        }
        implicitHeight: root.barSize

        property int behindTick: 0
        Timer {
          interval: 280
          repeat: true
          running: behindWin.visible
          onTriggered: behindWin.behindTick++
        }

        ScenicBackdrop {
          anchors.fill: parent
          visible: behindWin.visible
          styleMode: "behind"
          backdropAlpha: Math.min(0.95, root.backdropOpacity + 0.20)
          animTick: behindWin.behindTick
        }
      }
    }
  }

  component ScenicBackdrop: Item {
    id: backdropItem
    property string styleMode: "clear-zones" // "clear-zones" | "horizon" | "full" | "behind"
    property real backdropAlpha: 0.55
    property int animTick: 0

    readonly property bool useClearZones: styleMode === "clear-zones"
    readonly property bool useHorizon: styleMode === "horizon"
    readonly property int slotCount: Math.max(8, Math.floor(width / 80))
    readonly property string imageUrl: (root.ready && root.backdrop !== "none")
      ? (root.assetDir + "/theme-" + root.backdrop + ".png")
      : ""

    // Soft opacity multiplier for animated weather particles so torches,
    // fireflies, and snow also soften gently over clock, workspaces & battery.
    function zoneWeight(px) {
      if (!useClearZones || width <= 0) return 1.0
      var t = px / width
      if (t < 0.11) return 0.14
      if (t < 0.16) return 0.14 + ((t - 0.11) / 0.05) * 0.86
      if (t <= 0.37) return 1.0
      if (t < 0.42) return 1.0 - ((t - 0.37) / 0.05) * 0.90
      if (t <= 0.58) return 0.10
      if (t < 0.63) return 0.10 + ((t - 0.58) / 0.05) * 0.90
      if (t <= 0.78) return 1.0
      if (t < 0.83) return 1.0 - ((t - 0.78) / 0.05) * 0.90
      return 0.10
    }

    clip: true

    // Single static-cached Canvas pass: tiles the 480x32 theme PNG and applies
    // a silky smooth horizontal clear-zones or vertical horizon mask via
    // `destination-in`. Repaints ONLY when theme, style, opacity, or size changes.
    Canvas {
      id: panoramaCanvas
      anchors.fill: parent
      renderStrategy: Canvas.Cooperative
      property string loadedUrl: ""

      function syncSource() {
        var url = backdropItem.imageUrl
        if (url === "") {
          loadedUrl = ""
          requestPaint()
          return
        }
        if (isImageLoaded(url)) {
          loadedUrl = url
          requestPaint()
        } else {
          loadImage(url)
        }
      }

      onImageLoaded: {
        loadedUrl = backdropItem.imageUrl
        requestPaint()
      }
      onWidthChanged: if (width > 0 && height > 0) requestPaint()
      onHeightChanged: if (width > 0 && height > 0) requestPaint()
      Component.onCompleted: syncSource()

      Connections {
        target: backdropItem
        function onImageUrlChanged() { panoramaCanvas.syncSource() }
        function onStyleModeChanged() { panoramaCanvas.requestPaint() }
        function onBackdropAlphaChanged() { panoramaCanvas.requestPaint() }
        function onVisibleChanged() { if (backdropItem.visible) panoramaCanvas.syncSource() }
      }

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        ctx.clearRect(0, 0, width, height)
        var url = backdropItem.imageUrl
        if (url === "" || !isImageLoaded(url) || width <= 0 || height <= 0) return

        var tileW = 480
        var tileH = Math.min(32, height)
        var drawY = Math.round(height - tileH)

        ctx.save()
        ctx.globalCompositeOperation = "source-over"
        ctx.globalAlpha = backdropItem.backdropAlpha
        for (var x = 0; x < width; x += tileW) {
          ctx.drawImage(url, x, drawY, tileW, tileH)
        }
        ctx.restore()

        if (backdropItem.useClearZones) {
          ctx.save()
          ctx.globalCompositeOperation = "destination-in"
          var grad = ctx.createLinearGradient(0, 0, width, 0)
          grad.addColorStop(0.00, "rgba(0,0,0,0.14)")
          grad.addColorStop(0.11, "rgba(0,0,0,0.14)")
          grad.addColorStop(0.16, "rgba(0,0,0,1.00)")
          grad.addColorStop(0.37, "rgba(0,0,0,1.00)")
          grad.addColorStop(0.42, "rgba(0,0,0,0.10)")
          grad.addColorStop(0.58, "rgba(0,0,0,0.10)")
          grad.addColorStop(0.63, "rgba(0,0,0,1.00)")
          grad.addColorStop(0.78, "rgba(0,0,0,1.00)")
          grad.addColorStop(0.83, "rgba(0,0,0,0.10)")
          grad.addColorStop(1.00, "rgba(0,0,0,0.10)")
          ctx.fillStyle = grad
          ctx.fillRect(0, 0, width, height)
          ctx.restore()
        } else if (backdropItem.useHorizon) {
          ctx.save()
          ctx.globalCompositeOperation = "destination-in"
          var vgrad = ctx.createLinearGradient(0, 0, 0, height)
          vgrad.addColorStop(0.00, "rgba(0,0,0,0.00)")
          vgrad.addColorStop(0.45, "rgba(0,0,0,0.05)")
          vgrad.addColorStop(0.70, "rgba(0,0,0,1.00)")
          vgrad.addColorStop(1.00, "rgba(0,0,0,1.00)")
          ctx.fillStyle = vgrad
          ctx.fillRect(0, 0, width, height)
          ctx.restore()
        }
      }
    }

    // Forest: fireflies & drifting leaves
    Repeater {
      model: root.backdrop === "forest" ? backdropItem.slotCount : 0
      Item {
        required property int index
        readonly property real fx: index * 80 + 24 + (((backdropItem.animTick + index) & 1) ? 2 : 0)
        Rectangle {
          width: 3; height: 3; radius: 1.5
          x: parent.fx
          y: Math.max(3, (index * 7) % Math.max(6, backdropItem.height - 10))
          color: "#ECFCCB"
          border.width: 0.5; border.color: "#65A30D"
          opacity: (((backdropItem.animTick + index) % 3 === 0) ? 0.9 : 0.22) * backdropItem.zoneWeight(x)
        }
        Rectangle {
          visible: (index % 2) === 0
          width: 3; height: 2; radius: 1
          x: (index * 85 + ((backdropItem.animTick + index * 3) % 14)) % Math.max(80, Math.round(backdropItem.width))
          y: (backdropItem.animTick + index * 5) % Math.max(8, Math.round(backdropItem.height - 3))
          color: (index % 4 === 0) ? "#86EFAC" : "#FDE047"
          opacity: 0.65 * backdropItem.zoneWeight(x)
        }
      }
    }

    // Mountain: drifting mist & gentle snow flurries
    Repeater {
      model: root.backdrop === "mountain" ? backdropItem.slotCount : 0
      Item {
        required property int index
        Rectangle {
          width: 18; height: 3; radius: 1.5
          x: (index * 95 + backdropItem.animTick * 2) % Math.max(100, Math.round(backdropItem.width))
          y: 4 + (index % 3) * 4
          color: "#F8FAFC"
          opacity: 0.28 * backdropItem.zoneWeight(x)
        }
        Rectangle {
          width: 2; height: 2; radius: 1
          x: (index * 76 + ((backdropItem.animTick + index * 7) % 18)) % Math.max(80, Math.round(backdropItem.width))
          y: (backdropItem.animTick * 2 + index * 9) % Math.max(8, Math.round(backdropItem.height - 3))
          color: "#FFFFFF"
          opacity: 0.72 * backdropItem.zoneWeight(x)
        }
      }
    }

    // Space: twinkling stars & shooting star
    Repeater {
      model: root.backdrop === "space" ? backdropItem.slotCount * 2 : 0
      Rectangle {
        required property int index
        width: 2.5; height: 2.5; radius: 1.25
        x: index * 44 + ((index * 17) % 28)
        y: 3 + ((index * 9) % Math.max(6, backdropItem.height - 10))
        color: (index & 1) ? "#FEF08A" : "#7DD3FC"
        opacity: (((backdropItem.animTick + index) & 1) ? 0.9 : 0.15) * backdropItem.zoneWeight(x)
      }
    }
    Rectangle {
      readonly property int shootStep: backdropItem.animTick % 28
      visible: root.backdrop === "space" && shootStep < 7
      width: 14; height: 1.5; radius: 1
      rotation: 18
      color: "#FEF08A"
      x: Math.round(backdropItem.width * 0.18 + shootStep * 22)
      y: Math.round(2 + shootStep * 2.5)
      opacity: (0.85 - shootStep * 0.11) * backdropItem.zoneWeight(x)
    }

    // Beach: animated surf foam
    Repeater {
      model: root.backdrop === "beach" ? backdropItem.slotCount * 2 : 0
      Rectangle {
        required property int index
        width: 14; height: 2; radius: 1
        x: index * 40 + (((backdropItem.animTick + index) & 1) ? 3 : 0)
        y: backdropItem.height - 5
        color: "#ECFEFF"
        opacity: (((backdropItem.animTick + index) & 1) ? 0.85 : 0.45) * backdropItem.zoneWeight(x)
      }
    }

    // Castle: flickering wall torches
    Repeater {
      model: root.backdrop === "castle" ? Math.max(4, Math.floor(backdropItem.width / 80)) : 0
      Rectangle {
        required property int index
        width: 4; height: ((backdropItem.animTick + index) & 1) ? 6 : 5
        radius: 2
        x: index * 80 + 54
        y: backdropItem.height - 13
        color: ((backdropItem.animTick + index) & 1) ? "#FEF08A" : "#F97316"
        border.width: 1; border.color: "#7C2D12"
        opacity: 0.9 * backdropItem.zoneWeight(x)
      }
    }
  }
}
