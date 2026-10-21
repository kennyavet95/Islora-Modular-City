import SpriteKit
import SwiftUI

/// The interactive world (§15/§16): plots, buildings, workers and trucks all
/// live here. SwiftUI never draws city content itself — it only overlays HUD
/// chrome on top of this scene, per the "city is not a menu" rule.
final class CityScene: SKScene {
    var session: GameSession!
    var dragState: ConstructionDragState!

    private let worldLayer = SKNode()
    private let cameraNode = SKCameraNode()
    private var decorationNode: SKNode?
    private var buildingNodes: [UUID: BuildingNode] = [:]
    private var plotPadNodes: [UUID: SKNode] = [:]
    private var plotWorldPositions: [UUID: CGPoint] = [:]
    private var plotUnlockedState: [UUID: Bool] = [:]
    private var knownPlotIDs: Set<UUID> = []
    #if DEBUG
    private let testTimeScale = max(1, Double(ProcessInfo.processInfo.environment["ISLORA_TEST_TIME_SCALE"] ?? "1") ?? 1)
    #else
    private let testTimeScale = 1.0
    #endif
    private var lastUpdateTime: TimeInterval?
    private var lastRenderedMode: Bool?
    private var hasSetInitialOverviewCamera = false

    /// Camera pan tracking in overview and construction. Kept in view points (not scene/world
    /// points) since those aren't affected by the camera's own position — the
    /// thing we're busy changing — while we compute the drag.
    private var panStartViewLocation: CGPoint?
    private var panStartCamera: CGPoint?
    private var customCamera = false
    private var lastViewport = CGRect.zero
    private var lastContentRect = CGRect.zero
    private var didPanThisGesture = false
    /// Below this drag distance (in view points) a touch still counts as a
    /// tap on a plot rather than a pan, so a slightly-shaky tap doesn't get
    /// silently swallowed.
    private static let panTapThreshold: CGFloat = 10

    static let plotSpacing: CGFloat = 432
    static let minimumCameraScale: CGFloat = 0.25
    static let maximumCameraScale: CGFloat = 4
    static let plotBaseY: CGFloat = -95
    /// Fixed overview zoom (not a fit-every-plot-in scale): keeps a plot's
    /// on-screen size constant and close to the background paving's own tile
    /// scale no matter how many plots the island has grown to. The player
    /// pans sideways (see touchesMoved) to see plots that don't fit on
    /// screen, rather than everything shrinking to make room.
    static let overviewScale: CGFloat = 1.65

    override func didMove(to view: SKView) {
        backgroundColor = SKColor(BlockoraPalette.skyBottom)
        scaleMode = .resizeFill

        worldLayer.speed = testTimeScale
        addChild(worldLayer)
        camera = cameraNode
        addChild(cameraNode)

        installDecoration()
        syncPlots()
        focusOverview(animated: false)
    }

    /// The backdrop art is sized to exactly cover the screen and parented to
    /// the *camera* rather than `worldLayer`. Children of an SKCameraNode are
    /// automatically immune to the camera's own zoom (its scale both enlarges
    /// them and is divided back out by the viewport transform), so this stays
    /// pinned edge-to-edge at every zoom level instead of shrinking away and
    /// exposing bare scene background when the camera zooms out to fit more
    /// plots (§16/§36: the world must never look empty).
    private func installDecoration() {
        decorationNode?.removeFromParent()
        let decoration = WorldDecorationNode(sceneSize: size)
        decoration.zPosition = -100
        cameraNode.addChild(decoration)
        decorationNode = decoration
    }

    override func didChangeSize(_ oldSize: CGSize) {
        super.didChangeSize(oldSize)
        // `didMove(to:)` runs before the SKView has a real frame, so `size` is
        // still (0,0) there — the *first* resize (zero → real screen size) is
        // exactly the one that must not be skipped, or the background art and
        // camera framing both end up permanently sized for an empty scene.
        guard oldSize != size else { return }
        installDecoration()
        if session?.isConstructionModeActive != true { focusOverview(animated: false) }
    }

