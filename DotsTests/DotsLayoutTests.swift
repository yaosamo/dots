import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import Dots

final class DotsLayoutTests: XCTestCase {
    private let twoDots: [DotID] = [.mirror, .tasks]

    @MainActor
    func testCameraActivationAndDismissalAreIndependentStateChanges() {
        let pointer = LauncherPointerState()

        pointer.requestActivation(of: .mirror)
        XCTAssertEqual(pointer.requestedActivation, .mirror)
        XCTAssertEqual(pointer.activationSequence, 1)

        pointer.requestDismissal()
        XCTAssertNil(pointer.requestedActivation)
        XCTAssertEqual(pointer.dismissalSequence, 1)
    }

    @MainActor
    func testCameraCloseActivationBypassesOpenDebounce() {
        let pointer = LauncherPointerState()

        pointer.requestActivation(of: .mirror)
        let openSequence = pointer.activationSequence

        pointer.requestActivation(of: .mirror, ignoreDebounce: true)

        XCTAssertEqual(pointer.activationSequence, openSequence + 1)
    }

    func testRequestedDotAndCameraDiameters() {
        XCTAssertEqual(DotsLayout.nodeDiameter, 16)
        XCTAssertEqual(DotsLayout.cameraDiameter, 160)
        XCTAssertEqual(
            DotsLayout.cameraPanelSize,
            CGSize(width: 240, height: 240)
        )
        XCTAssertEqual(DotsLayout.cameraPanelGap, 16)
        XCTAssertEqual(DotsLayout.cameraMinimumSurfaceWidth, 240)
        XCTAssertEqual(
            CameraPanelStyle.rectangle.minimumPanelSize,
            CGSize(width: 240, height: 360)
        )
        XCTAssertEqual(
            CameraPanelStyle.circle.minimumPanelSize,
            CGSize(width: 240, height: 240)
        )
        XCTAssertEqual(DotsLayout.dotHitSlop, 12)
        XCTAssertEqual(DotsLayout.dotHitDiameter, 40)
        XCTAssertEqual(DotsLayout.cameraControlSize, 32)
        XCTAssertEqual(DotsLayout.cameraControlGap, 8)
        XCTAssertEqual(DotsLayout.cameraControlEdgePadding, 16)
        XCTAssertEqual(CameraPanelStyle.transitionDuration, 0.2)
        XCTAssertEqual(
            CameraPanelStyle.rectangle.size,
            CGSize(width: 240, height: 360)
        )
        XCTAssertEqual(CameraPanelStyle.circle.size, CGSize(width: 240, height: 240))
        XCTAssertEqual(
            CameraPanelStyle.rectangle.panelSize(for: .small),
            CGSize(width: 160, height: 240)
        )
        XCTAssertEqual(
            CameraPanelStyle.circle.panelSize(for: .small),
            CGSize(width: 160, height: 160)
        )
        XCTAssertEqual(
            CameraPanelStyle.rectangle.panelSize,
            CGSize(width: 240, height: 360)
        )
        XCTAssertEqual(CameraPanelStyle.circle.panelSize, CGSize(width: 240, height: 240))
        XCTAssertEqual(
            CameraPanelStyle.rectangle.size.width / CameraPanelStyle.rectangle.size.height,
            2.0 / 3.0,
            accuracy: 0.001
        )
        XCTAssertEqual(DotsLayout.launchCadence, 0.08)
        XCTAssertEqual(DotsLayout.taskListWidth, 434)
        XCTAssertEqual(DotsLayout.taskRowHeight, 51)
        XCTAssertEqual(DotsLayout.taskFontSize, 16)
        XCTAssertEqual(DotsLayout.taskRowSpacing, 6)
        XCTAssertEqual(DotsLayout.taskContentLeadingPadding, 12)
        XCTAssertEqual(DotsLayout.taskContentTrailingPadding, 16)
        XCTAssertEqual(DotsLayout.taskPanelPadding, 16)
        XCTAssertEqual(DotsLayout.taskCornerRadius, 18)
        XCTAssertEqual(
            DotsLayout.taskListContentSize(taskCount: 0),
            CGSize(width: 434, height: 51)
        )
        XCTAssertEqual(DotsLayout.taskListSize(taskCount: 0), CGSize(width: 466, height: 83))
        XCTAssertGreaterThanOrEqual(DotsLayout.taskControlHitSize, 22)
    }

    @MainActor
    func testCameraPanelStyleDefaultsToCircle() {
        let model = CameraPanelModel()

        model.resetStyle()

        XCTAssertEqual(model.style, .circle)
        XCTAssertEqual(model.style.size, CGSize(width: 240, height: 240))
    }

    @MainActor
    func testCameraPanelStyleTogglesBetweenCircleAndRectangle() {
        let model = CameraPanelModel()

        XCTAssertEqual(model.style, .circle)

        model.toggleStyle()
        XCTAssertEqual(model.style, .rectangle)

        model.toggleStyle()
        XCTAssertEqual(model.style, .circle)
    }

    @MainActor
    func testCameraPanelSizeTogglesBetweenStandardAndSmall() {
        let model = CameraPanelModel()

        XCTAssertEqual(model.sizeMode, .standard)
        XCTAssertEqual(model.style.panelSize(for: model.sizeMode), CGSize(width: 240, height: 240))

        model.toggleSize()
        XCTAssertEqual(model.sizeMode, .small)
        XCTAssertEqual(model.style.panelSize(for: model.sizeMode), CGSize(width: 160, height: 160))

        model.toggleSize()
        XCTAssertEqual(model.sizeMode, .standard)
    }

    @MainActor
    func testCameraPanelResetClearsAnInFlightTransition() {
        let model = CameraPanelModel()

        model.isTransitioning = true
        model.toggleSize()
        XCTAssertTrue(model.isTransitioning)

        model.resetStyle()

        XCTAssertFalse(model.isTransitioning)
        XCTAssertEqual(model.sizeMode, .standard)
    }

    func testCameraShapeAnimatesFromRoundedRectangleToCircle() {
        let frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let shape = MorphingCameraShape(progress: 0)

        XCTAssertEqual(shape.animatableData, 0)
        var circle = shape
        circle.animatableData = 1
        XCTAssertEqual(circle.animatableData, 1)
        XCTAssertEqual(circle.path(in: frame).boundingRect, frame)
    }

