import CoreGraphics
import XCTest
@testable import Dots

final class DotRegistryTests: XCTestCase {
    func testDefaultsContainOnlyImplementedDotsInProductOrder() {
        XCTAssertEqual(
            DotRegistry.defaultActiveIDs,
            [.mirror, .tasks, .redPen, .screenToText, .clipboard]
        )
        XCTAssertTrue(
            DotRegistry.descriptors(for: DotRegistry.defaultActiveIDs)
                .allSatisfy(\.isImplemented)
        )
    }

    func testVisibleIDsPreserveOrderWhileRemovingDuplicatesAndUnavailableDots() {
        let requested: [DotID] = [
            .tasks,
            .mirror,
            .tasks,
            .clipboard,
        ]

        XCTAssertEqual(DotRegistry.visibleIDs(from: requested), [.tasks, .mirror, .clipboard])
    }

    func testVisibleIDsNeverExceedNamedMaximum() {
        let implemented = Set(DotID.allCases)
        let requested: [DotID] = [
            .mirror,
            .tasks,
            .redPen,
            .screenToText,
            .clipboard,
            .mirror,
        ]

        XCTAssertEqual(DotRegistry.maximumVisibleDots, 5)
        XCTAssertEqual(
            DotRegistry.visibleIDs(from: requested, implemented: implemented),
            Array(requested.prefix(DotRegistry.maximumVisibleDots))
        )
    }

    func testEmptyVisibleSelectionFallsBackToImplementedDefaults() {
        XCTAssertEqual(
            DotRegistry.visibleIDs(from: [], implemented: [.mirror, .tasks]),
            [.mirror, .tasks]
        )
    }
}

final class DotMagnetismTests: XCTestCase {
    func testOnlyNearestStableAnchorMoves() {
        let anchors = [
            CGPoint(x: 20, y: 20),
            CGPoint(x: 60, y: 20),
            CGPoint(x: 100, y: 20),
        ]

        let offsets = DotMagnetism.offsets(
            pointer: CGPoint(x: 64, y: 30),
            anchors: anchors
        )

        XCTAssertEqual(offsets[0], .zero)
        XCTAssertNotEqual(offsets[1], .zero)
        XCTAssertEqual(offsets[2], .zero)
    }

    func testMagneticOffsetNeverExceedsMaximum() {
        let offset = DotMagnetism.offsets(
            pointer: CGPoint(x: 20, y: 21),
            anchors: [CGPoint(x: 20, y: 20)]
        )[0]
        let magnitude = hypot(offset.width, offset.height)

        XCTAssertLessThanOrEqual(magnitude, DotMagnetism.maximumOffset)
    }

    func testPointerOutsideActivationRadiusLeavesEveryAnchorStable() {
        let offsets = DotMagnetism.offsets(
            pointer: CGPoint(x: 400, y: 400),
            anchors: [CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 20)]
        )

        XCTAssertEqual(offsets, [.zero, .zero])
    }

    func testMissingPointerLeavesEveryAnchorStable() {
        XCTAssertEqual(
            DotMagnetism.offsets(
                pointer: nil,
                anchors: [CGPoint(x: 20, y: 20), CGPoint(x: 60, y: 20)]
            ),
            [.zero, .zero]
        )
    }
}