    /// Rebuilds plot pads whenever the *set* of plot ids changes (first load,
    /// or a full world reset from Settings) — `GameWorld.newGame()` mints
    /// fresh UUIDs each time it runs, so anything cached from an earlier,
    /// throwaway world must never be trusted once the real one loads.
    /// Otherwise just keeps each pad's lock/occupied visuals current.
    private func syncPlots() {
        guard let session else { return }
        let currentIDs = Set(session.world.plots.map(\.id))
        guard currentIDs != knownPlotIDs else {
            updatePlotPadVisuals()
            return
        }

        let newlyAddedIDs = currentIDs.subtracting(knownPlotIDs)

        for node in plotPadNodes.values { node.removeFromParent() }
        plotPadNodes.removeAll()
        plotWorldPositions.removeAll()
        plotUnlockedState.removeAll()
        for node in buildingNodes.values { node.removeFromParent() }
        buildingNodes.removeAll()
        knownPlotIDs = currentIDs

        for (index, plot) in session.world.plots.enumerated() {
            let worldPosition = CGPoint(x: CGFloat(index) * Self.plotSpacing, y: Self.plotBaseY)
            plotWorldPositions[plot.id] = worldPosition
            addPlotPad(plot, at: worldPosition)
        }

        // The plot count just changed (most commonly: the island expanded
        // with a new plot) — pan to bring the new one into view instead of
        // leaving it wherever it landed off-screen. First load has no
        // "newly added" plot to single out, so just settle at the start of the row.
        if session.isConstructionModeActive != true {
            if let newPlotID = newlyAddedIDs.first, hasSetInitialOverviewCamera {
                focusOverview(revealing: newPlotID, animated: true)
            } else {
                focusOverview(animated: true)
            }
        }
    }

    private func addPlotPad(_ plot: Plot, at worldPosition: CGPoint) {
        let pad = makePlotPad(plot: plot)
        pad.position = worldPosition
        pad.isHidden = plot.buildingID != nil
        worldLayer.addChild(pad)
        plotPadNodes[plot.id] = pad
        plotUnlockedState[plot.id] = plot.isUnlocked
    }

    private func updatePlotPadVisuals() {
        guard let session else { return }
        for plot in session.world.plots {
            if plotUnlockedState[plot.id] != plot.isUnlocked, let worldPosition = plotWorldPositions[plot.id] {
                plotPadNodes[plot.id]?.removeFromParent()
                addPlotPad(plot, at: worldPosition)
            }
            plotPadNodes[plot.id]?.isHidden = plot.buildingID != nil || session.isConstructionModeActive
        }
    }

    private func makePlotPad(plot: Plot) -> SKNode {
        // Same square BuildingNode uses for its own ground pad, so a plot's
        // footprint doesn't change shape the moment something gets built on it.
        let pad = SKShapeNode(rectOf: BuildingNode.footprintSize, cornerRadius: 20)
        if !plot.isUnlocked {
            pad.fillColor = SKColor.black.withAlphaComponent(0.35)
            pad.strokeColor = SKColor.white.withAlphaComponent(0.4)
            pad.lineWidth = 2
            let lockBody = SKShapeNode(rectOf: CGSize(width: 38, height: 30), cornerRadius: 7)
            lockBody.fillColor = SKColor(BlockoraPalette.panelBackground)
            lockBody.strokeColor = .white
            lockBody.lineWidth = 2
            lockBody.position = CGPoint(x: 0, y: -6)
            pad.addChild(lockBody)

            let shackle = SKShapeNode(path: CGPath(
                roundedRect: CGRect(x: -13, y: -2, width: 26, height: 26),
                cornerWidth: 13,
                cornerHeight: 13,
                transform: nil
            ))
            shackle.fillColor = .clear
            shackle.strokeColor = .white
            shackle.lineWidth = 4
            shackle.position = CGPoint(x: 0, y: 8)
            pad.addChild(shackle)
        } else {
            pad.fillColor = SKColor.white.withAlphaComponent(0.18)
            pad.strokeColor = SKColor.white.withAlphaComponent(0.6)
            pad.lineWidth = 2
            let plus = SKLabelNode(text: "+")
            plus.fontSize = 40
            plus.fontColor = .white
            plus.verticalAlignmentMode = .center
            pad.addChild(plus)
            if !UIAccessibility.isReduceMotionEnabled {
                plus.run(.repeatForever(.sequence([
                    .fadeAlpha(to: 0.6, duration: 1.2), .fadeAlpha(to: 1, duration: 1.2)
                ])))
            }
        }
        return pad
    }

    // MARK: - Camera