    func testTaskStackGrowsFromTheAddTaskRowUntilItsVisibleRowLimit() {
        let empty = DotsLayout.taskListSize(taskCount: 0)
        let oneTask = DotsLayout.taskListSize(taskCount: 1)
        let manyTasks = DotsLayout.taskListSize(taskCount: 100)

        XCTAssertEqual(empty, CGSize(width: 466, height: 83))
        XCTAssertEqual(oneTask, CGSize(width: 466, height: 140))
        XCTAssertEqual(manyTasks, CGSize(width: 466, height: 368))
    }

    func testTaskHitTestingUsesTheCompactStackBounds() {
        let emptyPanel = DotsLayout.hangingFrame(expansion: .tasks, taskCount: 0, dotIDs: twoDots)!
        let pointInsidePanel = CGPoint(
            x: emptyPanel.midX,
            y: emptyPanel.minY + 15
        )
        let pointBelowPanel = CGPoint(
            x: emptyPanel.midX,
            y: emptyPanel.maxY + 1
        )

        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                pointInsidePanel,
                expansion: .tasks,
                taskCount: 0,
                dotIDs: twoDots
            )
        )
        XCTAssertFalse(
            DotsLayout.containsInteractiveContent(
                pointBelowPanel,
                expansion: .tasks,
                taskCount: 0,
                dotIDs: twoDots
            )
        )
    }

    func testCollapsedGeometry() {
        XCTAssertEqual(DotsLayout.rowContentSize(dotCount: 2), CGSize(width: 48, height: 16))
        XCTAssertEqual(
            DotsLayout.canvasSize(cameraOffset: .zero, dotIDs: twoDots),
            CGSize(width: 504, height: 550)
        )
    }

    func testCameraExpandsFromTheVisible16PointDot() throws {
        let camera = try XCTUnwrap(DotsLayout.hangingFrame(expansion: .camera, dotIDs: twoDots))
        let mirrorDot = DotsLayout.nodeFrames(expansion: .camera, dotIDs: twoDots)[0]

        XCTAssertEqual(camera.midX, mirrorDot.midX)
        XCTAssertEqual(camera.minY, mirrorDot.maxY)
        XCTAssertEqual(camera.size, CGSize(width: 160, height: 160))
        XCTAssertTrue(
            DotsLayout.visibleNodeFrames(expansion: .camera, dotIDs: twoDots)
                .contains(DotsLayout.nodeFrames(expansion: .camera, dotIDs: twoDots)[0])
        )
    }

    func testCameraPanelLeavesPaddingBetweenTheDotAndWindow() {
        let anchor = CGRect(x: 100, y: 800, width: 16, height: 16)
        let rectangle = DotsLayout.cameraPanelFrame(
            anchoredTo: anchor,
            style: .rectangle
        )
        let circle = DotsLayout.cameraPanelFrame(
            anchoredTo: anchor,
            style: .circle
        )

        XCTAssertEqual(
            rectangle.minX,
            anchor.midX - (CameraPanelStyle.rectangle.size.width / 2)
        )
        XCTAssertEqual(rectangle.maxY, anchor.minY - DotsLayout.cameraPanelGap)
        XCTAssertEqual(rectangle.size, CameraPanelStyle.rectangle.panelSize)
        XCTAssertEqual(
            circle.minX,
            anchor.midX - (CameraPanelStyle.circle.size.width / 2)
        )
        XCTAssertEqual(circle.maxY, anchor.minY - DotsLayout.cameraPanelGap)
        XCTAssertEqual(circle.size, CameraPanelStyle.circle.panelSize)
    }

    func testCameraResizeKeepsItsCenterAndTopEdgeStable() {
        let currentFrame = CGRect(x: 200, y: 300, width: 160, height: 160)
        let targetSize = CGSize(width: 240, height: 240)
        let targetFrame = DotsLayout.cameraPanelResizeFrame(
            from: currentFrame,
            to: targetSize
        )

        XCTAssertEqual(targetFrame.midX, currentFrame.midX)
        XCTAssertEqual(targetFrame.maxY, currentFrame.maxY)
        XCTAssertEqual(targetFrame.size, targetSize)
    }

    func testLaunchFrameStartsAboveThePanelWithoutChangingDotSize() {
        let docked = CGRect(x: 80, y: 12, width: 16, height: 16)
        let start = DotsLayout.launchStartFrame(docked: docked, canvasHeight: 40)

        XCTAssertEqual(start.minX, docked.minX)
        XCTAssertEqual(start.minY, 56)
        XCTAssertEqual(start.size, docked.size)
    }

    func testTaskPanelIsHorizontallyCenteredBelowTheDotRow() {
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .tasks, taskCount: 0, dotIDs: twoDots),
            CGRect(x: 19, y: 32, width: 466, height: 83)
        )
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .tasks, taskCount: 0, dotIDs: twoDots)?.midX,
            DotsLayout.rowCenterX(cameraOffset: .zero, dotIDs: twoDots)
        )
        XCTAssertTrue(
            DotsLayout.visibleNodeFrames(expansion: .tasks, dotIDs: twoDots)
                .contains(DotsLayout.nodeFrames(expansion: .tasks, dotIDs: twoDots)[1])
        )
    }

    func testCollapsedDotsKeepRequestedFrames() {
        let frames = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0], CGRect(x: 228, y: 8, width: 16, height: 16))
        XCTAssertEqual(frames[1], CGRect(x: 260, y: 8, width: 16, height: 16))
    }

    func testFeaturePanelsKeepTheDotRowFixedForEveryState() {
        let collapsed = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)
        let camera = DotsLayout.nodeFrames(expansion: .camera, dotIDs: twoDots)
        let tasks = DotsLayout.nodeFrames(expansion: .tasks, dotIDs: twoDots)

        XCTAssertEqual(camera, collapsed)
        XCTAssertEqual(tasks, collapsed)
    }

    func testExpandedPanelStaysCenteredWithTheDotRow() {
        let frames = DotsLayout.nodeFrames(expansion: .tasks, dotIDs: twoDots)
        let list = DotsLayout.hangingFrame(expansion: .tasks, dotIDs: twoDots)!

        XCTAssertEqual(frames[1], CGRect(x: 260, y: 8, width: 16, height: 16))
        XCTAssertEqual(list.minX, 19)
        XCTAssertGreaterThan(list.minY, frames[1].maxY)
        XCTAssertEqual(
            list.midX,
            DotsLayout.rowCenterX(cameraOffset: .zero, dotIDs: twoDots)
        )
    }

    func testHitTestingIgnoresTransparentPadding() throws {
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 2, y: 2), expansion: .none, dotIDs: twoDots))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 300, y: 16), expansion: .none, dotIDs: twoDots))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 2, y: 2), expansion: .camera, dotIDs: twoDots))
        let camera = try XCTUnwrap(DotsLayout.hangingFrame(expansion: .camera, dotIDs: twoDots))
        XCTAssertFalse(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: camera.maxX + 2, y: camera.midY),
                expansion: .camera,
                dotIDs: twoDots
            )
        )
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 24, y: 16), expansion: .tasks, dotIDs: twoDots))
    }

    func testHitTestingAcceptsDotsAndHangingWidgets() {
        let dots = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)
        let camera = DotsLayout.hangingFrame(expansion: .camera, dotIDs: twoDots)!
        let tasks = DotsLayout.hangingFrame(expansion: .tasks, taskCount: 0, dotIDs: twoDots)!
        let pointOutsideDots = CGPoint(
            x: dots[1].maxX + DotsLayout.dotHitSlop + 1,
            y: dots[1].midY
        )

        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: dots[0].midX, y: dots[0].midY),
                expansion: .none,
                dotIDs: twoDots
            )
        )
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 120, y: 2), expansion: .none, dotIDs: twoDots))
        XCTAssertFalse(
            DotsLayout.containsInteractiveContent(
                pointOutsideDots,
                expansion: .none,
                dotIDs: twoDots
            )
        )
        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: camera.midX, y: camera.midY),
                expansion: .camera,
                dotIDs: twoDots
            )
        )
        XCTAssertFalse(
            DotsLayout.containsInteractiveContent(
                pointOutsideDots,
                expansion: .camera,
                dotIDs: twoDots
            )
        )
        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: dots[0].midX, y: dots[0].midY),
                expansion: .tasks,
                dotIDs: twoDots
            )
        )
        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: tasks.midX, y: tasks.midY),
                expansion: .tasks,
                taskCount: 0,
                dotIDs: twoDots
            )
        )
    }

    func testPanelSitsFlushWithUsableScreenEdgeOnFirstPlacement() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = DotsLayout.panelFrame(visibleFrame: visible, dotIDs: twoDots)

        XCTAssertEqual(frame.maxY, visible.maxY)
        XCTAssertEqual(frame.minX + DotsLayout.rowCenterX(cameraOffset: .zero, dotIDs: twoDots), visible.midX)
        XCTAssertEqual(frame.size, DotsLayout.canvasSize(cameraOffset: .zero, dotIDs: twoDots))
    }

    func testEveryFeatureUsesOneStablePanelFrame() {
        let visible = CGRect(x: 100, y: 50, width: 1440, height: 900)
        let frame = DotsLayout.panelFrame(visibleFrame: visible, dotIDs: twoDots)

        for state in [DotExpansion.none, .camera, .tasks] {
            let sourceIndex = state == .camera ? 0 : 1
            let source = DotsLayout.nodeFrames(expansion: state, dotIDs: twoDots)[sourceIndex]
            if let destination = DotsLayout.hangingFrame(expansion: state, dotIDs: twoDots) {
                let expectedCenter = state == .tasks
                    ? DotsLayout.rowCenterX(cameraOffset: .zero, dotIDs: twoDots)
                    : source.midX
                XCTAssertEqual(frame.minX + destination.midX, frame.minX + expectedCenter)
            }
        }
    }

    func testDraggingCameraLeftKeepsTheDotRowInPlace() {
        let offset = CGSize(width: -100, height: 0)
        let visible = CGRect(x: 100, y: 50, width: 1440, height: 900)
        let docked = DotsLayout.panelFrame(visibleFrame: visible, dotIDs: twoDots)
        let dragged = DotsLayout.panelFrame(
            visibleFrame: visible,
            cameraOffset: offset,
            previousCameraOffset: .zero,
            keepingTopOf: docked,
            dotIDs: twoDots
        )
        let dockedDot = docked.minX + DotsLayout.nodeFrames(expansion: .camera, dotIDs: twoDots)[0].minX
        let draggedDot = dragged.minX
            + DotsLayout.nodeFrames(expansion: .camera, cameraOffset: offset, dotIDs: twoDots)[0].minX

        XCTAssertEqual(dragged.maxY, docked.maxY)
        XCTAssertEqual(draggedDot, dockedDot)
        XCTAssertGreaterThanOrEqual(dragged.width, docked.width)
    }

    func testDraggingCameraDownExtendsTheCanvas() {
        let offset = CGSize(width: 0, height: 400)
        XCTAssertGreaterThan(
            DotsLayout.canvasSize(cameraOffset: offset, dotIDs: twoDots).height,
            DotsLayout.canvasSize(cameraOffset: .zero, dotIDs: twoDots).height
        )
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .camera, cameraOffset: offset, dotIDs: twoDots)?.minY,
            424
        )
    }

    func testHitTestingFollowsADraggedCameraAndIgnoresEmptySpaceAboveDots() {
        let offset = CGSize(width: 80, height: 40)
        let hang = DotsLayout.hangingFrame(expansion: .camera, cameraOffset: offset, dotIDs: twoDots)!
        let firstDot = DotsLayout.nodeFrames(expansion: .camera, cameraOffset: offset, dotIDs: twoDots)[0]
        let emptySpaceAboveDot = CGPoint(
            x: firstDot.midX,
            y: firstDot.minY - DotsLayout.dotHitSlop - 1
        )

        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: hang.midX, y: hang.midY),
                expansion: .camera,
                cameraOffset: offset,
                dotIDs: twoDots
            )
        )
        XCTAssertFalse(
            DotsLayout.containsInteractiveContent(
                emptySpaceAboveDot,
                expansion: .camera,
                cameraOffset: offset,
                dotIDs: twoDots
            )
        )
    }

    func testLayoutSupportsTheFiveDotMaximum() {
        let ids: [DotID] = [.mirror, .tasks, .redPen, .screenToText, .clipboard]

        XCTAssertEqual(DotsLayout.nodeFrames(expansion: .none, dotIDs: ids).count, 5)
        XCTAssertEqual(
            DotsLayout.rowContentSize(dotCount: ids.count),
            CGSize(width: 144, height: 16)
        )
    }

    func testDotHitTargetIsLargerThanTheVisibleFill() {
        let firstDot = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)[0]
        let pointOutsideFill = CGPoint(x: firstDot.minX - 12, y: firstDot.midY)
        let pointOutsideHitTarget = CGPoint(x: firstDot.minX - 13, y: firstDot.midY)

        XCTAssertFalse(firstDot.contains(pointOutsideFill))
        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                pointOutsideFill,
                expansion: .none,
                dotIDs: twoDots
            )
        )
        XCTAssertFalse(
            DotsLayout.containsInteractiveContent(
                pointOutsideHitTarget,
                expansion: .none,
                dotIDs: twoDots
            )
        )
    }

    func testExpandedDotHitTargetsPreferTheNearestDot() {
        let frames = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)

        XCTAssertEqual(
            DotsLayout.dotID(
                at: CGPoint(x: frames[1].midX - 7, y: frames[0].midY),
                expansion: .none,
                dotIDs: twoDots
            ),
            .tasks
        )
    }

    func testStableHitTestingResolvesOnlyRegisteredDots() {
        let frames = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)

        XCTAssertEqual(
            DotsLayout.dotID(
                at: CGPoint(x: frames[0].minX - 12, y: frames[0].midY),
                expansion: .none,
                dotIDs: twoDots
            ),
            .mirror
        )
        XCTAssertEqual(
            DotsLayout.dotID(
                at: CGPoint(x: frames[1].midX, y: 4),
                expansion: .none,
                dotIDs: twoDots
            ),
            .tasks
        )
        XCTAssertNil(
            DotsLayout.dotID(
                at: CGPoint(x: 300, y: 16),
                expansion: .none,
                dotIDs: twoDots
            )
        )
    }
}

