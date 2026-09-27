import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Raytube cast menu: pick a TV (Apple TV over AirPlay, or a Chromecast), choose
// whether to cast the laptop screen or the virtual TV desktop, and drive the TV
// desktop's scenes, layouts and rotation. Everything is done by the raytube
// command-line tools (`raytube-cast`, `raytube-tv`); this panel only calls them.
Panel {
  id: root
  moduleName: "nathank.raytube"
  // The base Panel registers open/close/show/hide/toggle on this IPC target:
  //   omarchy-shell nathank.raytube toggle
  ipcTarget: "nathank.raytube"

  readonly property string projectUrl: "github.com/<owner>/raytube"

  // The bar facade can be briefly null while the shell hot-reloads plugins.
  readonly property color fg: root.bar ? root.bar.foreground : Color.foreground
  readonly property string fontFamily: root.bar ? root.bar.fontFamily : Style.fontFamily

  // Whether `raytube-cast` is on PATH (-1 not checked yet, 0 no, 1 yes).
  property int toolsState: -1
  readonly property bool toolsInstalled: toolsState === 1
  // Set once the first `raytube-cast list` has finished (discovery takes ~2 s).
  property bool listLoaded: false

  // Receivers from `raytube-cast list` ({name, ip, paired, kind}; kind is
  // "airplay" or "cast" for Chromecasts) and the receiver currently being
  // cast to ("" when not casting).
  property var castDevices: []
  property string castTarget: ""
  // What gets cast: "mirror" (the laptop screen) or "desktop" (the virtual TV
  // desktop from raytube-tv), from `raytube-cast mode`.
  property string castMode: "mirror"
  // Sound sync for the AirPlay TV being cast to: audio delay in ms (-1 unknown).
  property int avDelay: -1
  // Picture size for the AirPlay TV being cast to ("1920x1080", "1280x720").
  property string castSize: ""
  readonly property var castingDevice: {
    for (var i = 0; i < root.castDevices.length; i++)
      if (root.castDevices[i].ip === root.castTarget) return root.castDevices[i]
    return null
  }
  // `raytube-tv json`: the virtual TV desktop's scenes, layout and rotation.
  property var tvState: ({ up: false, scenes: [] })
  readonly property var tvCurrent: {
    var list = root.tvState.scenes || []
    for (var i = 0; i < list.length; i++) if (list[i].current) return list[i]
    return null
  }

  // Keyboard cursor: j/k walks the receiver rows, Enter starts/stops a cast.
  property int selectedIndex: 0
  property bool cursorActive: false

  function moveCursor(delta) {
    if (castDevices.length === 0) return
    var next = selectedIndex + delta
    if (next < 0) next = 0
    if (next > castDevices.length - 1) next = castDevices.length - 1
    selectedIndex = next
  }

  function activateCursor() {
    if (selectedIndex >= 0 && selectedIndex < castDevices.length)
      toggleCast(castDevices[selectedIndex])
  }

  function clampCursor() {
    if (selectedIndex > castDevices.length - 1) selectedIndex = Math.max(0, castDevices.length - 1)
    if (selectedIndex < 0) selectedIndex = 0
  }

  // Keep the keyboard-focused row inside the viewport when the panel scrolls.
  function ensureCursorVisible(item) {
    if (!item || !scrollArea) return
    var flick = scrollArea.contentItem
    if (!flick || flick.contentY === undefined) return
    var pt = item.mapToItem(flick.contentItem || flick, 0, 0)
    var top = pt.y
    var bottom = top + (item.height || 0)
    var viewTop = flick.contentY
    var viewBottom = viewTop + flick.height
    var margin = 6
    if (top < viewTop + margin) flick.contentY = Math.max(0, top - margin)
    else if (bottom > viewBottom - margin)
      flick.contentY = bottom + margin - flick.height
  }

  function refresh() {
    if (!toolsProc.running) toolsProc.running = true
  }

  function refreshAvDelay() {
    if (!root.toolsInstalled || !root.castTarget) return
    if (!avDelayProc.running) {
      avDelayProc.command = ["raytube-cast", "av-delay", root.castTarget]
      avDelayProc.running = true
    }
    if (!castSizeProc.running) {
      castSizeProc.command = ["raytube-cast", "size", root.castTarget]
      castSizeProc.running = true
    }
  }

  function refreshCast() {
    if (!root.toolsInstalled) return
    refreshAvDelay()
    if (!castListProc.running) castListProc.running = true
    if (!castStatusProc.running) castStatusProc.running = true
    if (!castModeProc.running) castModeProc.running = true
    if (!tvProc.running) tvProc.running = true
  }

  // TV sound on/off: mutes only what the TV receives (the laptop and
  // headphones keep playing). Read from `raytube-cast tv-sound`.
  property bool tvSound: true
  function refreshTvSound() {
    if (!root.castTarget || tvSoundProc.running) return
    tvSoundProc.command = ["raytube-cast", "tv-sound"]
    tvSoundProc.running = true
  }
  function toggleTvSound() {
    if (!root.castTarget || tvSoundProc.running) return
    root.tvSound = !root.tvSound
    tvSoundProc.command = ["raytube-cast", "tv-sound", root.tvSound ? "on" : "off"]
    tvSoundProc.running = true
  }

  // Restart the cast session: a fresh session always starts in sync.
  function resyncCast() {
    if (!root.castTarget || castActionProc.running) return
    castActionProc.command = ["raytube-cast", "resync"]
    castActionProc.running = true
  }

  // Picture size for the AirPlay TV; restarts the cast at that size.
  function setCastSize(size) {
    if (!root.castTarget || castActionProc.running) return
    root.castSize = size
    castActionProc.command = ["raytube-cast", "size", root.castTarget, size]
    castActionProc.running = true
  }

  // Nudge the sound later (+) or earlier (-); the cast picks it up live.
  function stepAvDelay(ms) {
    if (!root.castTarget || avStepProc.running) return
    if (root.avDelay >= 0) root.avDelay = Math.max(0, root.avDelay + ms)
    avStepProc.command = ["raytube-cast", "av-delay-step", String(ms)]
    avStepProc.running = true
  }

  function tvCommand(args) {
    if (castActionProc.running) return
    castActionProc.command = ["raytube-tv"].concat(args)
    castActionProc.running = true
  }

  function setCastMode(mode) {
    if (mode === root.castMode || castActionProc.running) return
    root.castMode = mode
    castActionProc.command = ["raytube-cast", "mode", mode]
    castActionProc.running = true
  }

  function toggleCast(device) {
    if (!device || castActionProc.running) return
    // Optimistic: reflect the change now; the status poll confirms it.
    root.castTarget = root.castTarget === device.ip ? "" : device.ip
    castActionProc.command = ["raytube-cast", "toggle", device.ip, device.name]
    castActionProc.running = true
  }

  function statusText() {
    if (root.toolsState === 0) return "TOOLS NOT INSTALLED"
    if (root.castingDevice) return ("CASTING TO " + root.castingDevice.name).toUpperCase()
    if (root.castTarget !== "") return "CASTING"
    return "NOT CASTING"
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    if (opened) {
      refresh()
      selectedIndex = 0
      cursorActive = false
    }
  }

  onCastDevicesChanged: clampCursor()

  // Poll while the panel is open.
  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  // Keep the bar icon honest while the panel is closed (cheap: no discovery).
  Timer {
    interval: 10000
    running: root.toolsInstalled
    repeat: true
    onTriggered: if (!castStatusProc.running) castStatusProc.running = true
  }

  // The cast unit starts asynchronously; confirm its state shortly after.
  Timer {
    id: castRefreshDelay
    interval: 1500
    repeat: false
    onTriggered: root.refreshCast()
  }

  // Is raytube installed? Every other process is gated on this.
  Process {
    id: toolsProc
    command: ["sh", "-c", "command -v raytube-cast >/dev/null 2>&1 && echo yes || echo no"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.toolsState = String(text || "").trim() === "yes" ? 1 : 0
        if (root.toolsInstalled) root.refreshCast()
      }
    }
  }

  // `raytube-cast list`: name<TAB>ip<TAB>paired|unpaired<TAB>airplay|cast.
  Process {
    id: castListProc
    command: ["raytube-cast", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var devices = []
        var lines = String(text || "").split("\n")
        for (var i = 0; i < lines.length; i++) {
          var f = lines[i].split("\t")
          if (f.length >= 2 && f[1]) devices.push({ name: f[0], ip: f[1], paired: f[2] === "paired", kind: f[3] || "airplay" })
        }
        root.castDevices = devices
        root.listLoaded = true
      }
    }
  }

  Process {
    id: castModeProc
    command: ["raytube-cast", "mode"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.castMode = String(text || "").trim() === "desktop" ? "desktop" : "mirror"
    }
  }

  Process {
    id: tvProc
    command: ["sh", "-c", "command -v raytube-tv >/dev/null 2>&1 && raytube-tv json || echo '{}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { root.tvState = JSON.parse(String(text || "{}")) } catch (e) { root.tvState = { up: false, scenes: [] } }
      }
    }
  }

  Process {
    id: avDelayProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = parseInt(String(text || "").trim())
        root.avDelay = isNaN(v) ? -1 : v
      }
    }
  }

  Process {
    id: castSizeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.castSize = String(text || "").trim()
    }
  }

  Process {
    id: avStepProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) root.refreshAvDelay()
  }

  // `raytube-cast status`: "on<TAB>ip<TAB>name[<TAB>mode]" or "off".
  Process {
    id: tvSoundProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.tvSound = String(text || "").trim().indexOf("off") !== 0
    }
  }

  Process {
    id: castStatusProc
    command: ["raytube-cast", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var f = String(text || "").trim().split("\t")
        root.castTarget = f[0] === "on" && f.length > 1 ? f[1] : ""
        root.refreshAvDelay()
        root.refreshTvSound()
      }
    }
  }

  Process {
    id: castActionProc
    stdout: StdioCollector { waitForEnd: true }
    onRunningChanged: if (!running) { if (!tvProc.running) tvProc.running = true; castRefreshDelay.restart() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Cast-connected while casting, plain cast glyph otherwise.
    text: root.castTarget !== "" ? "󰄙" : "󰄘"
    onPressed: function(b) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        if (dy !== 0) root.moveCursor(dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          // ---------- Hero: cast icon · title/status ----------
          Item {
            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

            Text {
              id: heroIcon
              textFormat: Text.PlainText
              text: root.castTarget !== "" ? "󰄙" : "󰄘"
              color: root.fg
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroIcon.right
              anchors.leftMargin: Style.space(14)
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                text: "Raytube"
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                textFormat: Text.PlainText
                text: root.statusText()
                color: Qt.darker(root.fg, 1.4)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
                width: parent.width
              }
            }
          }

          PanelSeparator {
            foreground: root.fg
          }

          // ---------- Tools missing ----------
          Text {
            visible: root.toolsState === 0
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: "raytube tools not installed: see " + root.projectUrl
            color: root.fg
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          // ---------- Cast ----------
          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.toolsInstalled

            PanelSectionHeader {
              text: "CAST"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Grid {
              id: castModeRow
              width: parent.width
              columns: 2
              spacing: Style.spacing.xs

              readonly property real cellWidth: (width - spacing) / 2

              Repeater {
                model: [{ mode: "mirror", label: "Screen" }, { mode: "desktop", label: "TV desktop" }]

                Button {
                  required property var modelData

                  width: castModeRow.cellWidth
                  text: modelData.label
                  fontSize: Style.font.caption
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  active: root.castMode === modelData.mode
                  onClicked: root.setCastMode(modelData.mode)
                }
              }
            }

            Text {
              visible: root.castDevices.length === 0
              width: parent.width
              textFormat: Text.PlainText
              wrapMode: Text.Wrap
              text: root.listLoaded ? "No TVs found on the network." : "Looking for TVs…"
              color: Qt.darker(root.fg, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Repeater {
              model: root.castDevices

              CastRow {
                required property var modelData
                required property int index

                width: panelColumn.width
                device: modelData
                rowIndex: index
              }
            }

            // Sound sync: the TV holds the picture longer than the sound, so the
            // sound is delayed to match. AirPlay only.
            Grid {
              id: avSyncRow
              width: parent.width
              columns: 3
              spacing: Style.spacing.xs
              visible: root.castingDevice !== null && root.castingDevice.kind === "airplay"

              readonly property real sideWidth: Math.round(width * 0.2)

              Button {
                width: avSyncRow.sideWidth
                text: "−"
                fontSize: Style.font.caption
                foreground: root.fg
                fontFamily: root.fontFamily
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                onClicked: root.stepAvDelay(-50)
              }

              Button {
                width: avSyncRow.width - 2 * avSyncRow.sideWidth - 2 * avSyncRow.spacing
                text: root.avDelay >= 0 ? "Sound sync " + root.avDelay + " ms" : "Sound sync"
                fontSize: Style.font.caption
                foreground: root.fg
                fontFamily: root.fontFamily
                verticalPadding: Style.spacing.controlPaddingY
                bordered: false
                onClicked: root.refreshAvDelay()
              }

              Button {
                width: avSyncRow.sideWidth
                text: "+"
                fontSize: Style.font.caption
                foreground: root.fg
                fontFamily: root.fontFamily
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                onClicked: root.stepAvDelay(50)
              }
            }

            // Picture size sent to the AirPlay TV (both modes). 720p and 1080p
            // stay in sync; 1440p is sharper but the TV may hold the picture back.
            Grid {
              id: castSizeRow
              width: parent.width
              columns: 3
              spacing: Style.spacing.xs
              visible: avSyncRow.visible

              readonly property real cellWidth: (width - spacing * 2) / 3

              Repeater {
                model: [{ size: "1280x720", label: "720p" }, { size: "1920x1080", label: "1080p" }, { size: "2560x1440", label: "1440p" }]

                Button {
                  required property var modelData

                  width: castSizeRow.cellWidth
                  text: modelData.label
                  fontSize: Style.font.caption
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  active: root.castSize === modelData.size
                  onClicked: root.setCastSize(modelData.size)
                }
              }
            }

            Button {
              width: parent.width
              visible: avSyncRow.visible
              text: "Re-sync TV"
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              onClicked: root.resyncCast()
            }

            Button {
              width: parent.width
              visible: root.castTarget !== ""
              text: root.tvSound ? "TV sound: on" : "TV sound: off (laptop only)"
              fontSize: Style.font.caption
              foreground: root.fg
              fontFamily: root.fontFamily
              verticalPadding: Style.spacing.controlPaddingY
              bordered: true
              active: !root.tvSound
              onClicked: root.toggleTvSound()
            }
          }

          // ---------- TV desktop ----------
          PanelSeparator {
            visible: root.toolsInstalled && root.tvState.up === true
            foreground: root.fg
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.toolsInstalled && root.tvState.up === true

            PanelSectionHeader {
              text: "TV DESKTOP"
              foreground: root.fg
              fontFamily: root.fontFamily
            }

            Grid {
              id: tvLayoutRow
              width: parent.width
              columns: 4
              spacing: Style.spacing.xs
              readonly property real cellWidth: (width - spacing * 3) / 4

              Repeater {
                model: [{ id: "full", label: "Full" }, { id: "split", label: "Split" }, { id: "pip", label: "PiP" }]
                Button {
                  required property var modelData
                  width: tvLayoutRow.cellWidth
                  text: modelData.label
                  fontSize: Style.font.caption
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  active: root.tvCurrent !== null && root.tvCurrent.layout === modelData.id
                  onClicked: root.tvCommand(["layout", modelData.id])
                }
              }

              Button {
                width: tvLayoutRow.cellWidth
                text: root.tvState.rotation ? ("↻ " + (root.tvState.next_in !== null && root.tvState.next_in !== undefined ? root.tvState.next_in + "s" : "on")) : "↻ off"
                fontSize: Style.font.caption
                foreground: root.fg
                fontFamily: root.fontFamily
                horizontalPadding: Style.spacing.sm
                verticalPadding: Style.spacing.controlPaddingY
                bordered: true
                active: root.tvState.rotation === true
                onClicked: root.tvCommand(["rotate", "toggle"])
              }
            }

            Grid {
              id: tvAppRow
              width: parent.width
              columns: 3
              spacing: Style.spacing.xs
              readonly property real cellWidth: (width - spacing * 2) / 3

              Repeater {
                model: [{ args: ["board"], label: "Board" }, { args: ["browser"], label: "Browser" }, { args: ["native"], label: "YouTube ⇄ TV app" }]
                Button {
                  required property var modelData
                  width: tvAppRow.cellWidth
                  text: modelData.label
                  fontSize: Style.font.caption
                  foreground: root.fg
                  fontFamily: root.fontFamily
                  horizontalPadding: Style.spacing.sm
                  verticalPadding: Style.spacing.controlPaddingY
                  bordered: true
                  onClicked: root.tvCommand(modelData.args)
                }
              }
            }

            Repeater {
              model: root.tvState.scenes || []

              SceneRow {
                required property var modelData
                width: panelColumn.width
                scene: modelData
              }
            }
          }

          Item {
            width: parent.width
            height: Style.space(4)
          }
        }
      }
    }
  }

  component CastRow: CursorSurface {
    id: castRow
    required property var device
    required property int rowIndex

    readonly property bool isCasting: device && root.castTarget === device.ip

    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    onHasCursorChanged: if (hasCursor) root.ensureCursorVisible(castRow)
    current: isCasting
    foreground: root.fg
    fill: Style.hoverFillFor(root.fg, Color.accent)
    currentFill: Style.selectedFillFor(root.fg, Color.accent)
    implicitHeight: castInner.implicitHeight + Style.spacing.xl

    Row {
      id: castInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        text: castRow.isCasting ? "󰄙" : "󰄘"
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: castRow.device.name
              + (castRow.device.kind === "cast" ? " · Cast" : "")
              + (castRow.isCasting ? " · casting" : (castRow.device.paired ? "" : " · pair"))
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - Style.space(22) - Style.space(14) - Style.space(16)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: castRow.isCasting ? "󰄬" : ""
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        width: Style.space(14)
        horizontalAlignment: Text.AlignRight
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.selectedIndex = castRow.rowIndex
      }
      onClicked: root.toggleCast(castRow.device)
    }
  }

  component SceneRow: CursorSurface {
    id: sceneRow
    required property var scene

    current: scene && scene.current
    foreground: root.fg
    fill: Style.hoverFillFor(root.fg, Color.accent)
    currentFill: Style.selectedFillFor(root.fg, Color.accent)
    implicitHeight: sceneInner.implicitHeight + Style.spacing.xl
    opacity: scene && scene.windows > 0 ? 1.0 : 0.55

    Row {
      id: sceneInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: sceneRow.scene.label + " · " + (sceneRow.scene.windows === 1 ? "1 window" : sceneRow.scene.windows + " windows")
        color: root.fg
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
        width: parent.width - Style.space(30) - Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        textFormat: Text.PlainText
        text: "↻"
        color: root.fg
        opacity: sceneRow.scene.rotate ? 1.0 : 0.25
        font.family: root.fontFamily
        font.pixelSize: Style.font.subtitle
        width: Style.space(30)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }
    }

    // Click the name to show the scene; click ↻ to add it to or drop it from
    // the rotation.
    MouseArea {
      anchors.fill: parent
      anchors.rightMargin: Style.space(36)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.tvCommand(["scene", sceneRow.scene.id])
    }

    MouseArea {
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.right: parent.right
      width: Style.space(36)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.tvCommand(["rotate-scene", sceneRow.scene.id, sceneRow.scene.rotate ? "off" : "on"])
    }
  }
}
