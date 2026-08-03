import Foundation
import Testing
@testable import PIXCAPTURE

struct FloorplanAutoDockTests {

  @Test("Auto-dock can override an ambiguous entry hint when another opening fits better")
  func ambiguousEntryHintDoesNotHardLockWrongOpening() {
    let previousScanId = UUID(uuidString: "1D822E0B-438C-411D-8CDC-DE3771B9E70F")!
    let newScanId = UUID(uuidString: "AAF4EB1F-1EC7-4176-9B34-15990E59D2DD")!

    let previousGeo = FloorplanSegmentsFile(
      version: 6,
      segments: [
        FloorplanSegment(ax: 6.803906679153442, ay: 0.000000476837158203125, bx: 0.3122267723083496, by: 0.8101291656494141),
        FloorplanSegment(ax: 0.3122262954711914, ay: 0.8101291656494141, bx: 0, by: 5.556276321411133),
        FloorplanSegment(ax: 6.678013563156128, ay: 1.9137039184570312, bx: 6.803907155990601, by: 0),
        FloorplanSegment(ax: 6.294953346252441, ay: 5.970391750335693, bx: 6.373547792434692, by: 4.775679886341095),
        FloorplanSegment(ax: 6.373547911643982, ay: 4.775679767131805, bx: 6.562294244766235, by: 4.788096487522125),
        FloorplanSegment(ax: 6.751070261001587, ay: 1.9185099601745605, bx: 6.67801308631897, by: 1.9137039184570312),
        FloorplanSegment(ax: 0.000000476837158203125, ay: 5.556276321411133, bx: 6.294953107833862, by: 5.970391750335693),
        FloorplanSegment(ax: 6.562294006347656, ay: 4.788096606731415, bx: 6.751070499420166, by: 1.9185099601745605)
      ],
      metrics: FloorplanMetrics(
        perimeterMeters: 23.86029323963112,
        widthMeters: 6.803907155990601,
        depthMeters: 5.970391750335693,
        areaSqmApprox: 34.77828538518762
      ),
      doors: [
        FloorplanSegment(ax: 3.5475059151649475, ay: 5.789650082588196, bx: 4.4781323075294495, by: 5.850871682167053)
      ],
      openings: [
        FloorplanSegment(ax: 6.603107929229736, ay: 4.167683959007263, bx: 6.707828521728516, by: 2.5758272409439087)
      ],
      windows: [
        FloorplanSegment(ax: 3.007434129714966, ay: 0.47378087043762207, bx: 1.5728881359100342, by: 0.6528050899505615),
        FloorplanSegment(ax: 6.3547059297561646, ay: 0.05605816841125488, bx: 5.19547712802887, by: 0.20072388648986816)
      ],
      entryPassageHint: FloorplanEntryPassageHint(kind: "door", index: 0),
      previousRoomExitPassageHint: nil,
      trackingSessionId: nil,
      worldOffsetX: -4.378596782684326,
      worldOffsetY: -3.991147518157959
    )

    let newGeo = FloorplanSegmentsFile(
      version: 6,
      segments: [
        FloorplanSegment(ax: 2.473088502883911, ay: 6.519710540771484, bx: 7.847999095916748, by: 2.0488314628601074),
        FloorplanSegment(ax: 7.847999572753906, ay: 2.048831582069397, bx: 3.621027946472168, by: 0.00000011920928955078125),
        FloorplanSegment(ax: 2.2633612155914307, ay: 6.267576694488525, bx: 2.473088502883911, by: 6.519711017608643),
        FloorplanSegment(ax: 2.0807456970214844, ay: 6.419476509094238, bx: 2.2633614540100098, by: 6.267576217651367),
        FloorplanSegment(ax: 2.163602113723755, ay: 1.987967163324356, bx: 1.5179121494293213, by: 2.8559200763702393),
        FloorplanSegment(ax: 3.621027708053589, ay: 0, bx: 0, by: 4.8674774169921875),
        FloorplanSegment(ax: 0, ay: 4.867477893829346, bx: 2.0807454586029053, by: 6.4194769859313965)
      ],
      metrics: FloorplanMetrics(
        perimeterMeters: 21.99837713175927,
        widthMeters: 7.847999572753906,
        depthMeters: 6.519711017608643,
        areaSqmApprox: 24.165700387092073
      ),
      doors: nil,
      openings: [
        FloorplanSegment(ax: 2.0237345695495605, ay: 2.147122025489807, bx: 1.0571093559265137, by: 3.4464844465255737),
        FloorplanSegment(ax: 0.7028685808181763, ay: 5.391737461090088, bx: 1.4759443998336792, by: 5.968364238739014)
      ],
      windows: [
        FloorplanSegment(ax: 7.187534809112549, ay: 1.7287010550498962, bx: 6.074181079864502, by: 1.18905371427536),
        FloorplanSegment(ax: 5.5929856300354, ay: 0.9558165073394775, bx: 4.47019624710083, by: 0.41159558296203613)
      ],
      entryPassageHint: FloorplanEntryPassageHint(kind: "opening", index: 0),
      previousRoomExitPassageHint: FloorplanEntryPassageHint(kind: "door", index: 0),
      trackingSessionId: nil,
      worldOffsetX: -0.16076898574829102,
      worldOffsetY: -1.8286685943603516
    )

    let project = FloorplanProject(
      version: 4,
      projectKey: "GV24G",
      createdAt: Date(timeIntervalSince1970: 798630517.505744),
      roomScans: [
        FloorplanRoomScan(
          id: previousScanId,
          roomId: "living_room",
          floorId: "1og",
          createdAt: Date(timeIntervalSince1970: 798630569.282946),
          usdzPath: "rooms/\(previousScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(previousScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(previousScanId.uuidString)/segments.json",
          metrics: previousGeo.metrics,
          transform: .identity
        )
      ]
    )

    let result = FloorplanAutoDockService.bestAutoDock(
      project: project,
      newScanId: newScanId,
      newGeo: newGeo,
      floorId: "1og",
      loadGeo: { scanId in
        scanId == previousScanId ? previousGeo : nil
      }
    )

    #expect(result != nil)
    #expect(result?.connection.a.kind == .door)
    #expect(result?.connection.a.index == 0)
    #expect(result?.connection.b.kind == .opening)
    #expect(result?.connection.b.index == 1)
  }