@MainActor
final class DotOrbViewTests: XCTestCase {
    func testOrbHostsASwiftUICircleThatResizesWithItsFrame() {
        let orb = DotOrbView(frame: .zero)
        orb.frame = CGRect(x: 0, y: 0, width: 160, height: 160)
        orb.layoutSubtreeIfNeeded()

        XCTAssertEqual(orb.subviews.count, 1)
        XCTAssertEqual(orb.subviews[0].frame, orb.bounds)
    }

    func testOrbCanSwitchMaterialWithoutChangingItsHitView() {
        let orb = DotOrbView(frame: CGRect(x: 0, y: 0, width: 16, height: 16))

        orb.material = .regular

        XCTAssertEqual(orb.subviews.count, 1)
        XCTAssertEqual(orb.subviews[0].frame, orb.bounds)
    }
}

@MainActor
final class DotMaterialSettingsTests: XCTestCase {
    func testLiquidIsTheDefaultMaterial() throws {
        let suiteName = "DotMaterialSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertEqual(DotAppearanceSettings(defaults: defaults).material, .liquid)
    }

    func testMaterialSelectionPersists() throws {
        let suiteName = "DotMaterialSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = DotAppearanceSettings(defaults: defaults)
        settings.material = .thin

        XCTAssertEqual(
            DotAppearanceSettings(defaults: defaults).material,
            .thin
        )
    }
}

