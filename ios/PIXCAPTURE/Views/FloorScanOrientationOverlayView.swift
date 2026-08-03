import SwiftUI

struct FloorScanOrientationOverlayView: View {
  enum GuidanceStyle {
    case neutral
    case warning
    case ready
  }

  struct Model {
    var roomLabel: String
    var floorLabel: String
    var roomSegments: [FloorplanSegment]
    var pathPoints: [CGPoint]
    var verifiedPoint: CGPoint?
    var currentPoint: CGPoint?
    var currentHeadingRadians: Double?
    var isTrackingLimited: Bool
    var guidanceText: String
    var guidanceStyle: GuidanceStyle
  }

  let model: Model

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 6) {
        Image(systemName: iconName)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(accentColor.opacity(0.95))
        Text("Übergang")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.white.opacity(0.92))
        Spacer(minLength: 0)
        Text("\(model.roomLabel) · \(model.floorLabel)")
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.white.opacity(0.62))
          .lineLimit(1)
      }

      Canvas { context, size in
        draw(context: &context, size: size)
      }
      .frame(width: 300, height: 236)
      .background(Color.black.opacity(0.28))
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .stroke(Color.white.opacity(0.12), lineWidth: 1)
      )

      Text(model.guidanceText)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(accentColor.opacity(model.guidanceStyle == .neutral ? 0.78 : 0.94))
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(12)
    .frame(maxWidth: 380)
    .background(Color.black.opacity(0.44))
    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 14, style: .continuous)
        .stroke(Color.white.opacity(0.14), lineWidth: 1)
    )
  }

  private var accentColor: Color {
    switch model.guidanceStyle {
    case .neutral:
      return model.isTrackingLimited ? Color.yellow : Color.white
    case .warning:
      return Color.yellow
    case .ready:
      return Color(red: 0.23, green: 0.80, blue: 0.42)
    }
  }

  private var iconName: String {
    switch model.guidanceStyle {
    case .warning:
      return "exclamationmark.triangle.fill"
    case .ready:
      return "checkmark.circle.fill"
    case .neutral:
      return model.isTrackingLimited ? "location.slash.fill" : "location.north.line.fill"
    }
  }

  private func draw(context: inout GraphicsContext, size: CGSize) {
    let margin: CGFloat = 12
    let bounds = combinedBounds()
    let width = max(bounds.maxX - bounds.minX, 1.2)
    let height = max(bounds.maxY - bounds.minY, 1.2)

    let scale = min(
      (size.width - margin * 2) / width,
      (size.height - margin * 2) / height
    )

    let origin = CGPoint(
      x: margin - bounds.minX * scale,
      y: margin + bounds.maxY * scale
    )

    drawGrid(context: &context, size: size)

    if !model.roomSegments.isEmpty {
      var room = Path()
      for seg in model.roomSegments {
        let a = map(x: seg.ax, y: seg.ay, scale: scale, origin: origin)
        let b = map(x: seg.bx, y: seg.by, scale: scale, origin: origin)
        room.move(to: a)
        room.addLine(to: b)
      }
      context.stroke(
        room,
        with: .color(Color(red: 0.22, green: 0.54, blue: 0.94).opacity(0.9)),
        style: StrokeStyle(lineWidth: 3.2, lineCap: .round, lineJoin: .round)
      )
    }

    if model.pathPoints.count >= 2 {
      var track = Path()
      let first = model.pathPoints[0]
      track.move(to: map(x: Double(first.x), y: Double(first.y), scale: scale, origin: origin))
      for point in model.pathPoints.dropFirst() {
        track.addLine(to: map(x: Double(point.x), y: Double(point.y), scale: scale, origin: origin))
      }
      context.stroke(
        track,
        with: .color(Color.white.opacity(0.55)),
        style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round, dash: [4, 3])
      )
    }

    if let verified = model.verifiedPoint {
      let point = map(x: Double(verified.x), y: Double(verified.y), scale: scale, origin: origin)
      let r: CGFloat = 4.6
      context.fill(
        Path(ellipseIn: CGRect(x: point.x - r, y: point.y - r, width: r * 2, height: r * 2)),
        with: .color(Color(red: 0.23, green: 0.80, blue: 0.42).opacity(0.98))
      )
      context.stroke(
        Path(ellipseIn: CGRect(x: point.x - 8.2, y: point.y - 8.2, width: 16.4, height: 16.4)),
        with: .color(Color(red: 0.23, green: 0.80, blue: 0.42).opacity(0.55)),
        lineWidth: 1.6
      )
    }

    if let current = model.currentPoint {
      let point = map(x: Double(current.x), y: Double(current.y), scale: scale, origin: origin)
      let currentColor: Color = {
        switch model.guidanceStyle {
        case .warning:
          return Color.yellow.opacity(0.98)
        case .ready:
          return Color(red: 0.23, green: 0.80, blue: 0.42).opacity(0.98)
        case .neutral:
          return model.isTrackingLimited ? Color.yellow.opacity(0.96) : Color.white.opacity(0.98)
        }
      }()
      let currentRadius: CGFloat = 4.3
      context.fill(
        Path(ellipseIn: CGRect(x: point.x - currentRadius, y: point.y - currentRadius, width: currentRadius * 2, height: currentRadius * 2)),
        with: .color(currentColor)
      )

      if let heading = model.currentHeadingRadians {
        let tip = orientedPoint(from: point, headingRadians: heading, length: 20)
        var arrow = Path()
        arrow.move(to: point)
        arrow.addLine(to: tip)
        context.stroke(
          arrow,
          with: .color(currentColor.opacity(0.95)),
          style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
        )

        let leftWing = orientedPoint(from: tip, headingRadians: heading + 2.55, length: 7)
        let rightWing = orientedPoint(from: tip, headingRadians: heading - 2.55, length: 7)
        var head = Path()
        head.move(to: tip)
        head.addLine(to: leftWing)
        head.move(to: tip)
        head.addLine(to: rightWing)
        context.stroke(
          head,
          with: .color(currentColor.opacity(0.95)),
          style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
        )
      }
    }
  }

  private func drawGrid(context: inout GraphicsContext, size: CGSize) {
    let columns = 6
    let rows = 5
    var path = Path()
    for index in 1..<columns {
      let x = size.width * CGFloat(index) / CGFloat(columns)
      path.move(to: CGPoint(x: x, y: 0))
      path.addLine(to: CGPoint(x: x, y: size.height))
    }
    for index in 1..<rows {
      let y = size.height * CGFloat(index) / CGFloat(rows)
      path.move(to: CGPoint(x: 0, y: y))
      path.addLine(to: CGPoint(x: size.width, y: y))
    }

    context.stroke(path, with: .color(Color.white.opacity(0.08)), lineWidth: 1)
  }

  private func map(x: Double, y: Double, scale: CGFloat, origin: CGPoint) -> CGPoint {
    CGPoint(x: origin.x + CGFloat(x) * scale, y: origin.y - CGFloat(y) * scale)
  }

  private func orientedPoint(from point: CGPoint, headingRadians: Double, length: CGFloat) -> CGPoint {
    CGPoint(
      x: point.x + CGFloat(cos(headingRadians)) * length,
      y: point.y - CGFloat(sin(headingRadians)) * length
    )
  }

  private func combinedBounds() -> (minX: CGFloat, minY: CGFloat, maxX: CGFloat, maxY: CGFloat) {
    var minX = CGFloat.greatestFiniteMagnitude
    var minY = CGFloat.greatestFiniteMagnitude
    var maxX = -CGFloat.greatestFiniteMagnitude
    var maxY = -CGFloat.greatestFiniteMagnitude

    func include(_ p: CGPoint) {
      minX = min(minX, p.x)
      minY = min(minY, p.y)
      maxX = max(maxX, p.x)
      maxY = max(maxY, p.y)
    }

    for seg in model.roomSegments {
      include(CGPoint(x: seg.ax, y: seg.ay))
      include(CGPoint(x: seg.bx, y: seg.by))
    }

    for p in model.pathPoints {
      include(p)
    }
    if let verified = model.verifiedPoint {
      include(verified)
    }
    if let current = model.currentPoint {
      include(current)
    }

    if !minX.isFinite || !minY.isFinite || !maxX.isFinite || !maxY.isFinite {
      return (0, 0, 5, 5)
    }

    return (minX, minY, maxX, maxY)
  }
}
