// SPDX-License-Identifier: GPL-3.0-only
import Foundation

func testJobs() {
    func drain(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        assert(condition(), "Queue did not settle")
    }
    let queue = FileJobQueue(); queue.paused = true
    let lock = NSLock(); var order: [Int] = []
    func record(_ n: Int) { lock.lock(); order.append(n); lock.unlock() }
    let first = queue.enqueue(title: "first", work: { _, progress in record(1); progress(1, 1, "one") })
    let skipped = queue.enqueue(title: "cancelled", work: { _, _ in record(2) })
    let third = queue.enqueue(title: "third", work: { _, _ in record(3) })
    assert(queue.current == nil && queue.waitingCount == 3)
    queue.cancel(skipped.id); assert(skipped.status == .cancelled && queue.waitingCount == 2)
    queue.paused = false; drain { !queue.busy }
    assert(order == [1, 3] && first.status == .completed && third.status == .completed)
    assert(first.progress == 1)
    var completedFailure = false
    let failure = queue.enqueue(title: "failure", work: { _, _ in throw PanelError(message: "expected failure") }, complete: { completedFailure = true })
    let next = queue.enqueue(title: "after failure", work: { _, _ in record(4) })
    drain { !queue.busy }
    assert(failure.status == .failed && failure.errorText == "expected failure" && !completedFailure && next.status == .completed)
    var completedCancellation = false
    let running = queue.enqueue(title: "running cancellation", work: { state, _ in
        while !state.cancelled { _ = DispatchSemaphore(value: 0).wait(timeout: .now() + 0.005) }
    }, complete: { completedCancellation = true })
    queue.cancel(running.id); drain { !queue.busy }
    assert(running.status == .cancelled && !completedCancellation)
    let beforePause = queue.enqueue(title: "finish current", work: { _, _ in })
    let afterPause = queue.enqueue(title: "wait while paused", work: { _, _ in })
    queue.paused = true; drain { queue.current == nil }
    assert(beforePause.status == .completed && afterPause.status == .waiting)
    queue.clearFinished(); assert(queue.jobs.count == 1 && queue.jobs.first === afterPause)
    queue.cancelWaiting(); assert(afterPause.status == .cancelled && !queue.busy)
    queue.clearFinished(); assert(queue.jobs.isEmpty)
    queue.paused = false
    for _ in 0..<105 { queue.enqueue(title: "history", work: { _, _ in }) }
    drain { !queue.busy }; assert(queue.jobs.count == 100)
    queue.paused = true
    for _ in 0..<105 { queue.enqueue(title: "cancelled history", work: { _, _ in fatalError("Cancelled work must not run") }) }
    queue.cancelWaiting(); assert(queue.jobs.count == 100 && !queue.busy)
    print("PASS: sequential queue, pause/resume, pending/running cancellation, failure continuation, bounded history")
}