final class CameraLogicTests: XCTestCase {
    func testAuthorizationRoutes() {
        XCTAssertEqual(CameraAuthorization.action(for: .authorized), .start)
        XCTAssertEqual(CameraAuthorization.action(for: .notDetermined), .requestAccess)
        XCTAssertEqual(CameraAuthorization.action(for: .denied), .denied)
        XCTAssertEqual(CameraAuthorization.action(for: .restricted), .denied)
    }

    func testDevicePickerPrefersBuiltInFrontOverContinuity() {
        let continuity = CameraDeviceCandidate(
            uniqueID: "phone",
            kind: .continuity,
            position: .unspecified
        )
        let builtIn = CameraDeviceCandidate(
            uniqueID: "facetime",
            kind: .builtInWideAngle,
            position: .unspecified
        )
        let front = CameraDeviceCandidate(
            uniqueID: "front",
            kind: .builtInWideAngle,
            position: .front
        )

        XCTAssertEqual(CameraDevicePicker.preferred(from: [continuity, builtIn])?.uniqueID, "facetime")
        XCTAssertEqual(CameraDevicePicker.preferred(from: [continuity, builtIn, front])?.uniqueID, "front")
    }

    func testDevicePickerPrefersContinuityOverExternal() {
        let continuity = CameraDeviceCandidate(
            uniqueID: "phone",
            kind: .continuity,
            position: .unspecified
        )
        let external = CameraDeviceCandidate(
            uniqueID: "usb",
            kind: .external,
            position: .unspecified
        )

        XCTAssertEqual(CameraDevicePicker.preferred(from: [external, continuity])?.uniqueID, "phone")
    }

    func testDevicePickerReturnsNilWhenEmpty() {
        XCTAssertNil(CameraDevicePicker.preferred(from: []))
    }

    func testIdleAndRunningHaveNoOverlayWhilePermissionShowsSpinner() {
        XCTAssertEqual(CameraSession.Status.idle.overlay, .none)
        XCTAssertEqual(CameraSession.Status.running.overlay, .none)
        XCTAssertEqual(CameraSession.Status.requestingPermission.overlay, .spinner)
        XCTAssertEqual(CameraSession.Status.starting.overlay, .spinner)
        XCTAssertEqual(CameraSession.Status.denied.overlay, .unavailable)
        XCTAssertEqual(CameraSession.Status.failed.overlay, .unavailable)
        XCTAssertEqual(CameraSession.Status.unavailable.overlay, .unavailable)
    }

