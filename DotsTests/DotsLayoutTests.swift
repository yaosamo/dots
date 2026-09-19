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
        XCTAssertEqual(DotsLayout.panelSize(expansion: .none), CGSize(width: 136, height: 32))
    }

    func testCameraHangsBelowTheRowWithoutGrowingDots() {
        XCTAssertEqual(DotsLayout.panelSize(expansion: .camera), CGSize(width: 176, height: 160))
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .camera),
            CGRect(x: 0, y: 32, width: 120, height: 120)
        )
        for frame in DotsLayout.nodeFrames(expansion: .camera) {
            XCTAssertEqual(frame.size, CGSize(width: 16, height: 16))
        }
    }

    func testTaskListHangsBelowTheRowWithoutGrowingDots() {
        XCTAssertEqual(DotsLayout.panelSize(expansion: .tasks), CGSize(width: 200, height: 280))
        XCTAssertEqual(
            DotsLayout.hangingFrame(expansion: .tasks),
            CGRect(x: 0, y: 32, width: 200, height: 240)
        )
        for frame in DotsLayout.nodeFrames(expansion: .tasks) {
            XCTAssertEqual(frame.size, CGSize(width: 16, height: 16))
        }
    }

    func testCollapsedStemsRunFromScreenEdgeToEveryNodeCenter() {
        let frames = DotsLayout.nodeFrames(expansion: .none)
        let stems = DotsLayout.stemRects(expansion: .none)

        XCTAssertEqual(frames.count, 4)
        XCTAssertEqual(stems.count, frames.count)
        XCTAssertEqual(frames[0], CGRect(x: 12, y: 8, width: 16, height: 16))
        XCTAssertEqual(frames[3], CGRect(x: 108, y: 8, width: 16, height: 16))

        for (stem, frame) in zip(stems, frames) {
            XCTAssertEqual(stem.midX, frame.midX)
            XCTAssertEqual(stem.minY, 0)
            XCTAssertEqual(stem.maxY, frame.midY)
        }
    }

    func testHangingWidgetsDoNotMoveTheDotRow() {
        let collapsed = DotsLayout.nodeFrames(expansion: .none)
        let extraLeft = DotsLayout.extraLeft(expansion: .tasks)
        let hanging = DotsLayout.nodeFrames(expansion: .tasks)

        XCTAssertEqual(extraLeft, 48)
        for (idle, open) in zip(collapsed, hanging) {
            XCTAssertEqual(open.origin.x, idle.origin.x + extraLeft)
            XCTAssertEqual(open.origin.y, idle.origin.y)
            XCTAssertEqual(open.size, idle.size)
        }
    }

    func testTaskListHangsFromTheSecondDotWithoutCrossingTheList() {
        let frames = DotsLayout.nodeFrames(expansion: .tasks)
        let stems = DotsLayout.stemRects(expansion: .tasks)
        let list = DotsLayout.hangingFrame(expansion: .tasks)!

        XCTAssertEqual(frames[1], CGRect(x: 92, y: 8, width: 16, height: 16))
        XCTAssertEqual(stems[1].midX, frames[1].midX)
        XCTAssertEqual(stems[1].maxY, frames[1].midY)
        XCTAssertEqual(list.minX, 0)
        XCTAssertGreaterThan(list.minY, frames[1].maxY)
        XCTAssertEqual(list.midX, frames[1].midX)
    }

    func testHitTestingIgnoresTransparentPadding() {
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 2, y: 2), expansion: .none))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 134, y: 16), expansion: .none))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 2, y: 2), expansion: .camera))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 140, y: 20), expansion: .camera))
        XCTAssertFalse(DotsLayout.containsInteractiveContent(CGPoint(x: 50, y: 16), expansion: .tasks))
    }

    func testHitTestingAcceptsDotsStemsAndHangingWidgets() {
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 20, y: 16), expansion: .none))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 52, y: 4), expansion: .none))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 116, y: 16), expansion: .none))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 60, y: 92), expansion: .camera))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 156, y: 16), expansion: .camera))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 100, y: 16), expansion: .tasks))
        XCTAssertTrue(DotsLayout.containsInteractiveContent(CGPoint(x: 144, y: 150), expansion: .tasks))
    }

    func testPanelSitsFlushWithUsableScreenEdgeOnFirstPlacement() {
        let visible = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = DotsLayout.panelFrame(
            size: DotsLayout.panelSize(expansion: .none),
            expansion: .none,
            visibleFrame: visible
        )

        XCTAssertEqual(frame.maxY, visible.maxY)
        XCTAssertEqual(frame.midX, visible.midX)
        XCTAssertEqual(frame.size, CGSize(width: 136, height: 32))
    }

    func testOpeningCameraKeepsTheDotRowInPlace() {
        let visible = CGRect(x: 100, y: 50, width: 1440, height: 900)
        let collapsed = DotsLayout.panelFrame(
            size: DotsLayout.panelSize(expansion: .none),
            expansion: .none,
            visibleFrame: visible
        )
        let expanded = DotsLayout.panelFrame(
            size: DotsLayout.panelSize(expansion: .camera),
            expansion: .camera,
            previousExpansion: .none,
            keepingTopOf: collapsed,
            visibleFrame: visible
        )
        let collapsedDot = collapsed.minX + DotsLayout.nodeFrames(expansion: .none)[0].minX
        let expandedDot = expanded.minX + DotsLayout.nodeFrames(expansion: .camera)[0].minX

        XCTAssertEqual(expanded.maxY, collapsed.maxY)
        XCTAssertEqual(expandedDot, collapsedDot)
        XCTAssertEqual(expanded.size, CGSize(width: 176, height: 160))
    }

    func testOpeningTasksKeepsTheDotRowInPlace() {
        let visible = CGRect(x: 100, y: 50, width: 1440, height: 900)
        let collapsed = DotsLayout.panelFrame(
            size: DotsLayout.panelSize(expansion: .none),
            expansion: .none,
            visibleFrame: visible
        )
        let expanded = DotsLayout.panelFrame(
            size: DotsLayout.panelSize(expansion: .tasks),
            expansion: .tasks,
            previousExpansion: .none,
            keepingTopOf: collapsed,
            visibleFrame: visible
        )
        let collapsedDot = collapsed.minX + DotsLayout.nodeFrames(expansion: .none)[1].minX
        let expandedDot = expanded.minX + DotsLayout.nodeFrames(expansion: .tasks)[1].minX

        XCTAssertEqual(expanded.maxY, collapsed.maxY)
        XCTAssertEqual(expandedDot, collapsedDot)
        XCTAssertEqual(expanded.size, CGSize(width: 200, height: 280))
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