  @Test("Auto-dock can ignore an incorrect previous-room exit hint when equal-width openings fit better")
  func incorrectPreviousExitHintDoesNotBlockMatchingOpening() {
    let previousScanId = UUID(uuidString: "8AAAD525-12C7-4E82-B4EA-E412D65B513D")!
    let newScanId = UUID(uuidString: "41D08D6A-B75A-48D2-A0F6-A7B6B48F570A")!

    let previousGeo = FloorplanSegmentsFile(
      version: 6,
      segments: [
        FloorplanSegment(ax: 2.473501682281494, ay: 0, bx: 0, by: 5.972719192504883),
        FloorplanSegment(ax: 0.000000476837158203125, ay: 5.972719669342041, bx: 4.05202579498291, by: 8.622206211090088),
        FloorplanSegment(ax: 4.084644377231598, ay: 1.0534725189208984, bx: 2.4735019207000732, by: 0),
        FloorplanSegment(ax: 7.51615047454834, ay: 3.3243038654327393, bx: 6.470447063446045, by: 2.640552282333374),
        FloorplanSegment(ax: 6.470447301864624, ay: 2.640552282333374, bx: 6.537787199020386, by: 2.5375664234161377),
        FloorplanSegment(ax: 4.139579638838768, ay: 0.9694576263427734, bx: 4.084644392132759, by: 1.0534725189208984),
        FloorplanSegment(ax: 4.0520259141922, ay: 8.622206211090088, bx: 7.516150236129761, by: 3.3243037462234497),
        FloorplanSegment(ax: 6.537786960601807, ay: 2.5375664234161377, bx: 4.139579772949219, by: 0.9694576263427734)
      ],
      metrics: FloorplanMetrics(
        perimeterMeters: 23.899112313279314,
        widthMeters: 7.51615047454834,
        depthMeters: 8.622206211090088,
        areaSqmApprox: 34.99444072203371
      ),
      doors: nil,
      openings: [
        FloorplanSegment(ax: 6.035290479660034, ay: 2.209000587463379, bx: 4.677368879318237, by: 1.3211002349853516),
        FloorplanSegment(ax: 6.02623724937439, ay: 5.602921336889267, bx: 6.552878141403198, by: 4.79749670624733)
      ],
      windows: [
        FloorplanSegment(ax: 1.0490303039550781, ay: 3.4396464824676514, bx: 0.4748244285583496, by: 4.826170742511749),
        FloorplanSegment(ax: 2.2747385501861572, ay: 0.4799509048461914, bx: 1.7999141216278076, by: 1.626500129699707)
      ],
      entryPassageHint: FloorplanEntryPassageHint(kind: "opening", index: 1),
      previousRoomExitPassageHint: nil,
      trackingSessionId: nil,
      worldOffsetX: -3.9536712169647217,
      worldOffsetY: -5.238440990447998
    )

    let newGeo = FloorplanSegmentsFile(
      version: 6,
      segments: [
        FloorplanSegment(ax: 6.483622074127197, ay: 3.560929775238037, bx: 0.42958784103393555, by: 0.000000476837158203125),
        FloorplanSegment(ax: 0.42958807945251465, ay: 0, bx: 0.0000002384185791015625, by: 4.700116157531738),
        FloorplanSegment(ax: 6.312914848327637, ay: 3.851153612136841, bx: 6.483622074127197, by: 3.5609290599823),
        FloorplanSegment(ax: 6.521327018737793, ay: 3.9737398624420166, bx: 6.312914848327637, by: 3.851153612136841),
        FloorplanSegment(ax: 0, ay: 4.700116395950317, bx: 5.783891201019287, by: 6.432689845561981),
        FloorplanSegment(ax: 5.783891439437866, ay: 6.4326900243759155, bx: 6.521327257156372, by: 3.9737396240234375)
      ],
      metrics: FloorplanMetrics(
        perimeterMeters: 20.926809998272336,
        widthMeters: 6.521327257156372,
        depthMeters: 6.4326900243759155,
        areaSqmApprox: 24.101905122446574
      ),
      doors: [
        FloorplanSegment(ax: 6.0485851764678955, ay: 5.5500781536102295, bx: 6.316953897476196, by: 4.6552135944366455)
      ],
      openings: [
        FloorplanSegment(ax: 2.5226568579673767, ay: 5.455782055854797, bx: 4.125454902648926, by: 5.935902714729309)
      ],
      windows: [
        FloorplanSegment(ax: 0.3595883846282959, ay: 0.7658677101135254, bx: 0.24643778800964355, by: 2.003844738006592),
        FloorplanSegment(ax: 0.1946573257446289, ay: 2.570376396179199, bx: 0.08054780960083008, by: 3.818844795227051)
      ],
      entryPassageHint: FloorplanEntryPassageHint(kind: "opening", index: 0),
      previousRoomExitPassageHint: FloorplanEntryPassageHint(kind: "opening", index: 1),
      trackingSessionId: nil,
      worldOffsetX: -3.099842071533203,
      worldOffsetY: -7.135748863220215
    )

    let project = FloorplanProject(
      version: 4,
      projectKey: "RMLRM",
      createdAt: Date(timeIntervalSince1970: 798637048.721361),
      roomScans: [
        FloorplanRoomScan(
          id: previousScanId,
          roomId: "living_room",
          floorId: "1og",
          createdAt: Date(timeIntervalSince1970: 798637135.140447),
          usdzPath: "rooms/\(previousScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(previousScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(previousScanId.uuidString)/segments.json",
          metrics: previousGeo.metrics,
          transform: .identity
        )
      ]
    )
    let normalizedProject = FloorplanLayoutResolver.normalizedProject(project: project) { _ in previousGeo }

    let result = FloorplanAutoDockService.bestAutoDock(
      project: normalizedProject,
      newScanId: newScanId,
      newGeo: newGeo,
      floorId: "1og",
      loadGeo: { scanId in
        scanId == previousScanId ? previousGeo : nil
      }
    )

    #expect(result != nil)
    #expect(result?.connection.a.kind == .opening)
    #expect(result?.connection.a.index == 0)
    #expect(result?.connection.b.kind == .opening)
    #expect(result?.connection.b.index == 0)
  }