    func testAuthorizedStartIsNotDescribedAsWaitingForPermission() {
        XCTAssertEqual(CameraSession.Status.starting.accessibilityDescription, "Starting camera")
        XCTAssertEqual(
            CameraSession.Status.requestingPermission.accessibilityDescription,
            "Waiting for camera permission"
        )
        XCTAssertEqual(CameraSession.Status.idle.accessibilityDescription, "Camera inactive")
    }

    func testStopInvalidatesAnInFlightStartToken() {
        var generation = CameraGeneration()
        let startToken = generation.start()
        let stopToken = generation.stop()

        XCTAssertFalse(generation.isCurrent(startToken))
        XCTAssertTrue(generation.isCurrent(stopToken))
        XCTAssertFalse(generation.wantsToRun)
    }

    func testRepeatedStartDoesNotCreateAnotherCameraLaunchRequest() {
        var generation = CameraGeneration()
        let firstStart = generation.startIfNeeded()
        let repeatedStart = generation.startIfNeeded()

        XCTAssertEqual(firstStart, 1)
        XCTAssertNil(repeatedStart)
        XCTAssertTrue(generation.isCurrent(1))
        XCTAssertTrue(generation.wantsToRun)
    }

    func testReopenInvalidatesAQueuedStopToken() {
        var generation = CameraGeneration()
        _ = generation.start()
        let stopToken = generation.stop()
        let reopenToken = generation.start()

        XCTAssertFalse(generation.isCurrent(stopToken))
        XCTAssertTrue(generation.isCurrent(reopenToken))
        XCTAssertTrue(generation.wantsToRun)
    }

    func testPreviewPresetPrefersVGAWhenAvailable() {
        XCTAssertEqual(
            CameraPreviewPreset.preferred { $0 == .vga640x480 || $0 == .high },
            .vga640x480
        )
    }

    func testPreviewPresetFallsBackWhenVGAIsUnavailable() {
        XCTAssertEqual(
            CameraPreviewPreset.preferred { $0 == .medium || $0 == .high },
            .medium
        )
    }

    func testMediaServicesResetRetriesOnce() {
        let error = NSError(
            domain: AVFoundationErrorDomain,
            code: CameraRuntimeErrorPolicy.mediaServicesWereResetCode
        )

        XCTAssertTrue(CameraRuntimeErrorPolicy.shouldRetry(alreadyRetried: false, error: error))
        XCTAssertFalse(CameraRuntimeErrorPolicy.shouldRetry(alreadyRetried: true, error: error))
    }

    func testRapidReopenRuntimeErrorRetriesOnce() {
        let error = NSError(domain: AVFoundationErrorDomain, code: -11800)

        XCTAssertTrue(CameraRuntimeErrorPolicy.shouldRetry(alreadyRetried: false, error: error))
        XCTAssertFalse(CameraRuntimeErrorPolicy.shouldRetry(alreadyRetried: true, error: error))
        XCTAssertFalse(CameraRuntimeErrorPolicy.isRecoverable(nil))
    }
}

