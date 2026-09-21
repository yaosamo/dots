import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI
import XCTest
@testable import Dots

final class DotsLayoutTests: XCTestCase {
    private let twoDots: [DotID] = [.mirror, .tasks]

    @MainActor
    func testCameraMaskTracksTheExpandingDotFrame() {
        let pointer = LauncherPointerState()
        let dot = CGRect(x: 122, y: 8, width: 16, height: 16)
        let camera = CGRect(x: 50, y: 24, width: 160, height: 160)

        pointer.setCameraReveal(true)
        pointer.setCameraMaskFrame(dot)
        XCTAssertTrue(pointer.cameraReveal)
        XCTAssertEqual(pointer.cameraMaskFrame, dot)

        pointer.setCameraMaskFrame(camera)
        XCTAssertEqual(pointer.cameraMaskFrame, camera)
    }

    func testRequestedDotAndCameraDiameters() {
        XCTAssertEqual(DotsLayout.nodeDiameter, 16)
        XCTAssertEqual(DotsLayout.cameraDiameter, 160)
        XCTAssertEqual(DotsLayout.launchCadence, 0.08)
        XCTAssertEqual(
            DotsLayout.taskListSize(taskCount: 0),
            CGSize(width: 300, height: 168)
        )
        XCTAssertGreaterThanOrEqual(DotsLayout.taskControlHitSize, 22)
    }

    func testTaskPanelGrowsForEveryTaskUntilItsHeightCap() {
        let empty = DotsLayout.taskListSize(taskCount: 0)
        let oneTask = DotsLayout.taskListSize(taskCount: 1)
        let twoTasks = DotsLayout.taskListSize(taskCount: 2)
        let manyTasks = DotsLayout.taskListSize(taskCount: 100)

        XCTAssertEqual(oneTask.height - empty.height, 30)
        XCTAssertEqual(twoTasks.height - oneTask.height, 30)
        XCTAssertEqual(manyTasks.height, 420)
    }