  @Test("Normalized layout rotates a singleton room onto a stable orthogonal axis")
  func normalizedLayoutAlignsSingletonRoomToOrthogonalAxis() {
    let scanId = UUID(uuidString: "8AAAD525-12C7-4E82-B4EA-E412D65B513D")!
    let geometry = FloorplanSegmentsFile(
      version: 6,
      segments: [
        FloorplanSegment(ax: 2.473501682281494, ay: 0, bx: 0, by: 5.972719192504883),
        FloorplanSegment(ax: 0.000000476837158203125, ay: 5.972719669342041, bx: 4.05202579498291, by: 8.622206211090088),
        FloorplanSegment(ax: 4.084644377231598, ay: 1.0534725189208984, bx: 2.4735019207000732, by: 0),
        FloorplanSegment(ax: 7.51615047454834, ay: 3.3243038654327393, bx: 6.470447063446045, by: 2.640552282333374),
        FloorplanSegment(ax: 6.470447301864624, ay: 2.640552282333374, bx: 6.537787199020386, by: 2.5375664234161377),
        FloorplanSegment(ax: 4.139579638838768, ay: 0.9694576263427734, bx: 4.084644392132759, by: 1.0534725189208984),
        FloorplanSegment(ax: 4.0520259141922, ay: 8.622206211090088, bx: 7.516150236129761, by: 3.3243037462234497),
        FloorplanSegment(ax: 6.537786960601807, ay: 2.5375664234161377, bx: 4.139579772949219, by: 0.9694576263427734)
      ],
      metrics: FloorplanMetrics(
        perimeterMeters: 23.899112313279314,
        widthMeters: 7.51615047454834,
        depthMeters: 8.622206211090088,
        areaSqmApprox: 34.99444072203371
      ),
      doors: nil,
      openings: nil,
      windows: nil,
      entryPassageHint: nil,
      previousRoomExitPassageHint: nil,
      trackingSessionId: nil,
      worldOffsetX: nil,
      worldOffsetY: nil
    )

    let project = FloorplanProject(
      version: 4,
      projectKey: "AXIS",
      createdAt: Date(timeIntervalSince1970: 798637048.721361),
      roomScans: [
        FloorplanRoomScan(
          id: scanId,
          roomId: "living_room",
          floorId: "1og",
          createdAt: Date(timeIntervalSince1970: 798637135.140447),
          usdzPath: "rooms/\(scanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(scanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(scanId.uuidString)/segments.json",
          metrics: geometry.metrics,
          transform: .identity
        )
      ]
    )

    let normalized = FloorplanLayoutResolver.normalizedProject(project: project) { _ in geometry }
    guard let transform = normalized.roomScans.first?.transform else {
      Issue.record("Expected normalized project to contain the room transform")
      return
    }

    func apply(_ point: (Double, Double), rotation: Double, tx: Double, ty: Double) -> (Double, Double) {
      let cosR = cos(rotation)
      let sinR = sin(rotation)
      let x = point.0 * cosR - point.1 * sinR + tx
      let y = point.0 * sinR + point.1 * cosR + ty
      return (x, y)
    }

    guard let longest = geometry.segments.max(by: { segmentLength($0) < segmentLength($1) }) else {
      Issue.record("Expected at least one wall segment in the test geometry")
      return
    }
    let a = apply((longest.ax, longest.ay), rotation: transform.rotationRadians, tx: transform.translationX, ty: transform.translationY)
    let b = apply((longest.bx, longest.by), rotation: transform.rotationRadians, tx: transform.translationX, ty: transform.translationY)
    let angle = atan2(b.1 - a.1, b.0 - a.0)
    let orthogonalResidual = min(
      abs(normalizeOrthogonalResidual(angle)),
      abs(normalizeOrthogonalResidual(angle - (.pi / 2.0)))
    )

    #expect(orthogonalResidual < 0.15)
  }