final class TaskStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: TaskStore!

    override func setUp() {
        super.setUp()
        suiteName = "DotsTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = TaskStore(defaults: defaults, storageKey: "tasks")
    }

    override func tearDown() {
        if let suiteName {
            defaults.removePersistentDomain(forName: suiteName)
        }
        super.tearDown()
    }

    func testAddInsertsATaskWithTheGivenTitle() {
        let item = store.add("Buy milk")

        XCTAssertEqual(store.items.count, 1)
        XCTAssertEqual(item?.title, "Buy milk")
        XCTAssertEqual(item?.isDone, false)
    }

    func testNewTasksAppearBeforeExistingTasks() {
        _ = store.add("Existing")
        _ = store.add("New")

        XCTAssertEqual(store.visibleItems.map(\.title), ["New", "Existing"])
    }

    func testAddIgnoresBlankTitles() {
        XCTAssertNil(store.add("   "))
        XCTAssertTrue(store.items.isEmpty)
    }

    func testToggleMarksATaskCompleteThenIncomplete() {
        let item = store.add("Write tests")!

        store.toggle(item.id)
        XCTAssertTrue(store.items[0].isDone)

        store.toggle(item.id)
        XCTAssertFalse(store.items[0].isDone)
    }

    func testRemoveDeletesTheMatchingTask() {
        let keep = store.add("Keep")!
        let drop = store.add("Drop")!

        store.remove(drop.id)

        XCTAssertEqual(store.items.map(\.id), [keep.id])
    }

    func testTasksSurviveANewStoreOnTheSameDefaults() {
        store.add("Persist me")

        let reloaded = TaskStore(defaults: defaults, storageKey: "tasks")

        XCTAssertEqual(reloaded.items.map(\.title), ["Persist me"])
        XCTAssertEqual(reloaded.items.first?.isDone, false)
    }

    func testAddDraftClearsTheComposerAfterInserting() {
        store.draft = "From field"
        store.addDraft()

        XCTAssertEqual(store.items.map(\.title), ["From field"])
        XCTAssertEqual(store.draft, "")
    }

    func testAddDraftLeavesComposerAloneWhenBlank() {
        store.draft = "  "
        store.addDraft()

        XCTAssertTrue(store.items.isEmpty)
        XCTAssertEqual(store.draft, "  ")
    }

    func testBackspaceOnAddDraftRecallsTheNewestTaskForEditing() {
        _ = store.add("First")
        let newest = store.add("Newest")!

        XCTAssertTrue(store.handleBackspaceOnAddDraft())

        XCTAssertEqual(store.editingTaskID, newest.id)
        XCTAssertEqual(store.draft, "Newest")
    }

    func testBackspaceInEmptyComposerRecallsThePreviousTaskForEditing() {
        let keep = store.add("Keep")!
        let edit = store.add("Edit me")!

        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())

        XCTAssertEqual(store.draft, "Edit me")
        XCTAssertEqual(store.editingTaskID, edit.id)
        XCTAssertEqual(store.visibleItems.map(\.id), [edit.id, keep.id])
        XCTAssertEqual(store.items.map(\.id), [edit.id, keep.id])
    }

    func testBackspaceInEmptyComposerDoesNothingWithoutPreviousTasks() {
        XCTAssertFalse(store.handleBackspaceOnEmptyDraft())
        XCTAssertNil(store.editingTaskID)
        XCTAssertEqual(store.draft, "")
    }

    func testSubmittingRecalledTaskUpdatesItInsteadOfAddingAnotherTask() {
        let item = store.add("Before")!
        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())
        store.draft = "After"

        store.addDraft()

        XCTAssertEqual(store.items, [DotTask(id: item.id, title: "After", isDone: false)])
        XCTAssertNil(store.editingTaskID)
        XCTAssertEqual(store.draft, "")
    }

    func testDeletingRecalledTaskImmediatelyRecallsTheTaskBeforeIt() {
        let keep = store.add("Keep")!
        _ = store.add("Delete me")!
        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())
        store.draft = ""

        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())

        XCTAssertEqual(store.items.map(\.id), [keep.id])
        XCTAssertEqual(store.editingTaskID, keep.id)
        XCTAssertEqual(store.draft, "Keep")
        XCTAssertEqual(store.visibleItems.map(\.id), [keep.id])
        let reloaded = TaskStore(defaults: defaults, storageKey: "tasks")
        XCTAssertEqual(reloaded.items.map(\.id), [keep.id])
    }

    func testRepeatedEmptyBackspaceWalksBackwardUntilNoTasksRemain() {
        _ = store.add("First")!
        _ = store.add("Second")!
        _ = store.add("Third")!

        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())
        XCTAssertEqual(store.draft, "Third")

        store.draft = ""
        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())
        XCTAssertEqual(store.draft, "Second")

        store.draft = ""
        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())
        XCTAssertEqual(store.draft, "First")

        store.draft = ""
        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())
        XCTAssertTrue(store.items.isEmpty)
        XCTAssertNil(store.editingTaskID)
        XCTAssertEqual(store.draft, "")
    }

    func testArrowSelectionStartsAtTheNearestTaskAndStopsAtListEdges() {
        let first = store.add("First")!
        let second = store.add("Second")!

        XCTAssertTrue(store.moveTaskSelection(.up))
        XCTAssertEqual(store.selectedTaskID, first.id)
        XCTAssertTrue(store.moveTaskSelection(.up))
        XCTAssertEqual(store.selectedTaskID, second.id)
        XCTAssertTrue(store.moveTaskSelection(.up))
        XCTAssertEqual(store.selectedTaskID, second.id)

        store.clearTaskSelection()

        XCTAssertTrue(store.moveTaskSelection(.down))
        XCTAssertEqual(store.selectedTaskID, second.id)
        XCTAssertTrue(store.moveTaskSelection(.down))
        XCTAssertEqual(store.selectedTaskID, first.id)
        XCTAssertTrue(store.moveTaskSelection(.down))
        XCTAssertEqual(store.selectedTaskID, first.id)
    }

    func testEditingTheKeyboardSelectedTaskLoadsItIntoTheComposer() {
        _ = store.add("First")!
        let second = store.add("Second")!
        XCTAssertTrue(store.moveTaskSelection(.down))

        XCTAssertTrue(store.editSelectedTask())

        XCTAssertEqual(store.editingTaskID, second.id)
        XCTAssertNil(store.selectedTaskID)
        XCTAssertEqual(store.draft, "Second")
        XCTAssertEqual(store.visibleItems.map(\.title), ["Second", "First"])
    }

    func testEditingATaskByIDKeepsItVisibleForInlineEditing() {
        let item = store.add("Click to edit")!

        XCTAssertTrue(store.editTask(item.id))

        XCTAssertEqual(store.editingTaskID, item.id)
        XCTAssertEqual(store.draft, "Click to edit")
        XCTAssertEqual(store.visibleItems.map(\.id), [item.id])
    }
}

@MainActor
final class TaskComposerFocusTests: XCTestCase {
    func testTaskListHitTestIncludesSpacingBetweenRows() throws {
        let suiteName = "TaskListInteractionTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TaskStore(defaults: defaults, storageKey: "tasks")
        _ = store.add("First task")
        _ = store.add("Second task")

        let size = DotsLayout.taskListSize(taskCount: store.items.count)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.orderOut(nil) }
        let hostingView = NSHostingView(rootView: TaskListView(store: store))
        hostingView.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()

        let yFromTop = DotsLayout.taskPanelPadding
            + DotsLayout.taskRowHeight
            + (DotsLayout.taskRowSpacing / 2)
        let gapPoint = CGPoint(
            x: size.width / 2,
            y: hostingView.isFlipped ? yFromTop : size.height - yFromTop
        )

