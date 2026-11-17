// The pet's right-click menu.
//
// A full-screen transparent layer with a compact picker card near the pet.
// Full-screen makes click-anywhere-to-dismiss work without taking keyboard
// focus away from whatever window you are using.

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Frames.js" as Frames

PanelWindow {
  id: menu

  property var cat: null
  property bool open: false
  property real anchorPos: 0

  signal chose(string key, var value)

  visible: open && cat !== null
  screen: cat ? cat.catScreen : null
  color: "transparent"

  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "navbar-cat-menu"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors { top: true; bottom: true; left: true; right: true }

  mask: Region {
    item: menu.open ? dismissArea : null
  }

  MouseArea {
    id: dismissArea
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: menu.open = false
  }

  // Currently active character list on the bar.
  readonly property var activeCharacters: {
    if (!menu.cat) return ["neko"]
    var list = menu.cat.characters
    if (Array.isArray(list) && list.length > 0) return list
    return [String(menu.cat.character || "neko")]
  }

  // Group catalog entries by species while preserving catalog order.
  readonly property var groups: {
    var order = []
    var byName = {}
    var list = Frames.CATALOG || []
    for (var i = 0; i < list.length; i++) {
      var item = list[i]
      if (!byName[item.group]) {
        byName[item.group] = { name: item.group, items: [] }
        order.push(byName[item.group])
      }
      byName[item.group].items.push(item)
    }
    return order
  }

  component PlainText: Text {
    textFormat: Text.PlainText
    color: Color.popups.text
    font.family: Style.fontFamily
    font.pixelSize: Style.font.size ? Style.font.size : 12
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property string characterId: ""
    property bool active: false
    property color activeColor: "#2563EB"
    signal tapped()

    implicitWidth: chipRow.implicitWidth + Style.space(12)
    implicitHeight: Math.max(chipRow.implicitHeight + Style.space(8), Style.space(26))
    radius: Style.cornerRadius
    border.width: 0
    color: chip.active
      ? (chipMouse.containsMouse ? Qt.lighter(chip.activeColor, 1.08) : chip.activeColor)
      : (chipMouse.containsMouse ? Qt.rgba(0.5, 0.5, 0.5, 0.15) : "transparent")

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Style.space(5)

      CatSprite {
        visible: chip.characterId !== ""
        width: 16
        height: 16
        anchors.verticalCenter: parent.verticalCenter
        devicePixels: 16 * (menu.cat && menu.cat.catScreen ? menu.cat.catScreen.devicePixelRatio : 1)
        assetDir: (menu.open && menu.cat && chip.characterId !== "") ? menu.cat.assetDir : ""
        character: chip.characterId !== "" ? chip.characterId : "neko"
        pose: "stop"
        fillColor: chip.active ? "#FFFFFF" : Color.popups.text
        inkColor: chip.active ? chip.activeColor : Color.popups.background
      }

      PlainText {
        anchors.verticalCenter: parent.verticalCenter
        text: chip.label
        color: chip.active ? "#FFFFFF" : Color.popups.text
        font.bold: chip.active
        opacity: chip.active ? 1.0 : 0.78
        font.pixelSize: (Style.font.size ? Style.font.size : 12) - 1
      }
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.tapped()
    }
  }

  component ToggleRow: Rectangle {
    id: row
    property string label: ""
    property bool active: false
    signal tapped()

    implicitWidth: parent ? parent.width : Style.space(240)
    implicitHeight: rowText.implicitHeight + Style.space(8)
    radius: Style.cornerRadius
    color: rowMouse.containsMouse ? Qt.rgba(0.5, 0.5, 0.5, 0.14) : "transparent"

    PlainText {
      id: rowText
      x: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: (row.active ? "● " : "○ ") + row.label
      color: Color.popups.text
      font.bold: row.active
      opacity: row.active ? 1.0 : 0.65
    }

    MouseArea {
      id: rowMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: row.tapped()
    }
  }

  Rectangle {
    id: card

    readonly property int pad: Style.space(10)
    readonly property bool vertical: menu.cat ? menu.cat.vertical : false
    readonly property int barSize: menu.cat ? menu.cat.barSize : 26
    readonly property int maxCardHeight: Math.max(200, menu.height - Style.space(20))

    color: Color.popups.background
    border.color: Color.popups.border
    border.width: 1
    radius: Style.cornerRadius
    implicitWidth: column.implicitWidth + pad * 2
    implicitHeight: Math.min(column.implicitHeight + pad * 2, maxCardHeight)
    width: implicitWidth
    height: implicitHeight

    x: vertical
      ? Math.min(menu.width - width - Style.space(8),
          menu.cat && menu.cat.barPosition === "left" ? barSize + Style.space(6)
            : menu.width - width - barSize - Style.space(6))
      : Math.max(Style.space(8),
          Math.min(menu.width - width - Style.space(8), menu.anchorPos - width / 2))
    y: vertical
      ? Math.max(Style.space(8), Math.min(menu.height - height - Style.space(8), menu.anchorPos))
      : (menu.cat && menu.cat.barPosition === "bottom"
          ? menu.height - height - barSize - Style.space(6)
          : barSize + Style.space(6))

    // Absorb stray clicks on card padding so they don't dismiss unintentionally.
    MouseArea {
      z: -1
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
    }

    Flickable {
      anchors.fill: parent
      anchors.margins: card.pad
      contentWidth: column.implicitWidth
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: column
        spacing: Style.space(6)

        Row {
          spacing: Style.space(6)

          PlainText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Navbar Pets (" + menu.activeCharacters.length + " active)"
            opacity: 0.65
          }

          Chip {
            label: "● Give Food"
            active: true
            activeColor: "#EA580C"
            onTapped: {
              menu.chose("dropFood", "")
              menu.open = false
            }
          }

          Chip {
            visible: menu.activeCharacters.length > 1
            label: "Play"
            active: true
            activeColor: "#7C3AED"
            onTapped: {
              menu.chose("startPlay", 8500)
              menu.open = false
            }
          }

          Chip {
            visible: menu.activeCharacters.length > 1
            label: "Keep 1"
            onTapped: menu.chose("onlyOneCharacter", "")
          }
        }

        Repeater {
          model: menu.groups

          Column {
            id: groupCol
            required property var modelData
            spacing: Style.space(3)
            width: Math.max(chipGrid.implicitWidth, Style.space(260))

            PlainText {
              text: groupCol.modelData.name
              opacity: 0.48
              font.pixelSize: Math.max(9, (Style.font.size ? Style.font.size : 12) - 2)
            }

            Grid {
              id: chipGrid
              columns: 3
              columnSpacing: Style.space(4)
              rowSpacing: Style.space(4)

              Repeater {
                model: groupCol.modelData.items

                Chip {
                  required property var modelData
                  label: modelData.label
                  characterId: modelData.id
                  active: menu.activeCharacters.indexOf(modelData.id) !== -1
                  onTapped: {
                    menu.chose("toggleCharacter", modelData.id)
                  }
                }
              }
            }
          }
        }

        Rectangle {
          width: parent.width
          height: 1
          color: Color.popups.border
          opacity: 0.4
        }

        Column {
          spacing: Style.space(3)

          PlainText {
            text: "Navbar Theme"
            opacity: 0.48
            font.pixelSize: Math.max(9, (Style.font.size ? Style.font.size : 12) - 2)
          }

          Grid {
            columns: 3
            columnSpacing: Style.space(4)
            rowSpacing: Style.space(4)

            Repeater {
              model: [
                { label: "None", val: "none" },
                { label: "Forest", val: "forest" },
                { label: "Mountain", val: "mountain" },
                { label: "Space", val: "space" },
                { label: "Beach", val: "beach" },
                { label: "Castle", val: "castle" }
              ]

              Chip {
                required property var modelData
                label: modelData.label
                activeColor: "#2563EB"
                active: (menu.cat ? menu.cat.backdrop : "none") === modelData.val
                onTapped: {
                  menu.chose("backdrop", modelData.val)
                }
              }
            }
          }
        }

        Row {
          spacing: Style.space(4)

          PlainText {
            anchors.verticalCenter: parent.verticalCenter
            text: "Size"
            opacity: 0.55
            rightPadding: Style.space(4)
          }

          Repeater {
            model: [16, 20, 24, 32]

            Chip {
              required property int modelData
              label: modelData + "px"
              activeColor: "#0D9488"
              active: menu.cat && menu.cat.catSize === modelData
              onTapped: {
                menu.chose("size", modelData)
                menu.open = false
              }
            }
          }
        }

        ToggleRow {
          width: parent.width
          label: "food dot on bar"
          active: menu.cat && menu.cat.showFoodDot
          onTapped: {
            menu.chose("foodDot", !(menu.cat && menu.cat.showFoodDot))
          }
        }

        ToggleRow {
          width: parent.width
          label: "auto play together"
          active: menu.cat && menu.cat.autoPlay
          onTapped: {
            menu.chose("autoPlay", !(menu.cat && menu.cat.autoPlay))
          }
        }

        ToggleRow {
          width: parent.width
          label: "pounce"
          active: menu.cat && menu.cat.pounce
          onTapped: {
            menu.chose("pounce", !(menu.cat && menu.cat.pounce))
            menu.open = false
          }
        }

        ToggleRow {
          width: parent.width
          label: "chase cursor"
          active: menu.cat && menu.cat.chaseCursor
          onTapped: {
            menu.chose("chaseCursor", !(menu.cat && menu.cat.chaseCursor))
            menu.open = false
          }
        }
      }
    }
  }
}