    func testTaskHitTestingGrowsWithTheVisiblePanel() {
        let emptyPanel = DotsLayout.hangingFrame(expansion: .tasks, taskCount: 0, dotIDs: twoDots)!
        let pointInFirstGrowthRow = CGPoint(
            x: emptyPanel.midX,
            y: emptyPanel.maxY + 15
        )

        XCTAssertFalse(
            DotsLayout.containsInteractiveContent(
                pointInFirstGrowthRow,
                expansion: .tasks,
                taskCount: 0,
                dotIDs: twoDots
            )
        )
        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                pointInFirstGrowthRow,
                expansion: .tasks,
                taskCount: 1,
                dotIDs: twoDots
            )
        )
    }

    func testCollapsedGeometry() {
        XCTAssertEqual(DotsLayout.rowContentSize(dotCount: 2), CGSize(width: 48, height: 16))
        XCTAssertEqual(
            DotsLayout.canvasSize(cameraOffset: .zero, dotIDs: twoDots),
            CGSize(width: 324, height: 464)
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

    func testLaunchFrameStartsAboveThePanelWithoutChangingDotSize() {
        let docked = CGRect(x: 80, y: 12, width: 16, height: 16)
        let start = DotsLayout.launchStartFrame(docked: docked, canvasHeight: 40)

        XCTAssertEqual(start.minX, docked.minX)
        XCTAssertEqual(start.minY, 56)
        XCTAssertEqual(start.size, docked.size)
    }

    func testTaskPanelHangsBelowAVisible16PointDot() {
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .tasks, taskCount: 0, dotIDs: twoDots),
            CGRect(x: 12, y: 32, width: 300, height: 168)
        )
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .tasks, taskCount: 0, dotIDs: twoDots)?.midX,
            DotsLayout.nodeFrames(expansion: .tasks, dotIDs: twoDots)[1].midX
        )
        XCTAssertTrue(
            DotsLayout.visibleNodeFrames(expansion: .tasks, dotIDs: twoDots)
                .contains(DotsLayout.nodeFrames(expansion: .tasks, dotIDs: twoDots)[1])
        )
    }

    func testCollapsedDotsKeepRequestedFrames() {
        let frames = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)

        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0], CGRect(x: 122, y: 8, width: 16, height: 16))
        XCTAssertEqual(frames[1], CGRect(x: 154, y: 8, width: 16, height: 16))
    }

    func testFeaturePanelsKeepTheDotRowFixedForEveryState() {
        let collapsed = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)
        let camera = DotsLayout.nodeFrames(expansion: .camera, dotIDs: twoDots)
        let tasks = DotsLayout.nodeFrames(expansion: .tasks, dotIDs: twoDots)

        XCTAssertEqual(camera, collapsed)
        XCTAssertEqual(tasks, collapsed)
    }

    func testExpandedPanelStaysAlignedWithItsDot() {
        let frames = DotsLayout.nodeFrames(expansion: .tasks, dotIDs: twoDots)
        let list = DotsLayout.hangingFrame(expansion: .tasks, dotIDs: twoDots)!

        XCTAssertEqual(frames[1], CGRect(x: 154, y: 8, width: 16, height: 16))
        XCTAssertEqual(list.minX, DotsLayout.glassInset)
        XCTAssertGreaterThan(list.minY, frames[1].maxY)
        XCTAssertEqual(list.midX, frames[1].midX)
    }

    func testHitTestingIgnoresTransparentPadding() {
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 2, y: 2), expansion: .none, dotIDs: twoDots))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 222, y: 16), expansion: .none, dotIDs: twoDots))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 2, y: 2), expansion: .camera, dotIDs: twoDots))
        let camera = try! XCTUnwrap(DotsLayout.hangingFrame(expansion: .camera, dotIDs: twoDots))
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

        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: dots[0].midX, y: dots[0].midY),
                expansion: .none,
                dotIDs: twoDots
            )
        )
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 146, y: 2), expansion: .none, dotIDs: twoDots))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 276, y: 16), expansion: .none, dotIDs: twoDots))
        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: camera.midX, y: camera.midY),
                expansion: .camera,
                dotIDs: twoDots
            )
        )
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 276, y: 16), expansion: .camera, dotIDs: twoDots))
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
                XCTAssertEqual(frame.minX + destination.midX, frame.minX + source.midX)
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
        let emptySpaceAboveDot = CGPoint(x: firstDot.midX, y: 1)

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
        let pointOutsideFill = CGPoint(x: firstDot.minX - 4, y: firstDot.midY)

        XCTAssertFalse(firstDot.contains(pointOutsideFill))
        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(pointOutsideFill, expansion: .none)
        )
    }

    func testStableHitTestingResolvesOnlyRegisteredDots() {
        let frames = DotsLayout.nodeFrames(expansion: .none, dotIDs: twoDots)

        XCTAssertEqual(
            DotsLayout.dotID(
                at: CGPoint(x: frames[0].minX - 4, y: frames[0].midY),
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
                at: CGPoint(x: 200, y: 16),
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
}

@MainActor
final class CameraTransitionHitAnchorViewTests: XCTestCase {
    func testArmKeepsTheLastCameraClickInteractive() {
        let anchor = CameraTransitionHitAnchorView(frame: .zero)
        let click = CGPoint(x: 120, y: 240)

        anchor.arm(at: click)

        XCTAssertFalse(anchor.isHidden)
        XCTAssertEqual(anchor.frame.size, CGSize(width: 28, height: 28))
        XCTAssertEqual(CGPoint(x: anchor.frame.midX, y: anchor.frame.midY), click)
        XCTAssertTrue(anchor.contains(click))
        XCTAssertGreaterThan(anchor.layer?.backgroundColor?.alpha ?? 0, 0)
        XCTAssertLessThan(anchor.layer?.backgroundColor?.alpha ?? 1, 0.01)
    }

    func testDisarmRestoresClickThroughOutsideTheAnimation() {
        let anchor = CameraTransitionHitAnchorView(frame: .zero)
        let click = CGPoint(x: 120, y: 240)
        anchor.arm(at: click)

        anchor.disarm()

        XCTAssertTrue(anchor.isHidden)
        XCTAssertFalse(anchor.contains(click))
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

    func testOtherRuntimeErrorsDoNotRetry() {
        let error = NSError(domain: AVFoundationErrorDomain, code: -11800)

        XCTAssertFalse(CameraRuntimeErrorPolicy.shouldRetry(alreadyRetried: false, error: error))
        XCTAssertFalse(CameraRuntimeErrorPolicy.isMediaServicesReset(nil))
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

    func testBackspaceInEmptyComposerRecallsThePreviousTaskForEditing() {
        let keep = store.add("Keep")!
        let edit = store.add("Edit me")!

        XCTAssertTrue(store.handleBackspaceOnEmptyDraft())

        XCTAssertEqual(store.draft, "Edit me")
        XCTAssertEqual(store.editingTaskID, edit.id)
        XCTAssertEqual(store.visibleItems.map(\.id), [keep.id])
        XCTAssertEqual(store.items.map(\.id), [keep.id, edit.id])
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
        XCTAssertTrue(store.visibleItems.isEmpty)
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
        XCTAssertEqual(store.selectedTaskID, second.id)
        XCTAssertTrue(store.moveTaskSelection(.up))
        XCTAssertEqual(store.selectedTaskID, first.id)
        XCTAssertTrue(store.moveTaskSelection(.up))
        XCTAssertEqual(store.selectedTaskID, first.id)

        store.clearTaskSelection()

        XCTAssertTrue(store.moveTaskSelection(.down))
        XCTAssertEqual(store.selectedTaskID, first.id)
        XCTAssertTrue(store.moveTaskSelection(.down))
        XCTAssertEqual(store.selectedTaskID, second.id)
        XCTAssertTrue(store.moveTaskSelection(.down))
        XCTAssertEqual(store.selectedTaskID, second.id)
    }

    func testEditingTheKeyboardSelectedTaskLoadsItIntoTheComposer() {
        let first = store.add("First")!
        _ = store.add("Second")!
        XCTAssertTrue(store.moveTaskSelection(.down))

        XCTAssertTrue(store.editSelectedTask())

        XCTAssertEqual(store.editingTaskID, first.id)
        XCTAssertNil(store.selectedTaskID)
        XCTAssertEqual(store.draft, "First")
        XCTAssertEqual(store.visibleItems.map(\.title), ["Second"])
    }
}

@MainActor
final class TaskComposerFocusTests: XCTestCase {
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
        _ = store.add("First task")
        let secondTask = try XCTUnwrap(store.add("Second task"))

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

        let field = try XCTUnwrap(firstDescendant(of: FocusableTextField.self, in: hostingView))
        XCTAssertTrue(panel.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)

        editor.keyDown(with: try keyEvent("\u{F700}", keyCode: 126, window: panel))
        XCTAssertEqual(store.selectedTaskID, secondTask.id)
        editor.keyDown(with: try keyEvent("\u{F700}", keyCode: 126, window: panel))
        XCTAssertEqual(store.selectedTaskID, store.items.first?.id)
        editor.keyDown(with: try keyEvent("\u{F701}", keyCode: 125, window: panel))
        XCTAssertEqual(store.selectedTaskID, secondTask.id)

        editor.keyDown(with: try keyEvent("\r", keyCode: 36, window: panel))

        XCTAssertEqual(store.editingTaskID, secondTask.id)
        XCTAssertNil(store.selectedTaskID)
        XCTAssertEqual(store.draft, "Second task")
        XCTAssertEqual(field.stringValue, "Second task")
        XCTAssertEqual(
            editor.selectedRange(),
            NSRange(location: "Second task".utf16.count, length: 0)
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

        let field = try XCTUnwrap(firstDescendant(of: FocusableTextField.self, in: hostingView))
        XCTAssertTrue(panel.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        XCTAssertTrue(panel.firstResponder === editor)
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

        editor.keyDown(with: event)

        XCTAssertEqual(store.draft, "Second task")
        XCTAssertEqual(field.stringValue, "Second task")
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
        XCTAssertEqual(field.stringValue, "First task")
        XCTAssertEqual(
            editor.selectedRange(),
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
}
