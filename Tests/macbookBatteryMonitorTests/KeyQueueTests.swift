import Foundation

struct KeyQueueTests {
    /// 只有要先送出組字的按鍵開始排隊；排隊中後面的按鍵也要排，順序才不會亂；全部送出後回到直接放行
    func testQueuesInOrderUntilSent() {
        var queue = KeyQueue()
        XCTAssertTrue(!queue.enqueueIfNeeded(commitFirst: false, now: 0))
        XCTAssertTrue(queue.enqueueIfNeeded(commitFirst: true, now: 0))
        XCTAssertTrue(queue.enqueueIfNeeded(commitFirst: false, now: 0.1))
        XCTAssertEqual(queue.queued, 2)
        queue.sent(generation: queue.generation, now: 0.2)
        queue.sent(generation: queue.generation, now: 0.3)
        XCTAssertTrue(!queue.isQueuing)
        XCTAssertTrue(!queue.enqueueIfNeeded(commitFirst: false, now: 0.4))
        // 多送一次也不會變負數
        queue.sent(generation: queue.generation, now: 0.5)
        XCTAssertEqual(queue.queued, 0)
    }

    /// 主執行緒超過 1 秒沒送出：放棄排隊並換編號；之後送來的舊編號按鍵不算
    func testGivesUpWhenMainThreadIsStuck() {
        var queue = KeyQueue()
        _ = queue.enqueueIfNeeded(commitFirst: true, now: 10)
        let old = queue.generation
        XCTAssertTrue(!queue.dropIfStuck(now: 10.9))
        XCTAssertTrue(queue.dropIfStuck(now: 11.1))
        XCTAssertTrue(!queue.isQueuing)
        XCTAssertTrue(queue.generation != old)
        _ = queue.enqueueIfNeeded(commitFirst: true, now: 12)
        queue.sent(generation: old, now: 12.1)
        XCTAssertEqual(queue.queued, 1)
        // 沒在排隊時不會因為時間久了就換編號
        var idle = KeyQueue()
        XCTAssertTrue(!idle.dropIfStuck(now: 100))
        XCTAssertEqual(idle.generation, 0)
    }

    /// 每送出一個就重新計時：主執行緒慢但還在處理時不算卡住
    func testSlowButProgressingIsNotStuck() {
        var queue = KeyQueue()
        _ = queue.enqueueIfNeeded(commitFirst: true, now: 0)
        _ = queue.enqueueIfNeeded(commitFirst: false, now: 0)
        queue.sent(generation: queue.generation, now: 0.8)
        XCTAssertTrue(!queue.dropIfStuck(now: 1.5))
        XCTAssertTrue(queue.dropIfStuck(now: 1.9))
    }

    /// 自動重複的按鍵只在排隊中丟掉
    func testDropsRepeatsOnlyWhileQueuing() {
        var queue = KeyQueue()
        XCTAssertTrue(!queue.dropsRepeat(true))
        _ = queue.enqueueIfNeeded(commitFirst: true, now: 0)
        XCTAssertTrue(queue.dropsRepeat(true))
        XCTAssertTrue(!queue.dropsRepeat(false))
    }
}