    private func focusOverview(animated: Bool) {
        let x = hasSetInitialOverviewCamera ? cameraNode.position.x : 0
        hasSetInitialOverviewCamera = true
        move(camera: CGPoint(x: clampOverviewCameraX(x), y: 0), scale: Self.overviewScale, animated: animated)
    }

    private func focusOverview(revealing plotID: UUID, animated: Bool) {
        let x = plotWorldPositions[plotID]?.x ?? cameraNode.position.x
        move(camera: CGPoint(x: clampOverviewCameraX(x), y: 0), scale: Self.overviewScale, animated: animated)
    }

    /// Keeps the overview camera from panning past the first/last plot —
    /// there's nothing beyond the row to see, so scrolling further would just
    /// show empty background.
    private func clampOverviewCameraX(_ x: CGFloat) -> CGFloat {
        let plotCount = max(session?.world.plots.count ?? 1, 1)
        let minX: CGFloat = 0
        let maxX = CGFloat(plotCount - 1) * Self.plotSpacing
        guard minX < maxX else { return minX }
        return min(max(x, minX), maxX)
    }

    private var constructionViewport: CGRect {
        guard let view else { return CGRect(origin: .zero, size: size) }
        let top = dragState.hudBottom > 0 ? view.convert(CGPoint(x: 0, y: dragState.hudBottom), from: nil).y : view.safeAreaInsets.top + 110
        let bottom = dragState.constructionToolsTop > top ? view.convert(CGPoint(x: 0, y: dragState.constructionToolsTop), from: nil).y : view.bounds.height * 0.62
        return CGRect(x: 12, y: top + 12, width: max(80, view.bounds.width - 24), height: max(80, bottom - top - 24))
    }

    /// Pure fit math: put the entire editing area inside the space between HUD and tools.
    static func fittedCamera(content: CGRect, viewport: CGRect, viewSize: CGSize) -> (position: CGPoint, scale: CGFloat) {
        let scale = min(maximumCameraScale, max(minimumCameraScale,
            max((content.width + 32) / max(1, viewport.width), (content.height + 32) / max(1, viewport.height))))
        return (CGPoint(x: content.midX - (viewport.midX - viewSize.width / 2) * scale,
                        y: content.midY - (viewSize.height / 2 - viewport.midY) * scale), scale)
    }

    private var editingContentRect: CGRect? {
        guard let id = session.activeBuildingID, let building = session.world.buildings[id],
              let base = plotWorldPositions[building.plotID] else { return nil }
        return BuildingNode.constructionRect(topRow: building.footprint.maxY).offsetBy(dx: base.x, dy: base.y)
    }

    private func focusConstruction(on plotID: UUID, animated: Bool) {
        guard let content = editingContentRect, let view else { return }
        let fit = Self.fittedCamera(content: content, viewport: constructionViewport, viewSize: view.bounds.size)
        lastContentRect = content
        lastViewport = constructionViewport
        move(camera: fit.position, scale: fit.scale, animated: animated)
    }

    func zoom(by factor: CGFloat, around point: CGPoint) {
        guard factor.isFinite, factor > 0, dragState?.isDragging != true else { return }
        cameraNode.removeAction(forKey: "cameraFocus")
        let anchor = convertPoint(fromView: point)
        cameraNode.setScale(min(Self.maximumCameraScale, max(Self.minimumCameraScale, cameraNode.xScale / factor)))
        let shifted = convertPoint(fromView: point)
        cameraNode.position.x += anchor.x - shifted.x
        cameraNode.position.y += anchor.y - shifted.y
        customCamera = true
        didPanThisGesture = true
        clampCamera()
    }

    private func clampCamera() {
        if session.isConstructionModeActive, let content = editingContentRect, let view {
            let viewport = constructionViewport
            let scale = cameraNode.xScale
            let center = CGPoint(x: content.midX - (viewport.midX - view.bounds.midX) * scale,
                                 y: content.midY - (view.bounds.midY - viewport.midY) * scale)
            let dx = max(0, (content.width - viewport.width * scale) / 2) + 60 * scale
            let dy = max(0, (content.height - viewport.height * scale) / 2) + 60 * scale
            cameraNode.position.x = min(center.x + dx, max(center.x - dx, cameraNode.position.x))
            cameraNode.position.y = min(center.y + dy, max(center.y - dy, cameraNode.position.y))
        } else {
            let lastX = CGFloat(max(0, session.world.plots.count - 1)) * Self.plotSpacing
            cameraNode.position.x = min(lastX + 180, max(-180, cameraNode.position.x))
            cameraNode.position.y = min(350, max(-180, cameraNode.position.y))
        }
    }

