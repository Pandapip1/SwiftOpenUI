import XCTest
@testable import SwiftOpenUICore

// MARK: - Mock ViewHost

private class MockViewHost: AnyViewHost, DependencyTrackingHost {
    var lastReadSet: Set<ObjectIdentifier>?
    var lastInputSnapshot: [StorageSnapshot]?
    var rebuildCount = 0

    func scheduleRebuild() { rebuildCount += 1 }
    func suppressNextFocusRestore() {}
}

final class DependencyTrackingTests: XCTestCase {

    // MARK: - Tracking context

    @MainActor func testBeginEndTracking() {
        let obj = NSObject()
        beginDependencyTracking()
        recordDependencyRead(obj)
        let tracking = endDependencyTracking()
        XCTAssertNotNil(tracking)
        XCTAssertTrue(tracking!.readSet.contains(ObjectIdentifier(obj)))
    }

    @MainActor func testEmptyTrackingReturnsEmptySet() {
        beginDependencyTracking()
        let tracking = endDependencyTracking()
        XCTAssertNotNil(tracking)
        XCTAssertTrue(tracking!.readSet.isEmpty)
    }

    @MainActor func testNoTrackingReturnsNil() {
        let tracking = endDependencyTracking()
        XCTAssertNil(tracking)
    }

    // MARK: - isDependency

    @MainActor func testIsDependencyTrue() {
        let obj = NSObject()
        let readSet: Set<ObjectIdentifier> = [ObjectIdentifier(obj)]
        XCTAssertTrue(isDependency(obj, in: readSet))
    }

    @MainActor func testIsDependencyFalse() {
        let obj = NSObject()
        let other = NSObject()
        let readSet: Set<ObjectIdentifier> = [ObjectIdentifier(other)]
        XCTAssertFalse(isDependency(obj, in: readSet))
    }

    // MARK: - Storage integration

    @MainActor func testStateStorageRecordsDependency() {
        let storage = StateStorage(42)
        beginDependencyTracking()
        _ = storage.value
        let tracking = endDependencyTracking()
        XCTAssertNotNil(tracking)
        XCTAssertTrue(tracking!.readSet.contains(ObjectIdentifier(storage)))
    }

    @MainActor func testPublishedStorageRecordsDependency() {
        let storage = PublishedStorage("hello")
        beginDependencyTracking()
        _ = storage.value
        let tracking = endDependencyTracking()
        XCTAssertNotNil(tracking)
        XCTAssertTrue(tracking!.readSet.contains(ObjectIdentifier(storage)))
    }

    // MARK: - @State always rebuilds (no gating)

    @MainActor func testStateAlwaysRebuildsEvenWhenUnread() {
        let host = MockViewHost()
        let unreadStorage = StateStorage(1)
        unreadStorage.host = host

        beginDependencyTracking()
        let tracking = endDependencyTracking()
        host.lastReadSet = tracking?.readSet

        host.rebuildCount = 0
        unreadStorage.setValue(99)
        XCTAssertEqual(host.rebuildCount, 1, "@State must always rebuild — may pass value via Binding")
    }

    // MARK: - @Published gating

    @MainActor func testPublishedSkipsRebuildForUnreadStorage() {
        let host = MockViewHost()
        let readPublished = PublishedStorage("read")
        let unreadPublished = PublishedStorage("unread")

        readPublished.setObserver(token: ObjectIdentifier(host)) { [weak host] in
            guard let host = host else { return }
            if let readSet = host.lastReadSet,
               !isDependency(readPublished, in: readSet) {
                return
            }
            host.scheduleRebuild()
        }
        unreadPublished.setObserver(token: ObjectIdentifier(host)) { [weak host] in
            guard let host = host else { return }
            if let readSet = host.lastReadSet,
               !isDependency(unreadPublished, in: readSet) {
                return
            }
            host.scheduleRebuild()
        }

        beginDependencyTracking()
        _ = readPublished.value
        let tracking = endDependencyTracking()
        host.lastReadSet = tracking?.readSet

        host.rebuildCount = 0
        unreadPublished.setValue("changed")
        XCTAssertEqual(host.rebuildCount, 0, "Should skip rebuild for unread @Published")
    }

    @MainActor func testPublishedRebuildsForReadStorage() {
        let host = MockViewHost()
        let readPublished = PublishedStorage("read")

        readPublished.setObserver(token: ObjectIdentifier(host)) { [weak host] in
            guard let host = host else { return }
            if let readSet = host.lastReadSet,
               !isDependency(readPublished, in: readSet) {
                return
            }
            host.scheduleRebuild()
        }

        beginDependencyTracking()
        _ = readPublished.value
        let tracking = endDependencyTracking()
        host.lastReadSet = tracking?.readSet

        host.rebuildCount = 0
        readPublished.setValue("changed")
        XCTAssertEqual(host.rebuildCount, 1, "Should rebuild for read @Published")
    }

    // MARK: - Nested tracking (stack-based)

    @MainActor func testNestedTrackingPreservesParentSession() {
        let parentObj = NSObject()
        let childObj = NSObject()

        beginDependencyTracking()
        recordDependencyRead(parentObj)

        beginDependencyTracking()
        recordDependencyRead(childObj)
        let childTracking = endDependencyTracking()

        XCTAssertNotNil(childTracking)
        XCTAssertTrue(childTracking!.readSet.contains(ObjectIdentifier(childObj)))
        XCTAssertFalse(childTracking!.readSet.contains(ObjectIdentifier(parentObj)))

        let parentTracking = endDependencyTracking()
        XCTAssertNotNil(parentTracking)
        XCTAssertTrue(parentTracking!.readSet.contains(ObjectIdentifier(parentObj)))
        XCTAssertFalse(parentTracking!.readSet.contains(ObjectIdentifier(childObj)))
    }
}
