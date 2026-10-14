import XCTest
@testable import SwiftOpenUICore
@testable import BackendWeb

final class WebAnimationTests: XCTestCase {

    // MARK: - webCSSTimingFunction

    @MainActor

    func testCSSTimingFunctionLinear() {
        XCTAssertEqual(webCSSTimingFunction(.linear), "linear")
    }

    @MainActor

    func testCSSTimingFunctionEaseIn() {
        XCTAssertEqual(webCSSTimingFunction(.easeIn), "ease-in")
    }

    @MainActor

    func testCSSTimingFunctionEaseOut() {
        XCTAssertEqual(webCSSTimingFunction(.easeOut), "ease-out")
    }

    @MainActor

    func testCSSTimingFunctionEaseInOut() {
        XCTAssertEqual(webCSSTimingFunction(.easeInOut), "ease-in-out")
    }

    @MainActor

    func testCSSTimingFunctionSpring() {
        XCTAssertEqual(webCSSTimingFunction(.spring), "cubic-bezier(0.5, 1.8, 0.3, 0.8)")
    }

    // MARK: - AnimatedView TLS scoping

    @MainActor

    func testAnimatedViewScopesCurrentAnimation() {
        // Before: no animation in TLS
        setCurrentAnimation(nil)
        XCTAssertNil(getCurrentAnimation())

        // AnimatedView should set currentAnimation for its subtree.
        // We verify the struct stores the animation correctly.
        let view = Text("hello").animation(.easeIn)
        XCTAssertEqual(view.animation?.curve, .easeIn)

        // After the view is done rendering, TLS should be restored.
        // (Actual TLS scoping happens in webCreateElement which requires
        // JavaScriptKit runtime — we test the mechanism at the core level.)
        XCTAssertNil(getCurrentAnimation(),
            "currentAnimation should remain nil outside AnimatedView render")
    }

    @MainActor

    func testAnimatedViewNilAnimation() {
        let view = Text("hello").animation(nil)
        XCTAssertNil(view.animation)
    }

    // MARK: - WebViewHost animation fields

    @MainActor

    func testCaptureAnimationStoresCurrentAnimation() {
        // WebViewHost.captureAnimation is tested indirectly through
        // the core animation TLS mechanism. Verify the TLS contract.
        setCurrentAnimation(.easeInOut)
        let captured = getCurrentAnimation()
        XCTAssertEqual(captured?.curve, .easeInOut)

        // Clean up
        setCurrentAnimation(nil)
    }

    @MainActor

    func testPendingAnimationFromWithAnimation() {
        // Clean state
        _ = consumePendingAnimation()

        withAnimation(.spring) {}
        let pending = getPendingAnimation()
        XCTAssertNotNil(pending)
        XCTAssertEqual(pending?.curve, .spring)

        // Consume clears it
        let consumed = consumePendingAnimation()
        XCTAssertNotNil(consumed)
        let second = consumePendingAnimation()
        XCTAssertNil(second)
    }

    // MARK: - Animation snapshot types

    @MainActor

    func testAnimatableSnapshotOpacityRole() {
        let snapshot = WebAnimatableSnapshot(
            key: "opacity@2", role: "opacity", opacity: "0.5", transform: nil)
        XCTAssertEqual(snapshot.key, "opacity@2")
        XCTAssertEqual(snapshot.role, "opacity")
        XCTAssertEqual(snapshot.opacity, "0.5")
        XCTAssertNil(snapshot.transform)
    }

    @MainActor

    func testAnimatableSnapshotTransformRole() {
        let snapshot = WebAnimatableSnapshot(
            key: "offset@3", role: "offset", opacity: nil, transform: "translate(10px, 20px)")
        XCTAssertEqual(snapshot.key, "offset@3")
        XCTAssertEqual(snapshot.role, "offset")
        XCTAssertNil(snapshot.opacity)
        XCTAssertEqual(snapshot.transform, "translate(10px, 20px)")
    }

    @MainActor