    private func syncCameraControls() {
        if let command = dragState.cameraCommand {
            dragState.cameraCommand = nil
            switch command {
            case .zoomIn: zoom(by: 1.25, around: session.isConstructionModeActive ? CGPoint(x: constructionViewport.midX, y: constructionViewport.midY) : CGPoint(x: size.width / 2, y: size.height / 2))
            case .zoomOut: zoom(by: 0.8, around: session.isConstructionModeActive ? CGPoint(x: constructionViewport.midX, y: constructionViewport.midY) : CGPoint(x: size.width / 2, y: size.height / 2))
            case .fit:
                customCamera = false
                if let building = session.activeBuildingID.flatMap({ session.world.buildings[$0] }), session.isConstructionModeActive {
                    focusConstruction(on: building.plotID, animated: false)
                } else { focusOverview(animated: false) }
            }
        }
        if session.isConstructionModeActive, !dragState.isDragging,
           constructionViewport != lastViewport || editingContentRect != lastContentRect {
            if !customCamera, let id = session.activeBuildingID, let building = session.world.buildings[id] {
                focusConstruction(on: building.plotID, animated: false)
            } else {
                lastViewport = constructionViewport
                lastContentRect = editingContentRect ?? .zero
                clampCamera()
            }
        }
        let percent = Int((100 / cameraNode.xScale).rounded())
        if dragState.zoomPercent != percent { dragState.zoomPercent = percent }
    }

    private func move(camera target: CGPoint, scale: CGFloat, animated: Bool) {
        cameraNode.removeAction(forKey: "cameraFocus")
        if animated && !UIAccessibility.isReduceMotionEnabled {
            let action = SKAction.group([
                .move(to: target, duration: 0.45),
                .scale(to: scale, duration: 0.45)
            ])
            action.timingMode = .easeInEaseOut
            cameraNode.run(action, withKey: "cameraFocus")
        } else {
            cameraNode.position = target
            cameraNode.setScale(scale)
        }
    }

    // MARK: - Frame loop

    override func update(_ currentTime: TimeInterval) {
        defer { lastUpdateTime = currentTime }
        guard let session else { return }
        let dt = lastUpdateTime.map { currentTime - $0 } ?? 0
        if dt > 0, dt < 1 { session.tick(deltaSeconds: dt * testTimeScale) }

        syncPlots()
        syncMode()
        syncBuildings()
        syncCameraControls()
        syncDrag()
        processSceneEvents()
    }

    private func syncMode() {
        guard let session else { return }
        let active = session.isConstructionModeActive
        guard active != lastRenderedMode else { return }
        lastRenderedMode = active
        customCamera = false
        lastViewport = .zero
        if active, let buildingID = session.activeBuildingID, let building = session.world.buildings[buildingID] {
            focusConstruction(on: building.plotID, animated: true)
        } else {
            focusOverview(animated: true)
        }
    }

    private func syncBuildings() {
        guard let session else { return }
        for (plotID, plot) in zip(session.world.plots.map(\.id), session.world.plots) {
            guard let buildingID = plot.buildingID, let building = session.world.buildings[buildingID] else { continue }
            let node: BuildingNode
            if let existing = buildingNodes[buildingID] {
                node = existing
            } else {
                node = BuildingNode(buildingID: buildingID)
                node.position = plotWorldPositions[plotID] ?? .zero
                worldLayer.addChild(node)
                buildingNodes[buildingID] = node
            }
            guard let report = session.buildingReports[buildingID] else { continue }
            node.isHidden = session.isConstructionModeActive && buildingID != session.activeBuildingID
            node.setEditing(session.isConstructionModeActive && buildingID == session.activeBuildingID, topRow: building.footprint.maxY)
            node.sync(building: building, structural: report.structural, workers: session.world.workers)
        }

        // A building can now disappear mid-session (demolished, not just
        // never-placed), so its node must be cleaned up the same frame or a
        // ghost structure keeps rendering on an otherwise-empty plot.
        for (buildingID, node) in buildingNodes where session.world.buildings[buildingID] == nil {
            node.removeFromParent()
            buildingNodes.removeValue(forKey: buildingID)
        }
    }