        XCTAssertNotNil(hostingView.hitTest(gapPoint))
    }

    func testTaskListScrollViewportCanMovePastItsTopOffset() throws {
        let suiteName = "TaskListScrollTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TaskStore(defaults: defaults, storageKey: "tasks")
        for index in 0..<6 {
            _ = store.add("Task \(index)")
        }

        let size = DotsLayout.taskListSize(taskCount: store.items.count)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.orderOut(nil) }
        let hostingView = NSHostingView(rootView: TaskListView(store: store))
        hostingView.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(
            firstDescendant(of: NSScrollView.self, in: hostingView)
        )
        scrollView.layoutSubtreeIfNeeded()
        let viewportHeight = scrollView.contentView.bounds.height
        let documentHeight = try XCTUnwrap(scrollView.documentView?.frame.height)

        XCTAssertGreaterThan(documentHeight, viewportHeight)

        scrollView.contentView.scroll(to: NSPoint(x: 0, y: 40))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        XCTAssertGreaterThan(scrollView.contentView.bounds.minY, 0)
    }

    func testTaskListViewportHitTestResolvesInsideItsScrollView() throws {
        let suiteName = "TaskListHitTestTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TaskStore(defaults: defaults, storageKey: "tasks")
        for index in 0..<6 {
            _ = store.add("Task \(index)")
        }

        let size = DotsLayout.taskListSize(taskCount: store.items.count)
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.orderOut(nil) }
        let hostingView = NSHostingView(rootView: TaskListView(store: store))
        hostingView.frame = panel.contentView?.bounds ?? NSRect(origin: .zero, size: size)
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()

        let scrollView = try XCTUnwrap(
            firstDescendant(of: NSScrollView.self, in: hostingView)
        )
        let viewportPoint = hostingView.convert(
            NSPoint(
                x: scrollView.contentView.bounds.midX,
                y: scrollView.contentView.bounds.midY
            ),
            from: scrollView.contentView
        )
        let hitView = try XCTUnwrap(hostingView.hitTest(viewportPoint))

        XCTAssertTrue(
            hitView === scrollView || hitView.isDescendant(of: scrollView),
            "Expected viewport hit to stay inside the task scroll view, got \(hitView)"
        )
    }

    @MainActor
    func testTaskComposerCellUsesACompactVerticallyCenteredTitleRect() {
        let cell = VerticallyCenteredTextFieldCell(textCell: "Add a task")
        cell.font = .systemFont(ofSize: DotsLayout.taskFontSize, weight: .regular)
        let bounds = NSRect(x: 0, y: 0, width: 300, height: DotsLayout.taskRowHeight)

        let titleRect = cell.titleRect(forBounds: bounds)
        let editorRect = cell.editorTextRect(forBounds: bounds)

        XCTAssertLessThan(titleRect.height, bounds.height)
        XCTAssertEqual(titleRect.midY, bounds.midY, accuracy: 0.5)
        XCTAssertEqual(
            editorRect.midY,
            titleRect.midY + DotsLayout.taskEditingTextVerticalOffset,
            accuracy: 0.5
        )
    }

    func testTaskComposerFieldEditorSupportsUndo() throws {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 180, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.orderOut(nil) }
        let field = FocusableTextField(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = field
        panel.orderFrontRegardless()
        XCTAssertTrue(panel.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)

        editor.insertText("Draft", replacementRange: NSRange(location: 0, length: 0))

        XCTAssertTrue(editor.allowsUndo)
        XCTAssertEqual(editor.string, "Draft")
        XCTAssertTrue(editor.undoManager?.canUndo == true)

        editor.undoManager?.undo()

        XCTAssertEqual(editor.string, "")
    }

    func testFieldEditorNavigationOpensTheSelectedTaskForEditing() throws {
        let suiteName = "TaskComposerNavigationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TaskStore(defaults: defaults, storageKey: "tasks")
        let firstTask = try XCTUnwrap(store.add("First task"))
        _ = try XCTUnwrap(store.add("Second task"))

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 228),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.orderOut(nil) }
        let hostingView = NSHostingView(rootView: TaskListView(store: store))
        hostingView.frame = panel.contentView?.bounds ?? .zero
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()

        let focusSettled = expectation(description: "Task composer focus settles")
        DispatchQueue.main.async {
            focusSettled.fulfill()
        }
        wait(for: [focusSettled], timeout: 1)

        let addField = try XCTUnwrap(firstDescendant(of: FocusableTextField.self, in: hostingView))
        XCTAssertTrue(panel.makeFirstResponder(addField))
        let editor = try XCTUnwrap(addField.currentEditor() as? NSTextView)

        editor.keyDown(with: try keyEvent("\u{F700}", keyCode: 126, window: panel))
        XCTAssertEqual(store.selectedTaskID, firstTask.id)
        editor.keyDown(with: try keyEvent("\u{F700}", keyCode: 126, window: panel))
        XCTAssertEqual(store.selectedTaskID, store.items.first?.id)
        editor.keyDown(with: try keyEvent("\u{F701}", keyCode: 125, window: panel))
        XCTAssertEqual(store.selectedTaskID, firstTask.id)

        editor.keyDown(with: try keyEvent("\r", keyCode: 36, window: panel))

        let editingField = try waitForDescendant(
            of: FocusableTextField.self,
            in: hostingView,
            matching: { $0.stringValue == "First task" }
        )

        XCTAssertEqual(store.editingTaskID, firstTask.id)
        XCTAssertNil(store.selectedTaskID)
        XCTAssertEqual(store.draft, "First task")
        XCTAssertEqual(editingField.stringValue, "First task")
        XCTAssertEqual(
            try XCTUnwrap(editingField.currentEditor() as? NSTextView).selectedRange(),
            NSRange(location: "First task".utf16.count, length: 0)
        )
    }

    func testBackspaceFromActiveFieldEditorWalksBackwardThroughTasks() throws {
        let suiteName = "TaskComposerFocusTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = TaskStore(defaults: defaults, storageKey: "tasks")
        let firstTask = try XCTUnwrap(store.add("First task"))
        _ = store.add("Second task")

        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 300, height: 168),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        defer { panel.orderOut(nil) }
        let hostingView = NSHostingView(rootView: TaskListView(store: store))
        hostingView.frame = panel.contentView?.bounds ?? .zero
        panel.contentView = hostingView
        panel.orderFrontRegardless()
        hostingView.layoutSubtreeIfNeeded()

        let focusSettled = expectation(description: "Task composer focus settles")
        DispatchQueue.main.async {
            focusSettled.fulfill()
        }
        wait(for: [focusSettled], timeout: 1)

        let addField = try XCTUnwrap(firstDescendant(of: FocusableTextField.self, in: hostingView))
        XCTAssertTrue(panel.makeFirstResponder(addField))
        let addEditor = try XCTUnwrap(addField.currentEditor() as? NSTextView)
        XCTAssertTrue(panel.firstResponder === addEditor)
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: panel.windowNumber,
                context: nil,
                characters: "\u{8}",
                charactersIgnoringModifiers: "\u{8}",
                isARepeat: false,
                keyCode: 51
            )
        )

        addEditor.keyDown(with: event)

        let editingField = try waitForDescendant(
            of: FocusableTextField.self,
            in: hostingView,
            matching: { $0.stringValue == "Second task" }
        )
        let editor = try XCTUnwrap(editingField.currentEditor() as? NSTextView)

        XCTAssertEqual(store.draft, "Second task")
        XCTAssertEqual(editingField.stringValue, "Second task")
        XCTAssertEqual(
            editor.selectedRange(),
            NSRange(location: "Second task".utf16.count, length: 0)
        )

        for _ in "Second task" {
            editor.keyDown(with: event)
        }
        XCTAssertEqual(store.draft, "")

        editor.keyDown(with: event)

        XCTAssertEqual(store.items, [firstTask])
        XCTAssertEqual(store.editingTaskID, firstTask.id)
        XCTAssertEqual(store.draft, "First task")
        let recalledField = try waitForDescendant(
            of: FocusableTextField.self,
            in: hostingView,
            matching: { $0.stringValue == "First task" }
        )
        XCTAssertEqual(recalledField.stringValue, "First task")
        XCTAssertEqual(
            try XCTUnwrap(recalledField.currentEditor() as? NSTextView).selectedRange(),
            NSRange(location: "First task".utf16.count, length: 0)
        )
    }

    func testBackspacePositionsCaretAtEndOfRecalledTask() throws {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 180, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let field = FocusableTextField(frame: panel.contentView?.bounds ?? .zero)
        panel.contentView = field
        panel.orderFrontRegardless()
        panel.makeFirstResponder(field)
        field.onDeleteBackwardWhenEmpty = { "Previous task" }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{8}",
                charactersIgnoringModifiers: "\u{8}",
                isARepeat: false,
                keyCode: 51
            )
        )

        field.keyDown(with: event)

        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertEqual(
            editor.selectedRange(),
            NSRange(location: "Previous task".utf16.count, length: 0)
        )
        panel.orderOut(nil)
    }

    func testBackspaceInEmptyComposerLoadsThePreviousTaskTitle() throws {
        let field = FocusableTextField()
        var callbackCount = 0
        field.onDeleteBackwardWhenEmpty = {
            callbackCount += 1
            return "Previous task"
        }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                characters: "\u{8}",
                charactersIgnoringModifiers: "\u{8}",
                isARepeat: false,
                keyCode: 51
            )
        )

        field.keyDown(with: event)

        XCTAssertEqual(callbackCount, 1)
        XCTAssertEqual(field.stringValue, "Previous task")
    }

    func testComposerTakesFocusWhenItMountsIntoAnExistingPanel() {
        let panel = NSPanel(
            contentRect: CGRect(x: 0, y: 0, width: 180, height: 40),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        let container = NSView(frame: panel.contentView?.bounds ?? .zero)
        let existingResponder = NSButton(frame: CGRect(x: 0, y: 0, width: 20, height: 20))
        container.addSubview(existingResponder)
        panel.contentView = container
        panel.orderFrontRegardless()
        panel.makeFirstResponder(existingResponder)

        let field = FocusableTextField(frame: CGRect(x: 24, y: 0, width: 150, height: 20))
        container.addSubview(field)

        let focusSettled = expectation(description: "Dynamically mounted composer focus settles")
        DispatchQueue.main.async {
            focusSettled.fulfill()
        }
        wait(for: [focusSettled], timeout: 1)

        XCTAssertNotNil(field.currentEditor())
        panel.orderOut(nil)
    }

    private func firstDescendant<View: NSView>(
        of type: View.Type,
        in root: NSView
    ) -> View? {
        if let match = root as? View {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(of: type, in: subview) {
                return match
            }
        }
        return nil
    }

    private func waitForDescendant<View: NSView>(
        of type: View.Type,
        in root: NSView,
        matching predicate: @escaping (View) -> Bool
    ) throws -> View {
        let predicateExpectation = expectation(description: "Matching descendant mounts")
        var match: View?

        let deadline = Date().addingTimeInterval(1)
        func poll() {
            match = firstDescendant(of: type, in: root, matching: predicate)
            if match != nil || Date() >= deadline {
                predicateExpectation.fulfill()
            } else {
                DispatchQueue.main.async(execute: poll)
            }
        }
        poll()
        wait(for: [predicateExpectation], timeout: 1)

        return try XCTUnwrap(match)
    }

    private func firstDescendant<View: NSView>(
        of type: View.Type,
        in root: NSView,
        matching predicate: (View) -> Bool
    ) -> View? {
        if let match = root as? View, predicate(match) {
            return match
        }
        for subview in root.subviews {
            if let match = firstDescendant(of: type, in: subview, matching: predicate) {
                return match
            }
        }
        return nil
    }

    private func keyEvent(
        _ characters: String,
        keyCode: UInt16,
        window: NSWindow
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: window.windowNumber,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters,
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}

@MainActor
final class DotsMenuTests: XCTestCase {
    func testMainMenuDeclaresTaskEditingShortcuts() throws {
        let mainMenu = DotsMenu.mainMenu()
        let editMenu = try XCTUnwrap(mainMenu.item(withTitle: "Edit")?.submenu)
        let expectedShortcuts: [(title: String, key: String, action: Selector)] = [
            ("Undo", "z", Selector(("undo:"))),
            ("Select All", "a", #selector(NSText.selectAll(_:))),
            ("Cut", "x", #selector(NSText.cut(_:))),
            ("Copy", "c", #selector(NSText.copy(_:))),
            ("Paste", "v", #selector(NSText.paste(_:))),
        ]

        for shortcut in expectedShortcuts {
            let item = try XCTUnwrap(editMenu.item(withTitle: shortcut.title))
            XCTAssertEqual(item.keyEquivalent, shortcut.key)
            XCTAssertEqual(item.keyEquivalentModifierMask, [.command])
            XCTAssertEqual(item.action, shortcut.action)
            XCTAssertNil(item.target)
        }
    }

    func testMainMenuDeclaresDotMaterialChoices() throws {
        let mainMenu = DotsMenu.mainMenu(material: .regular)
        let appMenu = try XCTUnwrap(mainMenu.item(withTitle: "Dots")?.submenu)
        let materialMenu = try XCTUnwrap(appMenu.item(withTitle: "Dot Material")?.submenu)

        XCTAssertEqual(
            materialMenu.items.map(\.title),
            DotMaterialStyle.allCases.map(\.title)
        )
        XCTAssertEqual(materialMenu.item(withTitle: "Regular")?.state, .on)
        XCTAssertEqual(materialMenu.item(withTitle: "Liquid")?.state, .off)
    }
}