  @Test("Tracked placement keeps shared-world room offsets and respects the base room rotation")
  func trackedPlacementUsesSharedWorldOffsets() {
    let baseScanId = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let project = FloorplanProject(
      version: 4,
      projectKey: "TRACKED",
      createdAt: Date(timeIntervalSince1970: 798637048.721361),
      roomScans: [
        FloorplanRoomScan(
          id: baseScanId,
          roomId: "living_room",
          floorId: "eg",
          createdAt: Date(timeIntervalSince1970: 798637135.140447),
          usdzPath: "rooms/\(baseScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(baseScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(baseScanId.uuidString)/segments.json",
          metrics: makeTrackedRoomGeometry(openingOnRight: true, trackingSessionId: "seq-1", worldOffsetX: 10, worldOffsetY: 20).metrics,
          transform: FloorplanRoomTransform(translationX: 4, translationY: -3, rotationRadians: .pi / 2.0)
        )
      ]
    )

    let newGeo = makeTrackedRoomGeometry(openingOnRight: false, trackingSessionId: "seq-1", worldOffsetX: 12, worldOffsetY: 21)
    let transform = FloorplanTrackedPlacementService.trackedTransform(
      project: project,
      newGeo: newGeo,
      floorId: "eg",
      loadGeo: { scanId in
        scanId == baseScanId ? makeTrackedRoomGeometry(openingOnRight: true, trackingSessionId: "seq-1", worldOffsetX: 10, worldOffsetY: 20) : nil
      }
    )

    #expect(transform != nil)
    #expect(abs((transform?.translationX ?? 0) - 3.0) < 0.001)
    #expect(abs((transform?.translationY ?? 0) - (-1.0)) < 0.001)
    #expect(abs(normalizeOrthogonalResidual((transform?.rotationRadians ?? 0) - (.pi / 2.0))) < 0.001)
  }

  @Test("Tracked placement preserves shared-world room rotation relative to the snapped display axis")
  func trackedPlacementUsesSharedWorldRotation() {
    let baseScanId = UUID(uuidString: "11111111-1111-1111-1111-222222222222")!
    let baseGeo = makeTrackedRoomGeometry(
      openingOnRight: true,
      trackingSessionId: "seq-rotation",
      worldOffsetX: 10,
      worldOffsetY: 20,
      worldRotationRadians: 0.40
    )
    let newGeo = makeTrackedRoomGeometry(
      openingOnRight: false,
      trackingSessionId: "seq-rotation",
      worldOffsetX: 12,
      worldOffsetY: 21,
      worldRotationRadians: 1.05
    )
    let project = FloorplanProject(
      version: 4,
      projectKey: "TRACKED_ROT",
      createdAt: Date(timeIntervalSince1970: 798637048.721361),
      roomScans: [
        FloorplanRoomScan(
          id: baseScanId,
          roomId: "living_room",
          floorId: "eg",
          createdAt: Date(timeIntervalSince1970: 798637135.140447),
          usdzPath: "rooms/\(baseScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(baseScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(baseScanId.uuidString)/segments.json",
          metrics: baseGeo.metrics,
          transform: FloorplanRoomTransform(translationX: 4, translationY: -3, rotationRadians: 0.12)
        )
      ]
    )

    let transform = FloorplanTrackedPlacementService.trackedTransform(
      project: project,
      newGeo: newGeo,
      floorId: "eg",
      loadGeo: { scanId in
        scanId == baseScanId ? baseGeo : nil
      }
    )

    let expectedDisplayDelta = 0.12 - 0.40
    let expectedDelta = rotatePoint(x: 2.0, y: 1.0, radians: expectedDisplayDelta)
    let expectedRotation = 1.05 + expectedDisplayDelta

    #expect(transform != nil)
    #expect(abs((transform?.translationX ?? 0) - (4 + expectedDelta.x)) < 0.001)
    #expect(abs((transform?.translationY ?? 0) - (-3 + expectedDelta.y)) < 0.001)
    #expect(abs(normalizeOrthogonalResidual((transform?.rotationRadians ?? 0) - expectedRotation)) < 0.001)
  }

