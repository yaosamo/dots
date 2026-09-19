import AVFoundation
import CoreGraphics
import XCTest
@testable import Dots

final class DotsLayoutTests: XCTestCase {
    func testRequestedDotAndCameraDiameters() {
        XCTAssertEqual(DotsLayout.nodeDiameter, 16)
        XCTAssertEqual(DotsLayout.cameraDiameter, 120)
        XCTAssertEqual(DotsLayout.taskListSize, CGSize(width: 200, height: 240))
    }

    func testCollapsedGeometry() {
        XCTAssertEqual(DotsLayout.rowContentSize, CGSize(width: 112, height: 16))
        XCTAssertEqual(DotsLayout.canvasSize, CGSize(width: 224, height: 284))
    }

    func testCameraDotMorphsIntoA120PointCircle() {
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .camera),
            CGRect(x: 20, y: 32, width: 120, height: 120)
        )
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .camera)?.midX,
            DotsLayout.nodeFrames(expansion: .camera)[0].midX
        )
        XCTAssertFalse(
            DotsLayout.visibleNodeFrames(expansion: .camera)
                .contains(DotsLayout.nodeFrames(expansion: .camera)[0])
        )
    }

    func testTaskDotMorphsIntoARoundedTaskList() {
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .tasks),
            CGRect(x: 12, y: 32, width: 200, height: 240)
        )
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .tasks)?.midX,
            DotsLayout.nodeFrames(expansion: .tasks)[1].midX
        )
        XCTAssertFalse(
            DotsLayout.visibleNodeFrames(expansion: .tasks)
                .contains(DotsLayout.nodeFrames(expansion: .tasks)[1])
        )
    }

    func testCollapsedStemsRunFromScreenEdgeToEveryNodeCenter() {
        let frames = DotsLayout.nodeFrames(expansion: .none)
        let stems = DotsLayout.stemRects(expansion: .none)

        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(stems.count, frames.count)
        XCTAssertEqual(frames[0], CGRect(x: 72, y: 8, width: 16, height: 16))
        XCTAssertEqual(frames[3], CGRect(x: 168, y: 8, width: 16, height: 16))

        for (stem, frame) in zip(stems, frames) {
            XCTAssertEqual(stem.midX, frame.midX)
            XCTAssertEqual(stem.minY, 0)
            XCTAssertEqual(stem.maxY, frame.midY)
        }
    }

    func testMorphCanvasKeepsTheDotRowFixedForEveryState() {
        let collapsed = DotsLayout.nodeFrames(expansion: .none)
        let camera = DotsLayout.nodeFrames(expansion: .camera)
        let tasks = DotsLayout.nodeFrames(expansion: .tasks)

        XCTAssertEqual(camera, collapsed)
        XCTAssertEqual(tasks, collapsed)
    }

    func testExpandedStemMeetsTheMorphedSurface() {
        let frames = DotsLayout.nodeFrames(expansion: .tasks)
        let stems = DotsLayout.stemRects(expansion: .tasks)
        let list = DotsLayout.hangingFrame(expansion: .tasks)!

        XCTAssertEqual(frames[1], CGRect(x: 104, y: 8, width: 16, height: 16))
        XCTAssertEqual(stems[1].midX, frames[1].midX)
        XCTAssertEqual(stems[1].maxY, list.minY)
        XCTAssertEqual(list.minX, DotsLayout.glassInset)
        XCTAssertGreaterThan(list.minY, frames[1].maxY)
        XCTAssertEqual(list.midX, frames[1].midX)
    }

    func testHitTestingIgnoresTransparentPadding() {
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 2, y: 2), expansion: .none))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 222, y: 16), expansion: .none))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 2, y: 2), expansion: .camera))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 216, y: 20), expansion: .camera))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 24, y: 16), expansion: .tasks))
    }

    func testHitTestingAcceptsDotsStemsAndHangingWidgets() {
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 80, y: 16), expansion: .none))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 112, y: 4), expansion: .none))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 176, y: 16), expansion: .none))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 80, y: 92), expansion: .camera))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 176, y: 16), expansion: .camera))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 80, y: 16), expansion: .tasks))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 112, y: 150), expansion: .tasks))
    }

    func testPanelSitsFlushWithUsableScreenEdgeOnFirstPlacement() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = DotsLayout.panelFrame(visibleFrame: visible)

        XCTAssertEqual(frame.maxY, visible.maxY)
        XCTAssertEqual(frame.minX + DotsLayout.rowCenterX, visible.midX)
        XCTAssertEqual(frame.size, DotsLayout.canvasSize)
    }

    func testEveryMorphUsesOneStablePanelFrame() {
        let visible = CGRect(x: 100, y: 50, width: 1440, height: 900)
        let frame = DotsLayout.panelFrame(visibleFrame: visible)

        for state in [DotExpansion.none, .camera, .tasks] {
            let sourceIndex = state == .camera ? 0 : 1
            let sourceX = frame.minX + DotsLayout.nodeFrames(expansion: state)[sourceIndex].midX
            if let destination = DotsLayout.hangingFrame(expansion: state) {
                XCTAssertEqual(frame.minX + destination.midX, sourceX)
            }
        }
    }

    func testCameraIsDockedUntilItMovesPastTheDetachDistance() {
        XCTAssertFalse(DotsLayout.isCameraDetached(.zero))
        XCTAssertFalse(DotsLayout.isCameraDetached(CGSize(width: 4, height: 4)))
        XCTAssertTrue(DotsLayout.isCameraDetached(CGSize(width: 8, height: 0)))
        XCTAssertTrue(DotsLayout.isCameraDetached(CGSize(width: 0, height: 12)))
    }

    func testDetachedCameraHidesTheFirstStem() {
        let offset = CGSize(width: 80, height: 40)
        let stems = DotsLayout.stemRects(expansion: .camera, cameraOffset: offset)

        XCTAssertEqual(stems[0], .zero)
        XCTAssertGreaterThan(stems[1].height, 0)
        XCTAssertGreaterThan(stems[2].height, 0)
        XCTAssertGreaterThan(stems[3].height, 0)
    }

    func testDockedCameraStemMeetsTheMorphedSurface() {
        let frames = DotsLayout.nodeFrames(expansion: .camera)
        let stems = DotsLayout.stemRects(expansion: .camera)
        let hang = DotsLayout.hangingFrame(expansion: .camera)!

        XCTAssertEqual(stems[0].midX, frames[0].midX)
        XCTAssertEqual(stems[0].minY, 0)
        XCTAssertEqual(stems[0].maxY, hang.minY)
    }

    func testDraggingCameraLeftKeepsTheDotRowInPlace() {
        let offset = CGSize(width: -100, height: 0)
        let visible = CGRect(x: 100, y: 50, width: 1440, height: 900)
        let docked = DotsLayout.panelFrame(visibleFrame: visible)
        let dragged = DotsLayout.panelFrame(
            visibleFrame: visible,
            cameraOffset: offset,
            previousCameraOffset: .zero,
            keepingTopOf: docked
        )
        let dockedDot = docked.minX + DotsLayout.nodeFrames(expansion: .camera)[0].minX
        let draggedDot = dragged.minX
            + DotsLayout.nodeFrames(expansion: .camera, cameraOffset: offset)[0].minX

        XCTAssertEqual(dragged.maxY, docked.maxY)
        XCTAssertEqual(draggedDot, dockedDot)
        XCTAssertGreaterThan(dragged.width, docked.width)
    }

    func testDraggingCameraDownExtendsTheCanvas() {
        let offset = CGSize(width: 0, height: 200)
        XCTAssertGreaterThan(
            DotsLayout.canvasSize(cameraOffset: offset).height,
            DotsLayout.canvasSize.height
        )
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .camera, cameraOffset: offset)?.minY,
            232
        )
    }

    func testHitTestingFollowsADraggedCameraAndIgnoresTheMissingStem() {
        let offset = CGSize(width: 80, height: 40)
        let hang = DotsLayout.hangingFrame(expansion: .camera, cameraOffset: offset)!
        let firstDot = DotsLayout.nodeFrames(expansion: .camera, cameraOffset: offset)[0]
        let vanishedStem = CGPoint(x: firstDot.midX, y: 4)

        XCTAssertTrue(
            DotsLayout.containsInteractiveContent(
                CGPoint(x: hang.midX, y: hang.midY),
                expansion: .camera,
                cameraOffset: offset
            )
        )
        XCTAssertFalse(
            DotsLayout.containsInteractiveContent(
                vanishedStem,
                expansion: .camera,
                cameraOffset: offset
            )
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
}
