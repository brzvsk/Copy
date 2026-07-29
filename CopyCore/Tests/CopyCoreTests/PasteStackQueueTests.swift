import XCTest
@testable import CopyCore

final class PasteStackQueueTests: XCTestCase {
    func testEnqueueAddsItem() {
        var queue = PasteStackQueue()
        queue.enqueue("uuid-1")
        XCTAssertEqual(queue.itemUUIDs, ["uuid-1"])
        XCTAssertEqual(queue.count, 1)
        XCTAssertFalse(queue.isEmpty)
    }

    func testEnqueueDeduplicatesAndMovesToTail() {
        var queue = PasteStackQueue()
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.enqueue("uuid-1")
        XCTAssertEqual(queue.itemUUIDs, ["uuid-2", "uuid-1"])
        XCTAssertEqual(queue.count, 2)
    }

    func testRemoveItem() {
        var queue = PasteStackQueue()
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.enqueue("uuid-3")
        queue.remove("uuid-2")
        XCTAssertEqual(queue.itemUUIDs, ["uuid-1", "uuid-3"])
    }

    func testRemoveNonexistentItemIsNoop() {
        var queue = PasteStackQueue()
        queue.enqueue("uuid-1")
        queue.remove("uuid-999")
        XCTAssertEqual(queue.itemUUIDs, ["uuid-1"])
    }

    func testMoveValidIndices() {
        var queue = PasteStackQueue()
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.enqueue("uuid-3")
        queue.move(from: 0, to: 2)
        XCTAssertEqual(queue.itemUUIDs, ["uuid-2", "uuid-3", "uuid-1"])
    }

    func testMoveOutOfBoundsIsNoop() {
        var queue = PasteStackQueue()
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.move(from: 10, to: 5)
        XCTAssertEqual(queue.itemUUIDs, ["uuid-1", "uuid-2"])
        queue.move(from: -1, to: 0)
        XCTAssertEqual(queue.itemUUIDs, ["uuid-1", "uuid-2"])
    }

    func testFIFONext() {
        var queue = PasteStackQueue()
        queue.isLIFO = false
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.enqueue("uuid-3")
        XCTAssertEqual(queue.next, "uuid-1")
    }

    func testFIFOAdvance() {
        var queue = PasteStackQueue()
        queue.isLIFO = false
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.enqueue("uuid-3")
        let next = queue.advance()
        XCTAssertEqual(next, "uuid-1")
        XCTAssertEqual(queue.itemUUIDs, ["uuid-2", "uuid-3"])
        XCTAssertEqual(queue.next, "uuid-2")
    }

    func testLIFONext() {
        var queue = PasteStackQueue()
        queue.isLIFO = true
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.enqueue("uuid-3")
        XCTAssertEqual(queue.next, "uuid-3")
    }

    func testLIFOAdvance() {
        var queue = PasteStackQueue()
        queue.isLIFO = true
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.enqueue("uuid-3")
        let next = queue.advance()
        XCTAssertEqual(next, "uuid-3")
        XCTAssertEqual(queue.itemUUIDs, ["uuid-1", "uuid-2"])
        XCTAssertEqual(queue.next, "uuid-2")
    }

    func testAdvanceOnEmptyQueue() {
        var queue = PasteStackQueue()
        let next = queue.advance()
        XCTAssertNil(next)
        XCTAssertTrue(queue.isEmpty)
    }

    func testClear() {
        var queue = PasteStackQueue()
        queue.enqueue("uuid-1")
        queue.enqueue("uuid-2")
        queue.clear()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        XCTAssertEqual(queue.itemUUIDs, [])
    }

    func testIsEmptyAndCount() {
        var queue = PasteStackQueue()
        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
        queue.enqueue("uuid-1")
        XCTAssertFalse(queue.isEmpty)
        XCTAssertEqual(queue.count, 1)
    }

    func testEquatable() {
        var queue1 = PasteStackQueue()
        var queue2 = PasteStackQueue()
        XCTAssertEqual(queue1, queue2)

        queue1.enqueue("uuid-1")
        queue2.enqueue("uuid-1")
        XCTAssertEqual(queue1, queue2)

        queue1.isLIFO = true
        XCTAssertNotEqual(queue1, queue2)
    }
}