  @Test("Tracked room-sequence components keep their shared layout but are still axis-aligned together")
  func trackedRoomSequenceComponentAlignsWithoutResolvingAwayPlacement() {
    let leftScanId = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let rightScanId = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
    let leftGeo = makeTrackedRoomGeometry(openingOnRight: true, trackingSessionId: "seq-2", worldOffsetX: 0, worldOffsetY: 0)
    let rightGeo = makeTrackedRoomGeometry(openingOnRight: false, trackingSessionId: "seq-2", worldOffsetX: 2, worldOffsetY: 0)

    let rotation = 0.61
    let delta = rotatePoint(x: 2.0, y: 0.0, radians: rotation)
    let project = FloorplanProject(
      version: 4,
      projectKey: "SEQ",
      createdAt: Date(timeIntervalSince1970: 798637048.721361),
      roomScans: [
        FloorplanRoomScan(
          id: leftScanId,
          roomId: "living_room",
          floorId: "eg",
          createdAt: Date(timeIntervalSince1970: 798637135.140447),
          usdzPath: "rooms/\(leftScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(leftScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(leftScanId.uuidString)/segments.json",
          metrics: leftGeo.metrics,
          transform: FloorplanRoomTransform(translationX: 0, translationY: 0, rotationRadians: rotation)
        ),
        FloorplanRoomScan(
          id: rightScanId,
          roomId: "dining_room",
          floorId: "eg",
          createdAt: Date(timeIntervalSince1970: 798637236.140447),
          usdzPath: "rooms/\(rightScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(rightScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(rightScanId.uuidString)/segments.json",
          metrics: rightGeo.metrics,
          transform: FloorplanRoomTransform(translationX: delta.x, translationY: delta.y, rotationRadians: rotation)
        )
      ],
      connections: [
        FloorplanRoomConnection(
          id: UUID(),
          createdAt: Date(timeIntervalSince1970: 798637300.0),
          a: FloorplanPassageRef(scanId: leftScanId, kind: .opening, index: 0),
          b: FloorplanPassageRef(scanId: rightScanId, kind: .opening, index: 0)
        )
      ]
    )

    let normalized = FloorplanLayoutResolver.normalizedProject(project: project) { scan in
      switch scan.id {
      case leftScanId:
        return leftGeo
      case rightScanId:
        return rightGeo
      default:
        return nil
      }
    }

    guard let left = normalized.roomScans.first(where: { $0.id == leftScanId }),
          let right = normalized.roomScans.first(where: { $0.id == rightScanId }) else {
      Issue.record("Expected both rooms to remain in the normalized project")
      return
    }

    let dx = right.transform.translationX - left.transform.translationX
    let dy = right.transform.translationY - left.transform.translationY
    let distance = (dx * dx + dy * dy).squareRoot()

    #expect(abs(distance - 2.0) < 0.05)
    #expect(abs(normalizeOrthogonalResidual(left.transform.rotationRadians)) < 0.15)
    #expect(abs(normalizeOrthogonalResidual(right.transform.rotationRadians)) < 0.15)
  }

  @Test("Tracked room-sequence scans without explicit connections still align as one shared component")
  func trackedRoomSequenceWithoutConnectionsAlignTogether() {
    let leftScanId = UUID(uuidString: "3D727D4F-3F38-4E7A-88F6-F8C77B0685F1")!
    let rightScanId = UUID(uuidString: "7683B6A1-5D35-46A3-A66A-41F2D8B16867")!
    let leftGeo = makeTrackedRoomGeometry(openingOnRight: true, trackingSessionId: "seq-2b", worldOffsetX: 0, worldOffsetY: 0)
    let rightGeo = makeTrackedRoomGeometry(openingOnRight: false, trackingSessionId: "seq-2b", worldOffsetX: 2, worldOffsetY: 0)

    let leftRotation = 0.42
    let rightRotation = 2.78
    let expectedRelativeRotation = normalizeOrthogonalResidual(rightRotation - leftRotation)
    let initialDistance = hypot(10.76130044583409 - 2.240111500902388, 4.8724854685033065 - (-6.105441490092032))

    let project = FloorplanProject(
      version: 4,
      projectKey: "SEQ-NO-CONNECTION",
      createdAt: Date(timeIntervalSince1970: 798637048.721361),
      roomScans: [
        FloorplanRoomScan(
          id: leftScanId,
          roomId: "living_room",
          floorId: "1og",
          createdAt: Date(timeIntervalSince1970: 798637135.140447),
          usdzPath: "rooms/\(leftScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(leftScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(leftScanId.uuidString)/segments.json",
          metrics: leftGeo.metrics,
          transform: FloorplanRoomTransform(
            translationX: 2.240111500902388,
            translationY: -6.105441490092032,
            rotationRadians: leftRotation
          )
        ),
        FloorplanRoomScan(
          id: rightScanId,
          roomId: "dining_room",
          floorId: "1og",
          createdAt: Date(timeIntervalSince1970: 798637236.140447),
          usdzPath: "rooms/\(rightScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(rightScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(rightScanId.uuidString)/segments.json",
          metrics: rightGeo.metrics,
          transform: FloorplanRoomTransform(
            translationX: 10.76130044583409,
            translationY: 4.8724854685033065,
            rotationRadians: rightRotation
          )
        )
      ]
    )

    let normalized = FloorplanLayoutResolver.normalizedProject(project: project) { scan in
      switch scan.id {
      case leftScanId:
        return leftGeo
      case rightScanId:
        return rightGeo
      default:
        return nil
      }
    }

    guard let left = normalized.roomScans.first(where: { $0.id == leftScanId }),
          let right = normalized.roomScans.first(where: { $0.id == rightScanId }) else {
      Issue.record("Expected both rooms to remain in the normalized project")
      return
    }

    let normalizedRelativeRotation = normalizeOrthogonalResidual(right.transform.rotationRadians - left.transform.rotationRadians)
    let normalizedDistance = hypot(
      right.transform.translationX - left.transform.translationX,
      right.transform.translationY - left.transform.translationY
    )

    #expect(abs(normalizeOrthogonalResidual(left.transform.rotationRadians)) < 0.15)
    #expect(abs(normalizedRelativeRotation - expectedRelativeRotation) < 0.05)
    #expect(abs(normalizedDistance - initialDistance) < 0.05)
  }