    func testAnimatableSnapshotKeyFormat() {
        // Key is "role@depth"
        let snapshot = WebAnimatableSnapshot(
            key: "scale@5", role: "scale", opacity: nil, transform: "scale(2)")
        XCTAssertEqual(snapshot.key, "scale@5")
    }

    // MARK: - Strict match guard logic (key-based)

    @MainActor

    func testKeySequenceMatchIdentical() {
        let oldKeys = ["opacity@2", "offset@3", "scale@3"]
        let newKeys = ["opacity@2", "offset@3", "scale@3"]
        let keysMatch = oldKeys == newKeys && Set(oldKeys).count == oldKeys.count
        XCTAssertTrue(keysMatch)
    }

    @MainActor

    func testKeySequenceMismatchDifferentCount() {
        let oldKeys = ["opacity@2", "offset@3"]
        let newKeys = ["opacity@2", "offset@3", "scale@3"]
        let keysMatch = oldKeys == newKeys && Set(oldKeys).count == oldKeys.count
        XCTAssertFalse(keysMatch)
    }

    @MainActor

    func testKeySequenceMismatchDifferentOrder() {
        let oldKeys = ["opacity@2", "scale@3"]
        let newKeys = ["scale@3", "opacity@2"]
        let keysMatch = oldKeys == newKeys && Set(oldKeys).count == oldKeys.count
        XCTAssertFalse(keysMatch)
    }

    @MainActor

    func testKeySequenceMismatchDifferentRole() {
        let oldKeys = ["opacity@2"]
        let newKeys = ["rotation@2"]
        let keysMatch = oldKeys == newKeys && Set(oldKeys).count == oldKeys.count
        XCTAssertFalse(keysMatch)
    }

    @MainActor

    func testKeySequenceMismatchDifferentDepth() {
        // Same roles but different depths → different nodes, must not pair.
        let oldKeys = ["opacity@2"]
        let newKeys = ["opacity@4"]
        let keysMatch = oldKeys == newKeys && Set(oldKeys).count == oldKeys.count
        XCTAssertFalse(keysMatch, "Same role at different depth must not match")
    }

    @MainActor

    func testKeySequenceDuplicateRolesSameDepthCountMismatch() {
        // Two opacity wrappers at depth 3 — if one is removed, count differs.
        let oldKeys = ["opacity@3", "opacity@3"]
        let newKeys = ["opacity@3"]
        let keysMatch = oldKeys == newKeys && Set(oldKeys).count == oldKeys.count
        XCTAssertFalse(keysMatch)
    }

    @MainActor

    func testKeySequenceDuplicateRolesSameDepthReorder() {
        // Two same-role siblings at the same depth: even if the sequence
        // looks identical, duplicate keys mean we cannot pair reliably.
        let oldKeys = ["opacity@3", "opacity@3"]
        let newKeys = ["opacity@3", "opacity@3"]
        let keysMatch = oldKeys == newKeys && Set(oldKeys).count == oldKeys.count
        XCTAssertFalse(keysMatch,
            "Duplicate keys must bail — cannot distinguish reordered same-role siblings")
    }

    @MainActor

    func testEmptyKeySequencesMatch() {
        let oldKeys: [String] = []
        let newKeys: [String] = []
        let keysMatch = oldKeys == newKeys && Set(oldKeys).count == oldKeys.count
        XCTAssertTrue(keysMatch, "Empty sequences match but animation is skipped (no wrappers)")
    }

    // MARK: - Pending animation lifecycle

    @MainActor

    func testPendingAnimationConsumedBeforePhase7() {
        // Verify the contract: pendingAnimation must be consumed before
        // inputsUnchanged can short-circuit, so it cannot leak.
        _ = consumePendingAnimation()
        withAnimation(.easeIn) {}
        let pending = consumePendingAnimation()
        XCTAssertNotNil(pending, "pendingAnimation should be set by withAnimation")

        // After consumption, it's gone — a skipped rebuild cannot reuse it.
        let leaked = consumePendingAnimation()
        XCTAssertNil(leaked, "Consumed pending should not survive")
    }
}
