// Navbar Cat — a cat that walks along the Omarchy bar.
//
// The plugin is a `kind: "panel"` with `keepLoaded: true`, so the shell mounts
// it at startup (shell.qml:625) and it lives for the whole session. It draws a
// transparent strip over the bar on WlrLayer.Overlay — the same layer the bar's
// own drag ghost uses (Bar.qml:1167) — and is click-through everywhere except a
// small box around the cat while it is sitting still.
//
// All of the cat's decision-making lives in Brain.js, which is pure and tested.
// This file is the body: it gathers what is going on, hands a snapshot to the
// brain each tick, and moves the sprite toward whatever the brain asked for.

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

  // Injected by the shell host (shell.qml:629-637).
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

  // The shell assigns `manifest` after the component is constructed, so every
  // path derived from it is empty for the first moments of life. Nothing that
  // touches the filesystem may start before this turns true, or the sprite
  // tries to load `/cat32-fill.png` and the helper is launched as
  // `/bin/navbar-cat-cursor`.
  readonly property bool ready: assetDir !== "" && helper !== ""

  // ---------------------------------------------------------------- config

  // Settings live inline on this plugin's entry in shell.json's `plugins[]`.
  // Third-party plugins receive a capability-scoped PluginShellApi where
  // `shell.shellConfig` is not exposed and writes go through
  // `shell.updateEntryInline(pluginId, settings)`. We watch shell.json via
  // FileView and re-parse whenever `pluginId` updates after `manifest` is
  // injected at startup so saved pets and settings always survive reboots.
  property var fileConfig: ({})
  property var localOverrides: ({})
  property int configRevision: 0
  property string _rawShellJson: ""
  property bool _shellFileLoaded: false

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
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      var list = parsed && Array.isArray(parsed.plugins) ? parsed.plugins : []
      for (var i = 0; i < list.length; i++) {
        if (list[i] && String(list[i].id || "") === root.pluginId) {
          found = list[i]
          break
        }
      }
    } catch (e) {}
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
    Qt.callLater(root.step)
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

  // Multiple animals can roam the bar simultaneously (`characters: [...]`),
  // while falling back cleanly to the single `character` key. Keep the array
  // reference stable unless the actual character list changes so switching
  // themes or settings never tears down and resets active pet delegates.
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
  onCharactersChanged: Qt.callLater(root.step)

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
  // Fraction of the bar to keep clear when the cat picks its own spot. Omarchy
  // centres the clock, so the middle is the one place reliably occupied.
  readonly property real avoidCenter: config.avoidCenter !== undefined
    ? Math.max(0, Math.min(0.9, Number(config.avoidCenter)))
    : 0.2
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

  // One cat, on the output Hyprland has focused, so it follows you between
  // screens rather than multiplying.
  readonly property string pinnedMonitor: {
    var wanted = String(config.monitor || "focused")
    return wanted === "focused" ? "" : wanted
  }
  readonly property string wantedScreenName: {
    if (pinnedMonitor !== "") return pinnedMonitor
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }
  readonly property var catScreen: {
    var screens = Quickshell.screens
    if (!screens || screens.length === 0) return null
    for (var i = 0; i < screens.length; i++) {
      if (String(screens[i].name) === root.wantedScreenName) return screens[i]
    }
    return screens[0]
  }

  // --------------------------------------------------------- world inputs

  property real pointerX: -1
  property real pointerY: -1
  property real lastPointerMoveAt: 0
  property real pettedAt: -1
  property var workspaceEvent: null
  property real notifyAt: -1
  property real themeChangedAt: -1

  // The shell owns the notification server, so a plugin cannot run a second
  // one — but it does not need to. `serviceFor` hands out the running service
  // (shell.qml:275) and its popup list is deliberately aliased for exactly
  // this: "consumers outside this Item's id scope can bind to it".
  readonly property var notifications: shell && shell.serviceFor
    ? shell.serviceFor("omarchy.notifications") : null
  readonly property var popupModel: notifications && notifications.popupModel
    ? notifications.popupModel : null
  property int _popupCount: 0

  Connections {
    target: root.popupModel
    function onCountChanged() {
      var n = root.popupModel ? root.popupModel.count : 0
      // Only an arrival is interesting; a toast expiring is not news.
      if (n > root._popupCount && root.reactions.notification !== false) {
        root.notifyAt = Date.now()
        root.nudge()
      }
      root._popupCount = n
    }
  }

  // A theme switch repaints the cat mid-stride, which is a good excuse to have
  // it startle. The first assignment is the initial colour, not a change.
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

  // A machine with no battery reports onBattery false forever, which would
  // read as "permanently charging" and leave the cat asleep for good. Only
  // count it as charging when there is actually a battery being charged.
  readonly property bool charging: {
    if (reactions.charging === false) return false
    var device = UPower.displayDevice
    return !!(device && device.isPresent && !UPower.onBattery)
  }

  // The pointer counts as "at the bar" inside the bar strip plus a small
  // approach margin, so heading for the bar is enough to summon the cat.
  readonly property int chaseMargin: 12

  function pointerOnBar() {
    if (!catScreen || pointerX < 0) return false
    var sx = catScreen.x, sy = catScreen.y
    var sw = catScreen.width, sh = catScreen.height
    if (pointerX < sx || pointerX > sx + sw || pointerY < sy || pointerY > sy + sh) return false
    var depth = barSize + chaseMargin
    if (barPosition === "top") return pointerY - sy <= depth
    if (barPosition === "bottom") return (sy + sh) - pointerY <= depth
    if (barPosition === "left") return pointerX - sx <= depth
    return (sx + sw) - pointerX <= depth
  }

  function pointerAlongBar() {
    if (!catScreen) return 0
    return vertical ? pointerY - catScreen.y : pointerX - catScreen.x
  }

  // ------------------------------------------------------------ cat state

  readonly property real barLength: catScreen
    ? (vertical ? catScreen.height : catScreen.width)
    : 0

  property real catPos: 0
  property string catPose: "stop"
  property bool catBob: false
  property bool catSettled: false
  // 0 while on the bar, up to 1 at the top of a pounce.
  property real catLift: 0
  // Which way is "into the screen" from the bar's edge.
  readonly property int inwardSign: (barPosition === "top" || barPosition === "left") ? 1 : -1
  property int animTick: 0
  property int maskRevision: 0
  // Per-character state map so each active animal has its own brain, position,
  // and petted timestamp, and adding/removing an animal preserves the others.
  property var _actors: ({})
  property bool allSleeping: false

  // Food state: clicking the feeder dot (or menu button) drops a treat on the
  // bar. First animal to reach the treat claims it (`foodWinner`) and eats it
  // alone while the others go back to their own activities.
  property bool foodActive: false
  property real foodPos: 0
  property real foodAmount: 0
  property string foodWinner: ""
  property string foodKind: "fish"
  property bool foodEating: false
  property int _foodDropSeq: 0

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

  // Group play & bouncing ball toy state: clicking Play tosses a real physics
  // ball across the bar that bounces off the floor and edges; pets sprint to
  // intercept and bat it back into the air!
  property real playUntil: -1
  property real playSpot: 0
  property real playPhaseUpdatedAt: 0
  property real nextAutoPlayAt: Date.now() + 4000
  property bool ballActive: false
  property real ballPos: 0
  property real ballY: 0
  property real ballVx: 0
  property real ballVy: 0
  property real ballLastHitAt: 0

  readonly property real feederPos: Math.max(catSize, Math.round(barLength * 0.24))

  function dropFood(atPos) {
    var maxPos = Math.max(0, barLength - catSize)
    var list = root.characters
    var now = Date.now()
    var actor0 = _ensureActor(character, 0, maxPos)
    var picked = (atPos !== undefined && atPos !== null && isFinite(Number(atPos)))
      ? Number(atPos)
      : Brain.pickSpot(actor0.brainState, maxPos, barLength, avoidCenter)
    foodPos = Math.max(catSize, Math.min(barLength - catSize, picked))
    foodAmount = 1.0
    foodWinner = ""
    foodEating = false
    var targetChar = list.length > 0 ? list[_foodDropSeq % list.length] : character
    _foodDropSeq++
    foodKind = treatKindFor(targetChar)
    for (var i = 0; i < list.length; i++) {
      var a = _ensureActor(list[i], i, maxPos)
      a.alertUntil = now + 550
    }
    foodActive = true
    ballActive = false
    playUntil = -1
    nudge()
    return String(Math.round(foodPos))
  }

  function startPlay(durationMs) {
    var maxPos = Math.max(0, barLength - catSize)
    var now = Date.now()
    var baseDur = Number(durationMs) > 0 ? Number(durationMs) : 11000
    var list = root.characters
    var actor0 = _ensureActor(character, 0, maxPos)
    var launchPos = Brain.pickSpot(actor0.brainState, maxPos, barLength, avoidCenter)
    var dir = launchPos < barLength * 0.5 ? 1 : -1
    ballPos = Math.max(catSize, Math.min(barLength - catSize, launchPos))
    ballY = Math.max(8, barSize * 0.65)
    ballVx = dir * (135 + (now % 45))
    ballVy = 78
    ballLastHitAt = 0
    ballActive = true
    for (var i = 0; i < list.length; i++) {
      var a = _ensureActor(list[i], i, maxPos)
      a.mood = "play"
      a.alertUntil = now + 450
      a.playCenter = Math.max(catSize * 2, Math.min(maxPos - catSize * 2, launchPos + (i - (list.length - 1) / 2) * 55))
      a.moodUntil = now + baseDur + (i % 3) * 1400
    }
    playSpot = launchPos
    playPhaseUpdatedAt = now
    playUntil = now + baseDur
    nextAutoPlayAt = playUntil + 12000
    nudge()
    return "playing"
  }

  // --------------------------------------------------------- cursor feed

  // Hyprland has no cursor-move event and Quickshell exposes no pointer, so
  // the position is sampled by a helper. See bin/navbar-cat-cursor for why it
  // talks to the socket directly instead of shelling out to hyprctl.
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
        root.lastPointerMoveAt = Date.now()
        root.nudge()
      }
    }
  }

  // A sleeping cat does not need the pointer ten times a second. Slowing the
  // sampler down while it sleeps is most of the reason this costs nothing when
  // the desktop is idle.
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
  onCatScreenChanged: nudge()

  // ------------------------------------------------------------ the tick

  // 30fps: fast enough that a running cat does not visibly stutter, slow
  // enough to be free. The sprite's own frames advance far slower (below).
  readonly property int tickMs: 33

  function nudge() {
    // Something happened that the cat might care about — make sure the loop is
    // running to notice it.
    if (!ticker.running && !barHidden) ticker.running = true
  }

  Timer {
    id: ticker
    interval: root.tickMs
    repeat: true
    running: false
    onTriggered: root.step()
  }

  Timer {
    id: animator
    // oneko alternates its two frames far slower than the movement updates;
    // matching that keeps the walk cycle looking hand-drawn rather than frantic.
    // While all pets sleep, tick gently at 900ms so sleeping pets breathe and
    // float their "zzZ" bubble at virtually zero cost.
    interval: root.allSleeping ? 900 : 185
    repeat: true
    running: !root.barHidden && (ticker.running || root.allSleeping)
    onTriggered: root.animTick = (root.animTick + 1) & 0xff
  }

  function _ensureActor(charId, index, maxPos) {
    var actor = _actors[charId]
    if (!actor) {
      var charIdx = Math.max(0, Frames.CHARACTERS.indexOf(charId))
      var seed = (Date.now() + (index + 1) * 104729 + charIdx * 7919) % 2147483647
      var bState = Brain.freshState(seed > 0 ? seed : 987654321)
      var initialPos = Brain.pickSpot(bState, maxPos, barLength, avoidCenter)
      var initialMoods = ["play", "wander", "rest"]
      var initMood = initialMoods[(index + charIdx) % 3]
      actor = {
        pos: initialPos,
        pose: "stop",
        bob: false,
        settled: false,
        lift: 0,
        pettedAt: -1,
        brainState: bState,
        // Independent personality & autonomous mood schedule per animal:
        speedScale: 0.85 + ((index * 37 + charIdx * 19) % 24) / 100,
        animOffset: (index * 5 + charIdx * 3) & 0xff,
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

  function step() {
    if (!catScreen || barLength <= 0) return

    var now = Date.now()
    var dt = tickMs / 1000
    var maxPos = Math.max(0, barLength - catSize)
    var onBar = pointerOnBar()
    var pPos = pointerAlongBar()
    var list = root.characters
    var count = list.length
    var everyIdle = count > 0
    var minWakeIn = Infinity
    var eatingCount = 0

    var globalPlay = !foodActive && now < playUntil

    // Update bouncing ball physics while active.
    if (ballActive) {
      if (!globalPlay || foodActive) {
        ballActive = false
      } else {
        ballPos += ballVx * dt
        var ballMin = 8
        var ballMax = Math.max(ballMin, barLength - 8)
        if (ballPos <= ballMin) {
          ballPos = ballMin
          ballVx = Math.abs(ballVx) * 0.82
        } else if (ballPos >= ballMax) {
          ballPos = ballMax
          ballVx = -Math.abs(ballVx) * 0.82
        }
        ballVy -= 360 * dt
        ballY += ballVy * dt
        var maxBallY = Math.max(6, barSize - 10)
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
        playSpot = Math.max(0, Math.min(maxPos, ballPos - catSize / 2))
        everyIdle = false
      }
    }

    for (var i = 0; i < count; i++) {
      var charId = list[i]
      var actor = _ensureActor(charId, i, maxPos)
      var delegate = petRepeater.itemAt(i)
      var hovered = delegate && delegate.hovered === true

      // First animal to reach the dropped food claims it; others back off.
      if (foodActive && foodWinner === "" && Math.abs((actor.pos + catSize / 2) - foodPos) <= catSize * 0.65) {
        foodWinner = charId
      }
      var chasingFood = foodActive && (foodWinner === "" || foodWinner === charId)

      // If a pet catches the bouncing ball, bat it back across the navbar!
      if (ballActive && now - ballLastHitAt > 550
          && Math.abs((actor.pos + catSize / 2) - ballPos) <= catSize * 0.6
          && ballY <= 7) {
        var kickDir = (ballPos < barLength * 0.25) ? 1
          : (ballPos > barLength * 0.75 ? -1 : (ballVx >= 0 ? -1 : 1))
        ballVx = kickDir * (125 + ((now + i * 37) % 65))
        ballVy = 85 + ((now + i * 19) % 35)
        ballLastHitAt = now
        actor.heartUntil = now + 800
      }

      // Each animal rolls its own independent mood ("wander", "play", or "rest")
      // when its personal timer expires, so while one rests/naps, others play or stroll!
      if (!chasingFood && !globalPlay && now >= actor.moodUntil) {
        var roll = Brain.nextRandom ? Brain.nextRandom(actor.brainState) : Math.random()
        var durRoll = Brain.nextRandom ? Brain.nextRandom(actor.brainState) : Math.random()
        if (autoPlay && roll < 0.34) {
          actor.mood = "play"
          actor.brainState.nextStirAt = null
          actor.playCenter = Brain.pickSpot(actor.brainState, maxPos, barLength, avoidCenter)
          actor.moodUntil = now + 4500 + Math.round(durRoll * 4500)
        } else if (roll < 0.70) {
          actor.mood = "wander"
          actor.brainState.nextStirAt = null
          actor.restLimitMs = 1500 + Math.round(durRoll * 4500)
          actor.moodUntil = now + 5500 + Math.round(durRoll * 6000)
        } else {
          // Give resting animals 16-28s so they finish grooming/yawning (7.6s)
          // and curl up to sleep peacefully with "zzZ" for 9-20s.
          actor.mood = "rest"
          actor.moodUntil = now + 16000 + Math.round(durRoll * 12000)
        }
      }

      // When the pointer is on the navbar, all animals follow the pointer along
      // the bar; when the pointer leaves the bar, each animal resumes its own
      // independent mood (playing, strolling, or resting).
      var wantsCursor = onBar && chaseCursor && !catMenu.open && !chasingFood && !ballActive
      var actorPlaying = !chasingFood && !wantsCursor && (globalPlay || (autoPlay && actor.mood === "play"))
      var actorResting = !chasingFood && !wantsCursor && !actorPlaying && actor.mood === "rest"

      // Spread multiple animals around the cursor, chase the bouncing ball when
      // active, or weave smoothly during independent play.
      var spread = (i - (count - 1) / 2) * (catSize + 4)
      var charPointerPos = Math.max(catSize / 2, Math.min(barLength - catSize / 2, pPos + spread))
      var centerForPlay = globalPlay ? playSpot : actor.playCenter
      var playRadius = Math.max(catSize * 2, Math.min(110, maxPos * 0.15))
      var playWave = Math.sin(now / (1250 / actor.speedScale) + i * 2.15)
      var charPlayTarget = ballActive
        ? Math.max(0, Math.min(maxPos, ballPos - catSize / 2 + (i % 3 - 1) * 6))
        : Math.max(0, Math.min(maxPos, centerForPlay + playWave * playRadius))
      var leapSin = Math.sin(now / 520 + i * 1.9)
      var charIsBird = isBirdChar(charId)
      var charIsHeavyLand = isHeavyLandChar(charId)
      var charPlayLift = charIsBird
        ? (leapSin > 0.35 ? ((leapSin - 0.35) / 0.65) * 0.75 : 0.25)
        : (charIsHeavyLand
            ? 0
            : (leapSin > 0.80 ? ((leapSin - 0.80) / 0.20) * 0.45 : 0))

      var holdForClick = catMenu.open || (!actorPlaying && actor.settled && hovered)

      var decision = Brain.decide({
        now: now,
        axis: vertical ? "v" : "h",
        edge: barPosition,
        barLength: barLength,
        catSize: catSize,
        x: actor.pos,
        food: chasingFood ? { active: true, pos: foodPos } : null,
        play: actorPlaying ? { active: true, target: charPlayTarget, lift: charPlayLift } : null,
        soloRest: actorResting,
        pointer: wantsCursor ? { onBar: true, pos: holdForClick ? (actor.pos + catSize / 2) : charPointerPos } : null,
        pettedAt: actor.pettedAt >= 0 ? actor.pettedAt : null,
        lastPointerMoveAt: lastPointerMoveAt,
        music: musicPlaying,
        // Only let AC charging put pets to sleep once the user has actually
        // been idle past sleepAfter, so active desktop sessions stay lively.
        charging: charging && (now - lastPointerMoveAt > sleepAfter * 1000),
        workspaceEvent: workspaceEvent,
        notifyAt: notifyAt >= 0 ? notifyAt : null,
        notifying: reactions.notification !== false && popupModel !== null
          && popupModel.count > 0,
        themeChangedAt: themeChangedAt >= 0 ? themeChangedAt : null,
        hour: new Date().getHours(),
        config: {
          chaseCursor: chaseCursor,
          pettable: pettable,
          sleepAfter: sleepAfter,
          pounce: pounce && !charIsHeavyLand,
          rhythm: rhythm,
          avoidCenter: avoidCenter,
          stirEvery: stirEvery,
          stirFor: stirFor,
          lively: true,
          restLimitMs: actor.restLimitMs,
          reactions: reactions,
        },
      }, actor.brainState)

      actor.brainState = decision.state

      if (decision.reason === "eat" && foodWinner === "") {
        foodWinner = charId
      }

      var targetPos = decision.target
      if (decision.reason === "notification" && count > 1) {
        var notifyOffset = i * (catSize + 4)
        targetPos = vertical
          ? Math.min(maxPos, targetPos + notifyOffset)
          : Math.max(0, targetPos - notifyOffset)
      }

      var speciesMult = speciesSpeedFactor(charId)
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
        var stepPx = stepSpeed * speciesMult * actor.speedScale * speed * dt
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

      if (i === 0) {
        catPos = actor.pos
        catPose = actor.pose
        catBob = actor.bob
        catLift = actor.lift
        catSettled = actor.settled
      }

      if (foodActive && foodWinner === charId && (decision.reason === "eat" || Math.abs((actor.pos + catSize / 2) - foodPos) <= catSize * 0.8)) {
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
        foodAmount = Math.max(0, foodAmount - 0.42 * (tickMs / 1000))
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

    allSleeping = everyIdle

    // Let a stale scamper expire so it cannot re-fire.
    if (workspaceEvent && now - workspaceEvent.at > 4000) workspaceEvent = null
    if (notifyAt >= 0 && now - notifyAt > 20000) notifyAt = -1
    if (themeChangedAt >= 0 && now - themeChangedAt > 4000) themeChangedAt = -1

    // When every active animal is asleep, stop the render timer until woken.
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
    id: stirAlarm
    repeat: false
    onTriggered: root.nudge()
  }

  onBarHiddenChanged: {
    if (barHidden) ticker.running = false
    else nudge()
  }

  Component.onCompleted: {
    syncCharacters()
    lastPointerMoveAt = Date.now()
    var workspace = Hyprland.focusedWorkspace
    if (workspace) _lastWorkspaceId = Number(workspace.id)
    nudge()
  }

  // ------------------------------------------------------------- settings

  // The menu is the one thing here that writes. It touches only this plugin's
  // own entry in shell.json, only when you pick something, and it goes strictly
  // through the shell's scoped `updateEntryInline` API.
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
      root.dropFood()
      return
    }
    if (key === "startPlay") {
      root.startPlay(value)
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
    catMenu.anchorPos = root.catPos + root.catSize / 2
    catMenu.open = true
    return "ok"
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
      return root.startPlay(7500)
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


  // ---------------------------------------------------------- the window

  PanelWindow {
    id: window

    screen: root.catScreen
    visible: root.catScreen !== null && !root.barHidden
    color: "transparent"

    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "io.github.pradeepjung45.navbar-pets"
    // Above the bar (which sits on Top), matching what the bar's own drag
    // ghost does when it needs to float over everything.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: root.barPosition !== "bottom"
      bottom: root.barPosition !== "top"
      left: root.barPosition !== "right"
      right: root.barPosition !== "left"
    }
    // The window covers the bar strip plus the pounce headroom, growing inward
    // from the bar's edge. The extra strip is transparent and unmasked, so it
    // changes nothing until the cat actually leaves the ground.
    implicitWidth: root.vertical ? root.barSize + root.headroom : 0
    implicitHeight: root.vertical ? 0 : root.barSize + root.headroom

    // Where the middle of the bar strip sits inside this window. For a top or
    // left bar that is simply half the bar in; for the far edges the headroom
    // is on the near side, so it is measured back from the far end.
    readonly property real stripCentre: root.vertical
      ? (root.barPosition === "left" ? root.barSize / 2 : window.width - root.barSize / 2)
      : (root.barPosition === "top" ? root.barSize / 2 : window.height - root.barSize / 2)

    function hitBoxAt(idx) {
      var rev = root.maskRevision
      if (idx >= petRepeater.count) return null
      var item = petRepeater.itemAt(idx)
      return (item && item.maskActive) ? item.hitBox : null
    }

    // Click-through everywhere the pets and feeder dot are not.
    mask: Region {
      Region { item: (!root.barHidden && root.showFoodDot) ? feederHitBox : null }
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
    // Uses hand-crafted seamless 320x32 pixel-art panorama tiles plus live
    // animated particles (drifting clouds, fireflies, twinkling stars, waves,
    // and flickering torches). Completely click-through.
    Item {
      id: navbarBackdrop
      z: 0
      visible: root.backdrop !== "none" && !root.barHidden && !root.vertical
      anchors.fill: parent
      clip: true

      readonly property int slotCount: Math.max(8, Math.floor(window.width / 80))

      // Seamless 480x32 pixel-art panorama tile anchored to the bar floor.
      // Kept at tasteful atmospheric opacity (0.48) so the colorful pets and
      // bar widgets always stand out crisply in the foreground.
      Image {
        id: themePanorama
        visible: root.ready && root.backdrop !== "none"
        source: (root.ready && root.backdrop !== "none")
          ? (root.assetDir + "/theme-" + root.backdrop + ".png")
          : ""
        width: parent.width
        height: Math.min(32, parent.height)
        anchors.bottom: parent.bottom
        fillMode: Image.TileHorizontally
        smooth: parent.height !== 32
        opacity: 0.48
      }

      // Live animated effects layered over the pixel-art panorama:
      // 1. Forest: glowing drifting fireflies + softly falling woodland leaves
      Repeater {
        model: root.backdrop === "forest" ? navbarBackdrop.slotCount : 0
        Item {
          required property int index
          Rectangle {
            width: 3; height: 3; radius: 1.5
            x: index * 80 + 24 + (((root.animTick + index) & 1) ? 2 : 0)
            y: Math.max(3, (index * 7) % Math.max(6, navbarBackdrop.height - 10))
            color: "#ECFCCB"
            border.width: 0.5; border.color: "#65A30D"
            opacity: ((root.animTick + index) % 3 === 0) ? 0.9 : 0.22
          }
          Rectangle {
            visible: (index % 2) === 0
            width: 3; height: 2; radius: 1
            x: (index * 85 + ((root.animTick + index * 3) % 14)) % Math.max(80, Math.round(navbarBackdrop.width))
            y: (root.animTick + index * 5) % Math.max(8, Math.round(navbarBackdrop.height - 3))
            color: (index % 4 === 0) ? "#86EFAC" : "#FDE047"
            opacity: 0.65
          }
        }
      }

      // 2. Mountain: softly drifting alpine mist + gentle falling snowflakes
      Repeater {
        model: root.backdrop === "mountain" ? navbarBackdrop.slotCount : 0
        Item {
          required property int index
          Rectangle {
            width: 18; height: 3; radius: 1.5
            x: (index * 95 + root.animTick * 2) % Math.max(100, Math.round(navbarBackdrop.width))
            y: 4 + (index % 3) * 4
            color: "#F8FAFC"
            opacity: 0.28
          }
          Rectangle {
            width: 2; height: 2; radius: 1
            x: (index * 76 + ((root.animTick + index * 7) % 18)) % Math.max(80, Math.round(navbarBackdrop.width))
            y: (root.animTick * 2 + index * 9) % Math.max(8, Math.round(navbarBackdrop.height - 3))
            color: "#FFFFFF"
            opacity: 0.72
          }
        }
      }

      // 3. Space: twinkling starlight pulses + periodic diagonal shooting star
      Repeater {
        model: root.backdrop === "space" ? navbarBackdrop.slotCount * 2 : 0
        Rectangle {
          required property int index
          width: 2.5; height: 2.5; radius: 1.25
          x: index * 44 + ((index * 17) % 28)
          y: 3 + ((index * 9) % Math.max(6, navbarBackdrop.height - 10))
          color: (index & 1) ? "#FEF08A" : "#7DD3FC"
          opacity: ((root.animTick + index) & 1) ? 0.9 : 0.15
        }
      }
      Rectangle {
        readonly property int shootStep: root.animTick % 28
        visible: root.backdrop === "space" && shootStep < 7
        width: 14
        height: 1.5
        radius: 1
        rotation: 18
        color: "#FEF08A"
        opacity: 0.85 - shootStep * 0.11
        x: Math.round(navbarBackdrop.width * 0.18 + shootStep * 22)
        y: Math.round(2 + shootStep * 2.5)
      }

      // 4. Beach: animated whitewater surf foam along the shoreline
      Repeater {
        model: root.backdrop === "beach" ? navbarBackdrop.slotCount * 2 : 0
        Rectangle {
          required property int index
          width: 14; height: 2; radius: 1
          x: index * 40 + (((root.animTick + index) & 1) ? 3 : 0)
          y: navbarBackdrop.height - 5
          color: "#ECFEFF"
          opacity: ((root.animTick + index) & 1) ? 0.85 : 0.45
        }
      }

      // 5. Castle: flickering wall torches between battlements
      Repeater {
        model: root.backdrop === "castle" ? Math.max(4, Math.floor(window.width / 80)) : 0
        Rectangle {
          required property int index
          width: 4; height: ((root.animTick + index) & 1) ? 6 : 5
          radius: 2
          x: index * 80 + 54
          y: navbarBackdrop.height - 13
          color: ((root.animTick + index) & 1) ? "#FEF08A" : "#F97316"
          border.width: 1; border.color: "#7C2D12"
          opacity: 0.9
        }
      }
    }

    // Small clickable "Food Dot" on the bar: left-click drops food for the
    // animals to eat; right-click opens the pet picker menu.
    Item {
      id: feederHitBox
      z: 4
      visible: root.showFoodDot && !root.barHidden
      width: 18
      height: 18
      x: root.vertical
        ? Math.round(window.stripCentre - width / 2)
        : Math.round(root.feederPos - width / 2)
      y: root.vertical
        ? Math.round(root.feederPos - height / 2)
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
          width: 3
          height: 3
          radius: 1.5
          x: 2
          y: 2
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
            catMenu.anchorPos = root.feederPos
            catMenu.open = true
            return
          }
          root.dropFood()
        }
      }
    }

    // Dropped food treat on the bar floor, tailored to the active pets' species
    // (fish, bone, cheese, bamboo, apple, berry, or magic star) and shrinking
    // with animated crumbs as the winning animal munches it.
    Item {
      id: droppedFoodItem
      z: 1
      visible: root.foodActive && !root.barHidden
      readonly property real scaleFactor: 0.4 + 0.6 * root.foodAmount
      readonly property int baseW: root.foodKind === "bone" || root.foodKind === "fish" ? 16 : 13
      readonly property int baseH: root.foodKind === "bamboo" ? 15 : 12
      width: Math.max(6, Math.round(baseW * scaleFactor))
      height: Math.max(6, Math.round(baseH * scaleFactor))
      x: root.vertical
        ? Math.round(window.stripCentre - width / 2)
        : Math.round(root.foodPos - width / 2)
      y: root.vertical
        ? Math.round(root.foodPos - height / 2)
        : Math.max(0, Math.round(root.barSize - height - 1))

      // Fish treat (Cats)
      Item {
        visible: root.foodKind === "fish"
        anchors.fill: parent
        Rectangle {
          width: Math.max(5, parent.width - 4)
          height: Math.max(4, parent.height - 2)
          anchors.verticalCenter: parent.verticalCenter
          x: 0
          radius: height / 2
          color: (root.animTick & 1) ? "#38BDF8" : "#0EA5E9"
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
        visible: root.foodKind === "bone"
        anchors.fill: parent
        Rectangle {
          width: 5; height: Math.max(5, parent.height - 2)
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          radius: 2.5
          color: "#FEF3C7"
          border.width: 1.2; border.color: "#78350F"
        }
        Rectangle {
          width: 5; height: Math.max(5, parent.height - 2)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          radius: 2.5
          color: "#FEF3C7"
          border.width: 1.2; border.color: "#78350F"
        }
        Rectangle {
          width: Math.max(4, parent.width - 4)
          height: Math.max(4, Math.round(parent.height * 0.52))
          anchors.centerIn: parent
          radius: 1.5
          color: "#FFFBEB"
          border.width: 1.2; border.color: "#78350F"
        }
      }

      // Cheese wedge (Rats)
      Rectangle {
        visible: root.foodKind === "cheese"
        anchors.fill: parent
        radius: 3
        color: "#FACC15"
        border.width: 1.4
        border.color: "#713F12"
        Rectangle {
          width: 3; height: 3; radius: 1.5
          x: 2; y: 2
          color: "#CA8A04"
        }
        Rectangle {
          width: 2; height: 2; radius: 1
          anchors.right: parent.right; anchors.bottom: parent.bottom
          anchors.margins: 2
          color: "#CA8A04"
        }
      }

      // Bamboo shoot (Pandas)
      Item {
        visible: root.foodKind === "bamboo"
        anchors.fill: parent
        Rectangle {
          width: Math.max(5, Math.round(parent.width * 0.58))
          height: parent.height
          anchors.horizontalCenter: parent.horizontalCenter
          radius: 2
          color: "#4ADE80"
          border.width: 1.2
          border.color: "#14532D"
          Rectangle {
            width: parent.width; height: 1.5
            y: Math.round(parent.height * 0.48)
            color: "#166534"
          }
        }
        Rectangle {
          width: 4; height: 3; radius: 1.5
          anchors.right: parent.right
          y: 2
          color: "#22C55E"
          border.width: 1; border.color: "#14532D"
        }
      }

      // Crisp Apple / Berry (Horses & Birds)
      Item {
        visible: root.foodKind === "apple" || root.foodKind === "berry"
        anchors.fill: parent
        Rectangle {
          width: parent.width
          height: Math.max(5, parent.height - 2)
          anchors.bottom: parent.bottom
          radius: width / 2
          color: root.foodKind === "berry" ? "#E11D48" : "#EF4444"
          border.width: 1.3
          border.color: "#450A0A"
          Rectangle {
            width: 3; height: 3; radius: 1.5
            x: 2; y: 2
            color: "#FECDD3"
          }
        }
        Rectangle {
          width: 4; height: 3; radius: 1.5
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          color: "#22C55E"
          border.width: 1; border.color: "#14532D"
        }
      }

      // Magic Star Crystal (Fairy-tale creatures)
      Item {
        visible: root.foodKind === "star"
        anchors.fill: parent
        Rectangle {
          width: Math.max(6, parent.width - 2)
          height: width
          anchors.centerIn: parent
          rotation: 45
          radius: 2
          color: (root.animTick & 1) ? "#FDE047" : "#C084FC"
          border.width: 1.3
          border.color: "#4C1D95"
          Rectangle {
            width: 3; height: 3; radius: 1.5
            anchors.centerIn: parent
            color: "#FFFFFF"
          }
        }
      }

      // Animated munching crumbs while the winning pet eats the treat.
      Repeater {
        model: root.foodEating ? 3 : 0
        Rectangle {
          required property int index
          width: 2.5
          height: 2.5
          radius: 1.25
          color: (index === 0) ? "#FDE047" : "#FB923C"
          x: Math.round(droppedFoodItem.width / 2 + ((index - 1) * 5) + (((root.animTick + index) & 1) ? 1 : -1))
          y: Math.round(droppedFoodItem.height * 0.2 - (((root.animTick + index) & 1) ? 3 : 0))
        }
      }
    }

    // Bouncing pixel tennis ball toy tossed when Play is clicked!
    Item {
      id: playBallItem
      z: 2
      visible: root.ballActive && !root.barHidden && !root.vertical
      width: 10
      height: 10
      x: Math.round(root.ballPos - width / 2)
      y: Math.max(0, Math.round(root.barSize - height - 2 - root.ballY))

      // Ground shadow that shrinks as the ball bounces higher
      Rectangle {
        width: Math.max(4, Math.round(8 - root.ballY * 0.25))
        height: 2
        radius: 1
        color: "#000000"
        opacity: Math.max(0.08, 0.28 - root.ballY * 0.012)
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.round(parent.height + root.ballY)
      }

      // Neon-lime pixel tennis ball with seam stripe & highlight
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: "#A3E635"
        border.width: 1.3
        border.color: "#365314"

        Rectangle {
          width: parent.width - 3
          height: 1.5
          anchors.centerIn: parent
          rotation: (root.ballPos * 4) % 360
          color: "#FEFCE8"
        }

        Rectangle {
          width: 2.5
          height: 2.5
          radius: 1.25
          x: 2
          y: 1.5
          color: "#FFFFFF"
        }
      }
    }

    Repeater {
      id: petRepeater
      model: root.characters
      onCountChanged: {
        root.maskRevision++
        Qt.callLater(root.step)
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
        readonly property bool maskActive: !root.barHidden && (catSettled || hovered)
        property alias hitBox: hitBoxItem

        onMaskActiveChanged: root.maskRevision++
        Component.onCompleted: {
          var existing = root._actors[modelData]
          if (existing) {
            catPos = existing.pos
            catPose = existing.pose
            catBob = existing.bob
            catLift = existing.lift
            catSettled = existing.settled
            animOffset = existing.animOffset
          }
          root.maskRevision++
        }

        // Ground all land animals directly on the bottom floor of the navbar so
        // horses, cats, dogs, rats, pandas, and unicorns walk solidly on the
        // ground; only birds take flight above the floor while moving.
        readonly property real wingLift: petItem.isFlying
          ? (((root.animTick + petItem.animOffset) & 1) ? 3 : 2)
          : 0
        readonly property real hopUp: Math.round(petItem.catLift * (petItem.isBird ? 3 : 2)) + wingLift
        readonly property int bobOffset: petItem.catBob ? (((root.animTick + petItem.animOffset) & 1) ? -1 : 0) : 0
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
          height: 3
          radius: 1.5
          color: "#000000"
          opacity: petItem.isFlying ? 0.14 : 0.22
          x: Math.round(sprite.x + (sprite.width - width) / 2)
          y: Math.max(0, root.barSize - 3)
        }

        // Subtle gallop dust puffs behind sprinting land animals
        Item {
          visible: !root.vertical && petItem.isSprinting && !petItem.isBird
            && (petItem.catPose === "left" || petItem.catPose === "right")
          readonly property int trailDir: petItem.catPose === "right" ? -1 : 1
          Rectangle {
            width: 3; height: 3; radius: 1.5
            color: "#E7E5E4"
            opacity: ((root.animTick + petItem.animOffset) & 1) ? 0.65 : 0.25
            x: Math.round(sprite.x + (parent.trailDir < 0 ? -3 : sprite.width + 1))
            y: Math.max(0, root.barSize - 4)
          }
          Rectangle {
            width: 2; height: 2; radius: 1
            color: "#D6D3D1"
            opacity: ((root.animTick + petItem.animOffset) & 1) ? 0.30 : 0.60
            x: Math.round(sprite.x + (parent.trailDir < 0 ? -7 : sprite.width + 5))
            y: Math.max(0, root.barSize - 6)
          }
        }

        // Fairy sparkle dust trailing gently behind a moving Fairy
        Item {
          visible: !root.vertical && petItem.isFairyPixie && !petItem.catSettled
            && (petItem.catPose === "left" || petItem.catPose === "right")
          readonly property int trailDir: petItem.catPose === "right" ? -1 : 1
          Rectangle {
            width: 2.5; height: 2.5; radius: 1.25
            color: ((root.animTick + petItem.animOffset) & 1) ? "#FEF08A" : "#67E8F9"
            opacity: 0.9
            x: Math.round(sprite.x + (parent.trailDir < 0 ? -4 : sprite.width + 2))
            y: Math.max(1, Math.round(sprite.y + sprite.height * 0.45))
          }
          Rectangle {
            width: 2; height: 2; radius: 1
            color: "#F9A8D4"
            opacity: ((root.animTick + petItem.animOffset) & 1) ? 0.45 : 0.85
            x: Math.round(sprite.x + (parent.trailDir < 0 ? -8 : sprite.width + 6))
            y: Math.max(1, Math.round(sprite.y + sprite.height * 0.28))
          }
        }

        // Tiny warm fire embers flickering behind a sprinting Dragon
        Rectangle {
          visible: !root.vertical && petItem.isDragon && petItem.isSprinting
            && (petItem.catPose === "left" || petItem.catPose === "right")
          width: 3; height: 3; radius: 1.5
          color: ((root.animTick + petItem.animOffset) & 1) ? "#FDE047" : "#FB923C"
          opacity: 0.9
          x: Math.round(sprite.x + (petItem.catPose === "right" ? sprite.width + 1 : -4))
          y: Math.max(1, Math.round(sprite.y + sprite.height * 0.42))
        }

        CatSprite {
          id: sprite

          width: root.catSize
          height: root.catSize
          devicePixels: root.catSize * (root.catScreen ? root.catScreen.devicePixelRatio : 1)
          assetDir: root.assetDir
          character: petItem.modelData

          pose: petItem.catPose
          animTick: (root.animTick + petItem.animOffset) & 0xff
          fillColor: Color.bar.text
          inkColor: Color.bar.background

          x: root.vertical ? Math.round(petItem.crossPos) : Math.round(petItem.catPos)
          y: root.vertical ? Math.round(petItem.catPos) : Math.round(petItem.crossPos)
        }

        // Floating music notes while dancing to active media playback.
        Text {
          visible: petItem.isDancing && !petItem.showHeart && !petItem.showAlert
          readonly property int mPhase: (root.animTick + petItem.animOffset) & 1
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
          readonly property int zPhase: (root.animTick + petItem.animOffset) % 3
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

        // Brief "!" alert when spotting freshly dropped food.
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

        // Tiny floating heart when petted or after winning a food treat.
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
                catMenu.anchorPos = root.vertical
                  ? sprite.y + sprite.height / 2
                  : sprite.x + sprite.width / 2
                catMenu.open = true
                return
              }
              if (root.pettable) {
                var actor = root._ensureActor(petItem.modelData, petItem.index, Math.max(0, root.barLength - root.catSize))
                var now = Date.now()
                actor.pettedAt = now
                actor.heartUntil = now + 1000
                root.nudge()
              }
            }
          }
        }
      }
    }
  }
}
