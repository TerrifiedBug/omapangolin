import QtQuick
import qs.Commons

// The official Pangolin mark, kept at its SVG design size and scaled as one
// item so the small bar rendering stays crisp. Source and license are in NOTICE.
Item {
  id: root

  property real iconSize: Style.font.icon
  property bool busy: false

  implicitWidth: iconSize
  implicitHeight: iconSize
  width: iconSize
  height: iconSize
  transformOrigin: Item.Center

  RotationAnimation on rotation {
    from: 0
    to: 360
    duration: 1100
    loops: Animation.Infinite
    running: root.busy
  }

  Item {
    width: 238.34422
    height: 252.7317
    anchors.centerIn: parent
    scale: Math.min(root.width / width, root.height / height)

    Image {
      anchors.fill: parent
      source: Qt.resolvedUrl("pangolin.svg")
      fillMode: Image.PreserveAspectFit
      smooth: true
      mipmap: true
    }
  }
}
