import QtQuick
import QtQuick.Shapes

// Circular progress: a full track with the elapsed share drawn over it,
// starting at twelve o'clock.
Item {
  id: ring

  property real progress: 0
  property color trackColor: "gray"
  property color fillColor: "white"
  property real thickness: 6

  readonly property real radius: (Math.min(width, height) - thickness) / 2

  Behavior on progress {
    NumberAnimation { duration: 400; easing.type: Easing.OutCubic }
  }

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: ring.trackColor
      strokeWidth: ring.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: ring.width / 2
        centerY: ring.height / 2
        radiusX: ring.radius
        radiusY: ring.radius
        startAngle: -90
        sweepAngle: 360
      }
    }

    ShapePath {
      strokeColor: ring.progress > 0 ? ring.fillColor : "transparent"
      strokeWidth: ring.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap

      PathAngleArc {
        centerX: ring.width / 2
        centerY: ring.height / 2
        radiusX: ring.radius
        radiusY: ring.radius
        startAngle: -90
        sweepAngle: 360 * Math.max(0, Math.min(1, ring.progress))
      }
    }
  }
}