  @Test("Preferred tracked transforms act as a soft prior but final auto-dock still snaps walls flush")
  func preferredTrackedTransformStillSnapsToPassageGeometry() {
    let previousScanId = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!
    let newScanId = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
    let previousGeo = makeTrackedRoomGeometry(openingOnRight: true, trackingSessionId: "seq-3", worldOffsetX: 0, worldOffsetY: 0)
    let newGeo = makeTrackedRoomGeometry(openingOnRight: false, trackingSessionId: "seq-3", worldOffsetX: 0.4, worldOffsetY: -0.2)

    let project = FloorplanProject(
      version: 4,
      projectKey: "SOFTPRIOR",
      createdAt: Date(timeIntervalSince1970: 798637048.721361),
      roomScans: [
        FloorplanRoomScan(
          id: previousScanId,
          roomId: "living_room",
          floorId: "eg",
          createdAt: Date(timeIntervalSince1970: 798637135.140447),
          usdzPath: "rooms/\(previousScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(previousScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(previousScanId.uuidString)/segments.json",
          metrics: previousGeo.metrics,
          transform: .identity
        )
      ]
    )

    let preferredTransform = FloorplanRoomTransform(
      translationX: 2.45,
      translationY: 0.38,
      rotationRadians: 0.19
    )

    let result = FloorplanAutoDockService.bestAutoDock(
      project: project,
      newScanId: newScanId,
      newGeo: newGeo,
      floorId: "eg",
      loadGeo: { scanId in
        scanId == previousScanId ? previousGeo : nil
      },
      preferredTransform: preferredTransform
    )

    #expect(result != nil)
    #expect(result?.connection.a.kind == .opening)
    #expect(result?.connection.b.kind == .opening)
    #expect(abs((result?.transform.translationX ?? 0) - 2.0) < 0.001)
    #expect(abs((result?.transform.translationY ?? 0) - 0.0) < 0.001)
    #expect(abs(normalizeOrthogonalResidual(result?.transform.rotationRadians ?? 0)) < 0.001)
  }

  @Test("Tracked room-sequence docking does not let a wrong door hint override the matching opening pair")
  func trackedRoomSequencePrefersMatchingOpeningPairOverWrongDoorHint() {
    let previousScanId = UUID(uuidString: "7CAA5AB7-640C-4764-9347-3A04B8895693")!
    let newScanId = UUID(uuidString: "E9263A41-66A8-437C-9CF7-F0C20C7881BC")!
    let previousGeo = makeLiveJob9HOGCLivingRoomGeometry()
    let newGeo = makeLiveJob9HOGCDiningRoomGeometry()

    let project = FloorplanProject(
      version: 4,
      projectKey: "9HOGC",
      createdAt: Date(timeIntervalSince1970: 798644787.279626),
      roomScans: [
        FloorplanRoomScan(
          id: previousScanId,
          roomId: "living_room",
          floorId: "1og",
          createdAt: Date(timeIntervalSince1970: 798644787.279626),
          usdzPath: "rooms/\(previousScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(previousScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(previousScanId.uuidString)/segments.json",
          metrics: previousGeo.metrics,
          transform: FloorplanRoomTransform(
            translationX: 0.2078941220036734,
            translationY: -0.1180794149873301,
            rotationRadians: 0.07317342545936337
          )
        )
      ]
    )

    let preferredTransform = FloorplanTrackedPlacementService.trackedTransform(
      project: project,
      newGeo: newGeo,
      floorId: "1og",
      loadGeo: { scanId in
        scanId == previousScanId ? previousGeo : nil
      }
    )

    #expect(preferredTransform != nil)

    let result = FloorplanAutoDockService.bestAutoDock(
      project: project,
      newScanId: newScanId,
      newGeo: newGeo,
      floorId: "1og",
      loadGeo: { scanId in
        scanId == previousScanId ? previousGeo : nil
      },
      preferredTransform: preferredTransform,
      requiresTrackedAgreement: true
    )

    #expect(result != nil)
    #expect(result?.connection.a.kind == .opening)
    #expect(result?.connection.a.index == 0)
    #expect(result?.connection.b.kind == .opening)
    #expect(result?.connection.b.index == 0)
  }

