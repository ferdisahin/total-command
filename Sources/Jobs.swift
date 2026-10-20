// SPDX-License-Identifier: GPL-3.0-only
import Foundation

final class JobState: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
}

final class FileJob {
    enum Status { case waiting, running, completed, failed, cancelled }
    typealias Work = (JobState, @escaping (Int, Int, String) -> Void) throws -> Void
    let id = UUID()
    let title: String
    let detail: String
    let control = JobState()
    let work: Work
    let complete: () -> Void
    let reportFailure: Bool
    var status: Status = .waiting
    var progress = 0.0
    var progressText = ""
    var errorText = ""
    var finishedAt: Date?
    init(title: String, detail: String, reportFailure: Bool, work: @escaping Work, complete: @escaping () -> Void) {
        self.title = title; self.detail = detail; self.reportFailure = reportFailure; self.work = work; self.complete = complete
    }
    var statusText: String {
        switch status {
        case .waiting: return L("Bekliyor")
        case .running: return control.cancelled ? L("İptal bekleniyor") : L("Çalışıyor")
        case .completed: return L("Tamamlandı")
        case .failed: return L("Hata")
        case .cancelled: return L("İptal edildi")
        }
    }
}

// State and callbacks belong to the main thread; only Work executes in the background.
final class FileJobQueue {
    private(set) var jobs: [FileJob] = []
    private(set) var current: FileJob?
    private var finishing = false
    var changed: (() -> Void)?
    var finished: ((FileJob, Error?) -> Void)?
    var cancelRunning: (() -> Void)?
    var paused = false { didSet { changed?(); pump() } }
    var waitingCount: Int { jobs.filter { $0.status == .waiting }.count }
    var busy: Bool { current != nil || waitingCount > 0 }
    @discardableResult
    func enqueue(title: String, detail: String = "", reportFailure: Bool = false, work: @escaping FileJob.Work, complete: @escaping () -> Void = {}) -> FileJob {
        let job = FileJob(title: title, detail: detail, reportFailure: reportFailure, work: work, complete: complete)
        jobs.append(job); trimHistory(); changed?(); pump(); return job
    }
    func cancel(_ id: UUID) {
        guard let job = jobs.first(where: { $0.id == id }) else { return }
        if job.status == .waiting { job.control.cancel(); job.status = .cancelled; job.finishedAt = Date() }
        else if job.status == .running { job.control.cancel(); cancelRunning?() }
        trimHistory(); changed?(); pump()
    }
    func cancelWaiting() { for job in jobs where job.status == .waiting { job.control.cancel(); job.status = .cancelled; job.finishedAt = Date() }; trimHistory(); changed?() }
    func clearFinished() { jobs.removeAll { $0.status != .waiting && $0.status != .running }; changed?() }
    private func trimHistory() {
        var extra = jobs.filter { $0.status != .waiting && $0.status != .running }.count - 100
        jobs.removeAll { job in
            guard extra > 0, job.status != .waiting, job.status != .running else { return false }
            extra -= 1; return true
        }
    }
    private func pump() {
        guard current == nil, !paused, !finishing, let job = jobs.first(where: { $0.status == .waiting }) else { return }
        current = job; job.status = .running; changed?()
        DispatchQueue.global(qos: .userInitiated).async {
            var failure: Error?
            do {
                try job.work(job.control) { done, total, name in
                    DispatchQueue.main.async {
                        guard self.current === job else { return }
                        job.progress = min(1, max(0, Double(done) / Double(max(total, 1))))
                        job.progressText = "\(done)/\(total) · \(name)"; self.changed?()
                    }
                }
            } catch { failure = error }
            DispatchQueue.main.async {
                self.finishing = true; self.current = nil
                job.errorText = failure?.localizedDescription ?? ""
                job.status = job.control.cancelled ? .cancelled : failure == nil ? .completed : .failed
                if job.status == .completed { job.progress = 1 }
                job.finishedAt = Date(); self.trimHistory(); self.changed?()
                self.finished?(job, failure)
                if job.status == .completed { job.complete() }
                self.finishing = false; self.pump()
            }
        }
    }
}