    private func syncDrag() {
        guard let session, let dragState, session.isConstructionModeActive,
              let buildingID = session.activeBuildingID,
              let buildingNode = buildingNodes[buildingID] else {
            return
        }
        guard dragState.isDragging, let definitionID = dragState.draggingDefinitionID, let screenPoint = dragState.screenPoint,
              let definition = ModuleCatalog.definition(for: definitionID) else {
            buildingNode.hideGhost()
            return
        }
        let scenePoint = convertPoint(fromView: screenPoint)
        let localPoint = convert(scenePoint, to: buildingNode)
        let gridPosition = BuildingNode.nearestGridPosition(to: localPoint)
        let preview = session.preview(buildingID: buildingID, definitionID: definitionID, at: gridPosition)
        dragState.hoveredPosition = gridPosition
        dragState.preview = preview
        buildingNode.showGhost(at: gridPosition, definition: definition, isValid: preview?.isValid ?? false)
    }

    private func processSceneEvents() {
        guard let session else { return }
        for event in session.consumeSceneEvents() {
            switch event {
            case .structuralCollapse(let buildingID, let positions):
                buildingNodes[buildingID]?.collapse(positions: positions)
            case .moduleCompleted(let buildingID, let position):
                buildingNodes[buildingID]?.pulseModule(at: position)
            case .delivery(let buildingID, let job):
                spawnTruck(from: buildingID, job: job)
            default:
                break
            }
        }
    }

    private func spawnTruck(from buildingID: UUID, job: DeliveryJob) {
        guard !session.isConstructionModeActive, let origin = buildingNodes[buildingID]?.position else { return }
        let destination = CGPoint(x: origin.x, y: Self.plotBaseY - 90)
        let routedJob = DeliveryJob(
            id: job.id, resource: job.resource, amount: job.amount,
            originWorldPosition: origin, destinationWorldPosition: destination, speed: job.speed
        )
        let truck = TruckNode(resource: job.resource)
        worldLayer.addChild(truck)
        truck.drive(job: routedJob) { }
    }

    // MARK: - Touch handling

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view, dragState?.isDragging != true else { return }
        panStartViewLocation = touch.location(in: view)
        panStartCamera = cameraNode.position
        didPanThisGesture = (event?.allTouches?.count ?? 1) > 1
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let view, let start = panStartViewLocation,
              let cameraStart = panStartCamera, dragState?.isDragging != true else { return }
        let current = touch.location(in: view)
        let dx = current.x - start.x, dy = current.y - start.y
        if hypot(dx, dy) > Self.panTapThreshold { didPanThisGesture = true }
        guard didPanThisGesture else { return }
        cameraNode.removeAction(forKey: "cameraFocus")
        customCamera = true
        cameraNode.position = CGPoint(x: cameraStart.x - dx * cameraNode.xScale,
                                      y: cameraStart.y + dy * cameraNode.yScale)
        clampCamera()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = touches.first, let session else { return }
        defer { panStartViewLocation = nil; panStartCamera = nil }
        guard !didPanThisGesture, dragState?.isDragging != true else { return }
        let point = touch.location(in: worldLayer)
        if session.isConstructionModeActive, let id = session.activeBuildingID,
           let node = buildingNodes[id] {
            let local = convert(touch.location(in: self), to: node)
            let position = BuildingNode.nearestGridPosition(to: local)
            if session.world.buildings[id]?.module(at: position) != nil {
                session.pendingModuleRemovalPosition = position
            }
            return
        }
        for plot in session.world.plots {
            guard let base = plotWorldPositions[plot.id] else { continue }
            var rect = CGRect(x: base.x - 110, y: base.y - 110, width: 220, height: 220)
            if let building = session.world.building(on: plot.id), !building.isEmpty {
                let bounds = building.footprint
                let cells = CGRect(x: base.x + CGFloat(bounds.minX) * 72 - 36,
                                   y: base.y + CGFloat(bounds.minY) * 72 - 36,
                                   width: CGFloat(bounds.maxX - bounds.minX + 1) * 72,
                                   height: CGFloat(bounds.maxY - bounds.minY + 1) * 72)
                rect = rect.union(cells)
            }
            if rect.contains(point) { session.requestPlotInteraction(plot.id); return }
        }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        panStartViewLocation = nil
        panStartCamera = nil
        didPanThisGesture = true
    }
}