  @Test("Tracked room-sequence fallback snaps a nearly aligned room flush onto the shared opening")
  func trackedRoomSequenceFallbackSnapsNearlyAlignedOpenings() {
    let previousScanId = UUID(uuidString: "99999999-1111-2222-3333-444444444444")!
    let newScanId = UUID(uuidString: "99999999-5555-6666-7777-888888888888")!
    let previousGeo = makeTrackedRoomGeometry(openingOnRight: true, trackingSessionId: "seq-fallback", worldOffsetX: 0, worldOffsetY: 0)
    let newGeo = makeTrackedRoomGeometry(openingOnRight: false, trackingSessionId: "seq-fallback", worldOffsetX: 2, worldOffsetY: 0)

    let project = FloorplanProject(
      version: 4,
      projectKey: "TRACKED-SNAP",
      createdAt: Date(timeIntervalSince1970: 798644787.279626),
      roomScans: [
        FloorplanRoomScan(
          id: previousScanId,
          roomId: "living_room",
          floorId: "eg",
          createdAt: Date(timeIntervalSince1970: 798644787.279626),
          usdzPath: "rooms/\(previousScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(previousScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(previousScanId.uuidString)/segments.json",
          metrics: previousGeo.metrics,
          transform: .identity
        )
      ]
    )

    let trackedTransform = FloorplanRoomTransform(
      translationX: 2.0,
      translationY: 0.72,
      rotationRadians: 0
    )

    let result = FloorplanAutoDockService.refinedTrackedPlacement(
      project: project,
      newScanId: newScanId,
      newGeo: newGeo,
      trackedTransform: trackedTransform,
      floorId: "eg",
      loadGeo: { scanId in
        scanId == previousScanId ? previousGeo : nil
      }
    )

    #expect(result != nil)
    #expect(result?.connection.a.kind == .opening)
    #expect(result?.connection.b.kind == .opening)
    #expect(abs((result?.transform.translationX ?? 0) - 2.0) < 0.001)
    #expect(abs((result?.transform.translationY ?? 0) - 0.0) < 0.001)
    #expect(abs(normalizeOrthogonalResidual(result?.transform.rotationRadians ?? 0)) < 0.001)
  }

  @Test("Collision guard rejects placements whose room footprints overlap")
  func collisionGuardRejectsOverlappingPlacements() {
    let previousScanId = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!
    let previousGeo = makeTrackedRoomGeometry(openingOnRight: true, trackingSessionId: "seq-4", worldOffsetX: 0, worldOffsetY: 0)
    let newGeo = makeTrackedRoomGeometry(openingOnRight: false, trackingSessionId: "seq-4", worldOffsetX: 0, worldOffsetY: 0)

    let project = FloorplanProject(
      version: 4,
      projectKey: "COLLISION",
      createdAt: Date(timeIntervalSince1970: 798637048.721361),
      roomScans: [
        FloorplanRoomScan(
          id: previousScanId,
          roomId: "living_room",
          floorId: "eg",
          createdAt: Date(timeIntervalSince1970: 798637135.140447),
          usdzPath: "rooms/\(previousScanId.uuidString)/scan.usdz",
          floorplanPNGPath: "rooms/\(previousScanId.uuidString)/floorplan.png",
          segmentsJSONPath: "rooms/\(previousScanId.uuidString)/segments.json",
          metrics: previousGeo.metrics,
          transform: .identity
        )
      ]
    )

    let overlapping = FloorplanAutoDockService.placementHasSevereOverlap(
      project: project,
      newGeo: newGeo,
      newTransform: FloorplanRoomTransform(translationX: 1.0, translationY: 0, rotationRadians: 0),
      floorId: "eg",
      loadGeo: { scanId in
        scanId == previousScanId ? previousGeo : nil
      }
    )

    let flush = FloorplanAutoDockService.placementHasSevereOverlap(
      project: project,
      newGeo: newGeo,
      newTransform: FloorplanRoomTransform(translationX: 2.0, translationY: 0, rotationRadians: 0),
      floorId: "eg",
      loadGeo: { scanId in
        scanId == previousScanId ? previousGeo : nil
      }
    )

    #expect(overlapping)
    #expect(!flush)
  }
}

private func segmentLength(_ segment: FloorplanSegment) -> Double {
  let dx = segment.bx - segment.ax
  let dy = segment.by - segment.ay
  return (dx * dx + dy * dy).squareRoot()
}

private func normalizeOrthogonalResidual(_ angle: Double) -> Double {
  var normalized = angle
  while normalized > .pi { normalized -= 2 * .pi }
  while normalized < -.pi { normalized += 2 * .pi }
  return normalized
}

private func makeTrackedRoomGeometry(
  openingOnRight: Bool,
  trackingSessionId: String,
  worldOffsetX: Double,
  worldOffsetY: Double,
  worldRotationRadians: Double? = nil
) -> FloorplanSegmentsFile {
  let walls = [
    FloorplanSegment(ax: 0, ay: 0, bx: 2, by: 0),
    FloorplanSegment(ax: 2, ay: 0, bx: 2, by: 2),
    FloorplanSegment(ax: 2, ay: 2, bx: 0, by: 2),
    FloorplanSegment(ax: 0, ay: 2, bx: 0, by: 0)
  ]
  let opening = openingOnRight
    ? FloorplanSegment(ax: 2, ay: 0.7, bx: 2, by: 1.3)
    : FloorplanSegment(ax: 0, ay: 0.7, bx: 0, by: 1.3)

  return FloorplanSegmentsFile(
    version: 7,
    segments: walls,
    metrics: FloorplanMetrics(perimeterMeters: 8, widthMeters: 2, depthMeters: 2, areaSqmApprox: 4),
    doors: nil,
    openings: [opening],
    windows: nil,
    entryPassageHint: FloorplanEntryPassageHint(kind: "opening", index: 0),
    previousRoomExitPassageHint: nil,
    trackingSessionId: trackingSessionId,
    trackingSource: .roomSequenceSharedWorld,
    worldOffsetX: worldOffsetX,
    worldOffsetY: worldOffsetY,
    worldRotationRadians: worldRotationRadians
  )
}

