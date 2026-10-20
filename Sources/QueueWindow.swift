// SPDX-License-Identifier: GPL-3.0-only
import Cocoa

final class QueueWindowController: NSWindowController, NSTableViewDataSource, NSTableViewDelegate {
    let queue: FileJobQueue
    let table = NSTableView()
    let detail = NSTextView()
    let summary = NSTextField(labelWithString: "")
    let pauseButton = NSButton(title: "Sırayı Duraklat", target: nil, action: nil)
    let cancelButton = NSButton(title: "Seçili İşi İptal Et", target: nil, action: nil)
    private var selectedID: UUID?
    private var refreshing = false
    init(queue: FileJobQueue) {
        self.queue = queue
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 520), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "Total Command — İşlem Kuyruğu"; window.minSize = NSSize(width: 720, height: 420); window.isReleasedWhenClosed = false
        super.init(window: window)
        for (key, title, width) in [("title", "İşlem", 150.0), ("state", "Durum", 130.0), ("progress", "İlerleme", 85.0), ("detail", "Kaynak / Hedef", 450.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(key)); column.title = title; column.width = width; table.addTableColumn(column)
        }
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle; table.autoresizingMask = [.width]; table.frame = NSRect(x: 0, y: 0, width: 868, height: 0)
        table.delegate = self; table.dataSource = self; table.rowHeight = 26; table.usesAlternatingRowBackgroundColors = true; table.allowsEmptySelection = true
        let scroll = NSScrollView(); scroll.documentView = table; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        detail.isEditable = false; detail.font = .systemFont(ofSize: 12); detail.textContainerInset = NSSize(width: 8, height: 8)
        let detailScroll = NSScrollView(); detailScroll.documentView = detail; detailScroll.hasVerticalScroller = true; detail.isVerticallyResizable = true; detail.autoresizingMask = [.width]; detail.textContainer?.widthTracksTextView = true
        detailScroll.heightAnchor.constraint(equalToConstant: 100).isActive = true
        pauseButton.target = self; pauseButton.action = #selector(togglePause)
        cancelButton.target = self; cancelButton.action = #selector(cancelSelected)
        let cancelWaiting = NSButton(title: "Bekleyenleri İptal Et", target: self, action: #selector(cancelPending))
        let clear = NSButton(title: "Geçmişi Temizle", target: self, action: #selector(clearHistory))
        let tools = NSStackView(views: [pauseButton, cancelButton, cancelWaiting, NSView(), clear]); tools.spacing = 8
        let note = NSTextField(wrappingLabelWithString: "Duraklatma, sıradaki işin başlamasını bekletir. Çalışan dosya işlemi tamamlanır. Geçmişi temizlemek dosyaları silmez."); note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [summary, tools, scroll, detailScroll, note]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 16), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -16), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 16), stack.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor, constant: -16)])
        for view in [tools, scroll, detailScroll, note] { view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        window.center(); refresh()
    }
    required init?(coder: NSCoder) { fatalError() }
    var selected: FileJob? { queue.jobs.first { $0.id == selectedID } }
    func refresh() {
        let id = selectedID
        refreshing = true
        table.reloadData()
        if let id, let index = queue.jobs.firstIndex(where: { $0.id == id }) { table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false) }
        else { selectedID = nil; table.deselectAll(nil) }
        refreshing = false
        let failed = queue.jobs.filter { $0.status == .failed }.count
        summary.stringValue = "\(queue.current == nil ? 0 : 1) çalışan · \(queue.waitingCount) bekleyen · \(failed) hatalı\(queue.paused ? " · Sıra duraklatıldı" : "")"
        pauseButton.title = queue.paused ? "Sırayı Sürdür" : "Sırayı Duraklat"
        showDetail()
    }
    func showDetail() {
        cancelButton.isEnabled = selected.map { $0.status == .waiting || $0.status == .running } ?? false
        guard let job = selected else { detail.string = "İşlem ayrıntıları için bir satır seçin. Geçmiş bu oturum boyunca tutulur."; return }
        detail.string = "\(job.title) — \(job.statusText)\n\(job.detail)\n\(job.progressText)\(job.errorText.isEmpty ? "" : "\n" + job.errorText)"
    }
    func numberOfRows(in tableView: NSTableView) -> Int { queue.jobs.count }
    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !refreshing else { return }
        selectedID = queue.jobs.indices.contains(table.selectedRow) ? queue.jobs[table.selectedRow].id : nil
        showDetail()
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let job = queue.jobs[row]
        let text: String
        switch tableColumn?.identifier.rawValue {
        case "title": text = job.title
        case "state": text = job.statusText
        case "progress": text = job.status == .waiting ? "—" : "\(Int(job.progress * 100))%"
        default: text = job.detail
        }
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 12); label.lineBreakMode = .byTruncatingMiddle; label.toolTip = text
        if job.status == .failed { label.textColor = .systemRed }
        return label
    }
    @objc func togglePause() { queue.paused.toggle() }
    @objc func cancelSelected() { if let job = selected { queue.cancel(job.id) } }
    @objc func cancelPending() { queue.cancelWaiting() }
    @objc func clearHistory() { queue.clearFinished() }
}
