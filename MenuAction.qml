import QtQuick
import qs.Commons

Item {
  id: root

  property string label: ""
  signal chosen()

  implicitHeight: Math.round(Style.space(30))

  Rectangle {
    id: hoverBg
    anchors.fill: parent
    radius: Style.cornerRadius
    color: "transparent"
  }

  Text {
    id: labelText
    anchors.verticalCenter: parent.verticalCenter
    anchors.left: parent.left
    anchors.leftMargin: Math.round(Style.spacing.md)
    anchors.right: parent.right
    anchors.rightMargin: Math.round(Style.spacing.md)
    text: root.label
    color: Color.popups.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onEntered: hoverBg.color = Util.alpha(Color.foreground, 0.10)
    onExited: hoverBg.color = "transparent"
    onClicked: root.chosen()
  }
}