private func makeLiveJob9HOGCLivingRoomGeometry() -> FloorplanSegmentsFile {
  FloorplanSegmentsFile(
    version: 7,
    segments: [
      FloorplanSegment(ax: 0.24062013626098633, ay: 6.143834590911865, bx: 6.56771183013916, by: 4.813920497894287),
      FloorplanSegment(ax: 6.56771183013916, ay: 4.813920974731445, bx: 6.436159133911133, by: 0),
      FloorplanSegment(ax: 0.18792939186096191, ay: 4.215737342834473, bx: 0.24061942100524902, by: 6.143834590911865),
      FloorplanSegment(ax: 0.11262321472167969, ay: 0.1728074550628662, bx: 0.14447307586669922, by: 1.3382959961891174),
      FloorplanSegment(ax: 0.04584002494812012, ay: 4.219620227813721, bx: 0.18792939186096191, by: 4.215737342834473),
      FloorplanSegment(ax: 0.14447307586669922, ay: 1.338295817375183, bx: 0, by: 1.3422437906265259),
      FloorplanSegment(ax: 6.436159372329712, ay: 2.384185791015625e-07, bx: 0.11262297630310059, by: 0.1728074550628662),
      FloorplanSegment(ax: 0, ay: 1.3422441482543945, bx: 0.04584026336669922, by: 4.2196204662323)
    ],
    metrics: FloorplanMetrics(
      perimeterMeters: 23.866117659025793,
      widthMeters: 6.56771183013916,
      depthMeters: 6.143834590911865,
      areaSqmApprox: 34.85380188130027
    ),
    doors: [
      FloorplanSegment(ax: 2.860291361808777, ay: 0.09772014617919922, bx: 1.911051869392395, by: 0.12366056442260742)
    ],
    openings: [
      FloorplanSegment(ax: 0.010043144226074219, ay: 1.9726635813713074, bx: 0.03590965270996094, by: 3.5962889194488525)
    ],
    windows: [
      FloorplanSegment(ax: 3.926715672016144, ay: 5.3690409660339355, bx: 5.42375111579895, by: 5.054373741149902),
      FloorplanSegment(ax: 0.6925539970397949, ay: 6.048841238021851, bx: 1.935375690460205, by: 5.787607908248901)
    ],
    entryPassageHint: FloorplanEntryPassageHint(kind: "door", index: 0),
    previousRoomExitPassageHint: nil,
    trackingSessionId: "D6EED003-D3AC-4522-BD71-92BDDFA94587",
    trackingSource: .roomSequenceSharedWorld,
    worldOffsetX: -3.576791763305664,
    worldOffsetY: -2.159262180328369
  )
}

private func makeLiveJob9HOGCDiningRoomGeometry() -> FloorplanSegmentsFile {
  FloorplanSegmentsFile(
    version: 7,
    segments: [
      FloorplanSegment(ax: 6.333378791809082, ay: 5.908236265182495, bx: 2.500175356864929, by: 4.76837158203125e-07),
      FloorplanSegment(ax: 2.500175714492798, ay: 0, bx: 0, by: 3.9904470443725586),
      FloorplanSegment(ax: 6.039615631103516, ay: 6.09882664680481, bx: 6.333378791809082, by: 5.908236265182495),
      FloorplanSegment(ax: 6.187270641326904, ay: 6.237403988838196, bx: 6.039616107940674, by: 6.098826766014099),
      FloorplanSegment(ax: 0, ay: 3.9904470443725586, bx: 4.410871982574463, by: 8.130160212516785),
      FloorplanSegment(ax: 4.410871982574463, ay: 8.130159974098206, bx: 6.187270164489746, by: 6.237403988838196)
    ],
    metrics: FloorplanMetrics(
      perimeterMeters: 20.949438000724307,
      widthMeters: 6.333378791809082,
      depthMeters: 8.130160212516785,
      areaSqmApprox: 24.067626921300544
    ),
    doors: nil,
    openings: [
      FloorplanSegment(ax: 1.9496400952339172, ay: 5.820232629776001, bx: 3.1535322666168213, by: 6.950115442276001),
      FloorplanSegment(ax: 5.00139856338501, ay: 7.500953048467636, bx: 5.654350757598877, by: 6.805230736732483)
    ],
    windows: [
      FloorplanSegment(ax: 2.0983616709709167, ay: 0.6413226127624512, bx: 1.428671583533287, by: 1.710193157196045),
      FloorplanSegment(ax: 1.1440536081790924, ay: 2.164461612701416, bx: 0.47994446754455566, by: 3.224423885345459)
    ],
    entryPassageHint: FloorplanEntryPassageHint(kind: "opening", index: 0),
    previousRoomExitPassageHint: FloorplanEntryPassageHint(kind: "door", index: 0),
    trackingSessionId: "D6EED003-D3AC-4522-BD71-92BDDFA94587",
    trackingSource: .roomSequenceSharedWorld,
    worldOffsetX: -1.5322637557983398,
    worldOffsetY: -7.981960773468018
  )
}

private func rotatePoint(x: Double, y: Double, radians: Double) -> (x: Double, y: Double) {
  let cosR = cos(radians)
  let sinR = sin(radians)
  return (
    x: x * cosR - y * sinR,
    y: x * sinR + y * cosR
  )
}
