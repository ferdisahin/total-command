// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 Ferdi Sahin

import Cocoa
import QuickLookUI
import QuickLookThumbnailing

final class IconItem: NSCollectionViewItem {
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 112, height: 104))
        let icon = NSImageView(); icon.imageScaling = .scaleProportionallyUpOrDown
        let label = NSTextField(wrappingLabelWithString: ""); label.alignment = .center; label.font = .systemFont(ofSize: 11); label.maximumNumberOfLines = 2
        let stack = NSStackView(views: [icon, label]); stack.orientation = .vertical; stack.spacing = 5; stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack); NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4), stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4), stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 5), icon.heightAnchor.constraint(equalToConstant: 60), icon.widthAnchor.constraint(equalToConstant: 64)])
        imageView = icon; textField = label; view.wantsLayer = true; view.layer?.cornerRadius = 6
    }
    override var isSelected: Bool { didSet { view.layer?.backgroundColor = isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.3).cgColor : NSColor.clear.cgColor } }
}
final class DropTable: NSTableView {
    var onDrop: (([URL]) -> Void)?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }; onDrop?(urls); return true
    }
}
final class DropGrid: NSCollectionView {
    var onDrop: (([URL]) -> Void)?
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        guard !urls.isEmpty else { return false }; onDrop?(urls); return true
    }
}
final class FilePane: NSView, NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate, NSSearchFieldDelegate {
    var location = FileManager.default.homeDirectoryForCurrentUser
    var entries: [Entry] = []
    var activated: (() -> Void)?
    var report: ((Error) -> Void)?
    var archiveOpened: ((URL) -> Void)?
    var dropped: (([URL], URL) -> Void)?
    var paths: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    var tabIndex = 0
    var history: [URL] = []; var future: [URL] = []
    var showHidden = false
    var sortKey = "name"; var ascending = true
    var archiveRoot: URL?
    var archiveSource: URL?
    var updating = false
    var remoteSession: RemoteSession?
    var lockedTabs: Set<Int> = []
    let path = NSTextField(), search = NSSearchField(), tabs = NSSegmentedControl(), table = DropTable(), grid = DropGrid()
    let listScroll = NSScrollView(), gridScroll = NSScrollView(), body = NSView()
    let status = NSTextField(labelWithString: ""), disk = NSPopUpButton(), mode = NSSegmentedControl(labels: [L("Liste"), L("Simgeler")], trackingMode: .selectOne, target: nil, action: nil)
    var gridMode: Bool { mode.selectedSegment == 1 }
    var selected: [URL] { gridMode ? grid.selectionIndexPaths.sorted { $0.item < $1.item }.compactMap { entries.indices.contains($0.item) && !entries[$0.item].isParent ? entries[$0.item].url : nil } : table.selectedRowIndexes.compactMap { entries.indices.contains($0) && !entries[$0].isParent ? entries[$0].url : nil } }
    init() {
        super.init(frame: .zero)
        let back = iconButton("chevron.left", L("Geri"), #selector(goBack)), forward = iconButton("chevron.right", L("İleri"), #selector(goForward)), up = iconButton("arrow.up", L("Üst klasör"), #selector(goUp))
        path.font = .systemFont(ofSize: 12); path.target = self; path.action = #selector(enterPath); path.delegate = self
        search.placeholderString = L("Adına göre filtrele"); search.delegate = self
        tabs.target = self; tabs.action = #selector(changeTab); tabs.segmentStyle = .texturedRounded
        let add = iconButton("plus", L("Yeni sekme"), #selector(newTab)), close = iconButton("xmark", L("Sekmeyi kapat"), #selector(closeTab))
        let tabRow = NSStackView(views: [tabs, add, close]); tabRow.spacing = 5
        tabs.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let nav = NSStackView(views: [back, forward, up, path]); nav.spacing = 5
        path.setContentHuggingPriority(.defaultLow, for: .horizontal)
        disk.target = self; disk.action = #selector(pickDisk)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let places = [(L("Başlangıç"), home), (L("Masaüstü"), home.appendingPathComponent("Desktop")), (L("Belgeler"), home.appendingPathComponent("Documents")), (L("İndirilenler"), home.appendingPathComponent("Downloads"))] + (FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []).map { ($0.lastPathComponent.isEmpty ? "Macintosh HD" : $0.lastPathComponent, $0) }
        for (label, url) in places { disk.addItem(withTitle: label); disk.lastItem?.representedObject = url }
        disk.widthAnchor.constraint(equalToConstant: 155).isActive = true
        mode.selectedSegment = 0; mode.target = self; mode.action = #selector(switchViewMode)
        let tools = NSStackView(views: [disk, search, mode]); tools.spacing = 7; search.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for (id, title, width) in [("name", L("Ad"), 245.0), ("ext", L("Uzantı"), 55.0), ("size", L("Boyut"), 78.0), ("date", L("Değiştirilme"), 125.0)] {
            let c = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); c.title = title; c.width = width; c.minWidth = id == "name" ? 100 : 45
            c.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true); table.addTableColumn(c)
        }
        table.delegate = self; table.dataSource = self; table.allowsMultipleSelection = true; table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = CGFloat(Prefs.int("rowHeight")); table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.target = self; table.action = #selector(clicked); table.doubleAction = #selector(openSelected)
        table.registerForDraggedTypes([.fileURL]); table.setDraggingSourceOperationMask(.copy, forLocal: false); table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.onDrop = { [weak self] urls in guard let self else { return }; self.activated?(); self.dropped?(urls, self.location) }
        listScroll.documentView = table; listScroll.hasVerticalScroller = true
        let layout = NSCollectionViewFlowLayout(); layout.itemSize = NSSize(width: 112, height: 105); layout.minimumInteritemSpacing = 5; layout.minimumLineSpacing = 8; layout.sectionInset = NSEdgeInsets(top: 10, left: 8, bottom: 10, right: 8)
        grid.registerForDraggedTypes([.fileURL]); grid.onDrop = { [weak self] urls in guard let self else { return }; self.activated?(); self.dropped?(urls, self.location) }
        grid.collectionViewLayout = layout; grid.dataSource = self; grid.delegate = self; grid.isSelectable = true; grid.allowsMultipleSelection = true
        grid.register(IconItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("icon"))
        grid.setDraggingSourceOperationMask(.copy, forLocal: false); grid.setDraggingSourceOperationMask(.copy, forLocal: true)
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(openSelected)); doubleClick.numberOfClicksRequired = 2; grid.addGestureRecognizer(doubleClick)
        gridScroll.documentView = grid; gridScroll.hasVerticalScroller = true; gridScroll.isHidden = true
        for v in [listScroll, gridScroll] { v.translatesAutoresizingMaskIntoConstraints = false; body.addSubview(v); NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: body.leadingAnchor), v.trailingAnchor.constraint(equalTo: body.trailingAnchor), v.topAnchor.constraint(equalTo: body.topAnchor), v.bottomAnchor.constraint(equalTo: body.bottomAnchor)]) }
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [tabRow, nav, tools, body, status]); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 7; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack); NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8), stack.topAnchor.constraint(equalTo: topAnchor, constant: 8), stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8)])
        for v in [tabRow, nav, tools, body, status] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        updateTabs(); reload()
    }
    required init?(coder: NSCoder) { fatalError() }
    func iconButton(_ name: String, _ title: String, _ action: Selector) -> NSButton { let b = NSButton(image: NSImage(systemSymbolName: name, accessibilityDescription: title)!, target: self, action: action); b.bezelStyle = .texturedRounded; b.toolTip = title; return b }
    func restore(_ key: String) {
        showHidden = UserDefaults.standard.bool(forKey: key + "Hidden"); mode.selectedSegment = UserDefaults.standard.integer(forKey: key + "Mode"); gridScroll.isHidden = !gridMode; listScroll.isHidden = gridMode
        let stored = UserDefaults.standard.stringArray(forKey: key) ?? []
        let valid = stored.map { URL(fileURLWithPath: $0) }.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
        if !valid.isEmpty { paths = valid; tabIndex = 0; location = paths[0]; updateTabs(); reload() }
    }
    func save(_ key: String) { UserDefaults.standard.set(showHidden, forKey: key + "Hidden"); UserDefaults.standard.set(mode.selectedSegment, forKey: key + "Mode"); UserDefaults.standard.set(paths.filter { !$0.path.contains("TotalCommand-Archive-") }.map(\.path), forKey: key) }
    func updateTabs() {
        tabs.segmentCount = paths.count
        for (i, u) in paths.enumerated() {
            let baseLabel = u.lastPathComponent.isEmpty ? "/" : u.lastPathComponent
            let isLocked = lockedTabs.contains(i)
            let displayLabel = isLocked ? "🔒 \(baseLabel)" : baseLabel
            tabs.setLabel(displayLabel, forSegment: i)
            tabs.setWidth(min(160, max(60, Double(displayLabel.count) * 7 + 18)), forSegment: i)
        }
        tabs.selectedSegment = tabIndex
    }
    @objc func newTab() { paths.append(location); tabIndex = paths.count - 1; updateTabs(); activated?() }
    @objc func closeTab() {
        guard paths.count > 1 else { return }
        if lockedTabs.contains(tabIndex) {
            report?(PanelError(message: L("Kilitli sekmeler kapatılamaz.")))
            return
        }
        paths.remove(at: tabIndex)
        var newLocked: Set<Int> = []
        for idx in lockedTabs {
            if idx < tabIndex { newLocked.insert(idx) }
            else if idx > tabIndex { newLocked.insert(idx - 1) }
        }
        lockedTabs = newLocked
        tabIndex = min(tabIndex, paths.count - 1)
        location = paths[tabIndex]
        history = []; future = []; archiveRoot = nil; search.stringValue = ""
        updateTabs()
        reload()
        activated?()
    }
    func toggleLockTab() {
        if lockedTabs.contains(tabIndex) {
            lockedTabs.remove(tabIndex)
        } else {
            lockedTabs.insert(tabIndex)
        }
        updateTabs()
    }
    @objc func changeTab() { tabIndex = tabs.selectedSegment; location = paths[tabIndex]; history = []; future = []; archiveRoot = nil; search.stringValue = ""; reload(); activated?() }
    @objc func switchViewMode() { let urls = gridMode ? table.selectedRowIndexes.compactMap { entries.indices.contains($0) && !entries[$0].isParent ? entries[$0].url : nil } : grid.selectionIndexPaths.compactMap { entries.indices.contains($0.item) && !entries[$0.item].isParent ? entries[$0.item].url : nil }; gridScroll.isHidden = !gridMode; listScroll.isHidden = gridMode; select(urls); activated?() }
    @objc func pickDisk() { guard let u = disk.selectedItem?.representedObject as? URL else { return }; navigate(u); activated?() }
    func controlTextDidBeginEditing(_ obj: Notification) { activated?() }
    func controlTextDidChange(_ obj: Notification) { if obj.object as? NSSearchField === search { reload() } }
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            search.stringValue = ""
            reload()
            window?.makeFirstResponder(gridMode ? grid : table)
            return true
        }
        return false
    }
    func reload() {
        let selection = selected
        updating = true; defer { updating = false }
        if let remote = remoteSession {
            path.stringValue = remote.displayURLString
            remote.listDirectory(path: remote.currentPath) { [weak self] result in
                guard let self else { return }
                switch result {
                case .success(let items):
                    var list = items.map { $0.toAppEntry(baseURL: remote.virtualURL) }
                    if remote.currentPath != "/" && !remote.currentPath.isEmpty {
                        let parentURL = remote.virtualURL.deletingLastPathComponent()
                        list.append(Entry(url: parentURL, directory: true, size: 0, date: .distantPast, isParent: true))
                    }
                    self.entries = list
                    self.sort()
                    self.table.reloadData()
                    self.grid.reloadData()
                    self.select(selection)
                    self.updateStatus()
                case .failure(let err):
                    self.report?(err)
                }
            }
            return
        }
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: location, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey], options: showHidden ? [] : [.skipsHiddenFiles])
            entries = try urls.filter { search.stringValue.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(search.stringValue) }.map {
                let v = try $0.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]); return Entry(url: $0, directory: v.isDirectory ?? false, size: Int64(v.fileSize ?? 0), date: v.contentModificationDate ?? .distantPast)
            }
            if location.deletingLastPathComponent() != location || archiveRoot == location { entries.append(Entry(url: location.deletingLastPathComponent(), directory: true, size: 0, date: .distantPast, isParent: true)) }
            sort(); path.stringValue = location.path; table.reloadData(); grid.reloadData(); select(selection); updateStatus()
        } catch { report?(error) }
    }
    func sort() {
        entries.sort { a, b in
            if a.isParent != b.isParent { return a.isParent }
            if Prefs.bool("foldersFirst"), a.directory != b.directory { return a.directory }
            var cmp: ComparisonResult
            switch sortKey {
            case "size": cmp = a.size == b.size ? .orderedSame : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case "date": cmp = a.date.compare(b.date)
            case "ext": cmp = a.ext.localizedStandardCompare(b.ext)
            default: cmp = a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent)
            }
            if cmp == .orderedSame { cmp = a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) }
            return ascending ? cmp == .orderedAscending : cmp == .orderedDescending
        }
    }
    func navigate(_ url: URL, record: Bool = true) {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { report?(PanelError(message: L("Klasör bulunamadı: {0}", url.path))); path.stringValue = location.path; return }
        if lockedTabs.contains(tabIndex) && url != location {
            paths.append(url)
            tabIndex = paths.count - 1
            location = url
            history = []; future = []; archiveRoot = nil; search.stringValue = ""
            updateTabs()
            reload()
            return
        }
        if record, location != url { history.append(location); future = [] }
        location = url; paths[tabIndex] = url; search.stringValue = ""; table.deselectAll(nil); grid.deselectAll(nil); updateTabs(); reload()
    }
    @objc func goBack() { guard let u = history.popLast() else { return }; future.append(location); navigate(u, record: false) }
    @objc func goForward() { guard let u = future.popLast() else { return }; history.append(location); navigate(u, record: false) }
    @objc func clicked() { activated?() }
    @objc func enterPath() { navigate(URL(fileURLWithPath: NSString(string: path.stringValue).expandingTildeInPath)) }
    @objc func goUp() {
        if let remote = remoteSession {
            let cur = remote.currentPath
            if cur != "/" && !cur.isEmpty {
                let parent = (cur as NSString).deletingLastPathComponent
                remote.currentPath = parent.isEmpty ? "/" : parent
                reload()
            }
            return
        }
        if let root = archiveRoot, location == root, let source = archiveSource { archiveRoot = nil; archiveSource = nil; navigate(source.deletingLastPathComponent()); select([source]) } else { navigate(location.deletingLastPathComponent()) }
    }
    @objc func openSelected() {
        activated?()
        let rawSelection = gridMode ? grid.selectionIndexPaths.map(\.item).sorted() : Array(table.selectedRowIndexes)
        if let first = rawSelection.first, entries.indices.contains(first), entries[first].isParent, selected.isEmpty { goUp(); return }
        guard let url = selected.first else { return }
        if let remote = remoteSession {
            if let entry = entries.first(where: { $0.url == url }) {
                if entry.directory {
                    let cur = remote.currentPath
                    let next = cur.hasSuffix("/") ? "\(cur)\(entry.url.lastPathComponent)" : "\(cur)/\(entry.url.lastPathComponent)"
                    remote.currentPath = next
                    reload()
                } else {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(entry.url.lastPathComponent)
                    let state = JobState()
                    let rPath = remote.currentPath.hasSuffix("/") ? "\(remote.currentPath)\(entry.url.lastPathComponent)" : "\(remote.currentPath)/\(entry.url.lastPathComponent)"
                    try? remote.download(remotePath: rPath, to: tmp, control: state, progress: { _, _, _ in })
                    NSWorkspace.shared.open(tmp)
                }
            }
            return
        }
        if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { navigate(url) }
        else if Prefs.bool("browseArchives"), ["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz"].contains(url.pathExtension.lowercased()) { archiveOpened?(url) }
        else { NSWorkspace.shared.open(url) }
    }
    func select(_ urls: [URL]) {
        let prior = updating; updating = true; defer { updating = prior }
        let set = Set(urls); let indices = entries.indices.filter { !entries[$0].isParent && set.contains(entries[$0].url) }
        table.selectRowIndexes(IndexSet(indices), byExtendingSelection: false); grid.selectionIndexPaths = Set(indices.map { IndexPath(item: $0, section: 0) }); updateStatus()
    }
    func selectPattern(_ pattern: String) { let predicate = NSPredicate(format: "SELF LIKE[cd] %@", pattern); select(entries.filter { predicate.evaluate(with: $0.url.lastPathComponent) }.map(\.url)) }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableViewSelectionDidChange(_ notification: Notification) { if !gridMode && !updating { activated?(); updateStatus() } }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) { if let d = tableView.sortDescriptors.first { sortKey = d.key ?? "name"; ascending = d.ascending; reload() } }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { entries[row].isParent ? nil : entries[row].url as NSURL }
    func updateStatus() {
        let urls = Set(selected); let bytes = entries.filter { urls.contains($0.url) }.reduce(Int64(0)) { $0 + ($1.directory ? 0 : $1.size) }
        let free = remoteSession != nil ? "— (Uzak)" : (try? location.resourceValues(forKeys: [.volumeAvailableCapacityKey]).volumeAvailableCapacity).map { ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) } ?? "—"
        status.stringValue = L("{0} öğe · {1} seçili ({2}) · Boş: {3}", entries.filter { !$0.isParent }.count, urls.count, ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file), free)
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let e = entries[row]; let key = tableColumn?.identifier.rawValue
        if key == "name" {
            let icon = NSImageView(); icon.image = e.isParent ? NSImage(systemSymbolName: "arrow.up", accessibilityDescription: L("Üst klasör")) : NSWorkspace.shared.icon(forFile: e.url.path); icon.widthAnchor.constraint(equalToConstant: 16).isActive = true; icon.heightAnchor.constraint(equalToConstant: 16).isActive = true
            let label = NSTextField(labelWithString: e.isParent ? "[..]" : e.url.lastPathComponent); label.font = .systemFont(ofSize: CGFloat(Prefs.int("fontSize"))); label.lineBreakMode = .byTruncatingMiddle
            let stack = NSStackView(views: [icon, label]); stack.spacing = 6; stack.toolTip = e.isParent ? L("Üst klasöre çık") : e.url.path; return stack
        }
        if e.isParent { return NSTextField(labelWithString: "") }
        let text = key == "ext" ? e.ext : key == "size" ? (e.directory ? "<DIR>" : ByteCountFormatter.string(fromByteCount: e.size, countStyle: .file)) : DateFormatter.localizedString(from: e.date, dateStyle: Prefs.string("dateStyle") == "long" ? .long : .short, timeStyle: .short)
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: 11); label.textColor = .secondaryLabelColor; return label
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("icon"), for: indexPath); let e = entries[indexPath.item]
        item.representedObject = e.url
        item.imageView?.image = e.isParent ? NSImage(systemSymbolName: "arrow.up", accessibilityDescription: L("Üst klasör")) : NSWorkspace.shared.icon(forFile: e.url.path)
        if Prefs.bool("thumbnails"), !e.directory, ["png", "jpg", "jpeg", "heic", "gif", "webp", "pdf", "mov", "mp4"].contains(e.ext.lowercased()) {
            let request = QLThumbnailGenerator.Request(fileAt: e.url, size: NSSize(width: 64, height: 60), scale: 2, representationTypes: .thumbnail)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { [weak item] representation, _ in
                DispatchQueue.main.async { if let item, item.representedObject as? URL == e.url, let representation { item.imageView?.image = representation.nsImage } }
            }
        }
        item.textField?.stringValue = e.isParent ? "[..]" : e.url.lastPathComponent; item.view.toolTip = e.isParent ? L("Üst klasöre çık") : e.url.path; return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { if !updating { activated?(); updateStatus() } }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateStatus() }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? { entries[indexPath.item].isParent ? nil : entries[indexPath.item].url as NSURL }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, QLPreviewPanelDataSource {
    var window: NSWindow!
    let left = FilePane(), right = FilePane()
    var activeLeft = true
    var active: FilePane { activeLeft ? left : right }; var other: FilePane { activeLeft ? right : left }
    let indicator = NSTextField(labelWithString: L("Sol panel etkin")), progress = NSProgressIndicator(), cancel = NSButton(title: L("İptal"), target: nil, action: nil)
    let command = NSTextField()
    var commandBar: NSView?
    var logWindows: [NSWindow] = []
    var settingsController: SettingsController?
    let updateChecker = UpdateChecker()
    var updateTimer: Timer?
    var manualUpdateRequested = false
    var pendingUpdate: AppRelease?
    var pendingUpdateIsManual = false
    let operations = FileJobQueue()
    var queueController: QueueWindowController?
    let queueButton = NSButton(title: L("İşlem Kuyruğu"), target: nil, action: nil)
    var siteManagerController: SiteManagerController?
    var quickConnectController: QuickConnectController?
    var diffController: DiffWindowController?
    var multiRenameController: MultiRenameWindowController?
    var splitController: SplitWindowController?
    var combineController: CombineWindowController?
    var syncWindowController: SyncWindowController?
    var job: JobState? { operations.current?.control }
    var process: Process?; var previewURLs: [URL] = []; var temporary: [URL] = []
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular); buildMenus()
        operations.changed = { [weak self] in self?.refreshQueueStatus() }
        operations.cancelRunning = { [weak self] in if self?.process?.isRunning == true { self?.process?.terminate() } }
        operations.finished = { [weak self] job, error in
            guard let self else { return }; self.process = nil; self.refresh()
            if let error, job.reportFailure, !job.control.cancelled { self.show(error) }
        }
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = L("Total Command — Dosya Yöneticisi"); window.minSize = NSSize(width: 1080, height: 560); window.center(); window.delegate = self
        let split = NSSplitView(); split.isVertical = true; split.dividerStyle = .thin; split.addArrangedSubview(left); split.addArrangedSubview(right)
        let equal = left.widthAnchor.constraint(equalTo: right.widthAnchor); equal.priority = .defaultHigh; equal.isActive = true
        left.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true; right.widthAnchor.constraint(greaterThanOrEqualToConstant: 400).isActive = true
        left.activated = { [weak self] in self?.activate(true) }; right.activated = { [weak self] in self?.activate(false) }
        left.report = { [weak self] in self?.show($0) }; right.report = left.report
        left.archiveOpened = { [weak self] archive in guard let self else { return }; self.browseArchive(archive, pane: self.left) }; right.archiveOpened = { [weak self] archive in guard let self else { return }; self.browseArchive(archive, pane: self.right) }
        let drop: ([URL], URL) -> Void = { [weak self] urls, dest in self?.transfer(urls, to: dest, move: false) }; left.dropped = drop; right.dropped = drop
        for pane in [left, right] {
            let context = NSMenu()
            for (title, action) in [(L("Aç"), #selector(openItem)), (L("Önizle"), #selector(preview)), (L("Karşı panele kopyala"), #selector(copyFiles)), (L("Karşı panele taşı"), #selector(moveFiles)), (L("Yeniden adlandır…"), #selector(rename)), (L("Yolu kopyala"), #selector(copyPath)), (L("Finder’da göster"), #selector(reveal)), (L("Çöpe taşı…"), #selector(trash))] { let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; context.addItem(item) }
            pane.table.menu = context; pane.grid.menu = context.copy() as? NSMenu
        }
        let top = NSStackView(); top.spacing = 6
        top.addArrangedSubview(iconBarButton("arrow.clockwise", L("Yenile"), #selector(refresh)))
        top.addArrangedSubview(iconBarButton("list.bullet", L("Liste Görünümü"), #selector(showListMode)))
        top.addArrangedSubview(iconBarButton("square.grid.2x2", L("Simgeler / Küçük Resimler"), #selector(showGridMode)))
        top.addArrangedSubview(iconBarButton("eye", L("Önizle"), #selector(preview)))
        top.addArrangedSubview(iconBarButton("archivebox", L("Paketle / Sıkıştır…"), #selector(pack)))
        top.addArrangedSubview(iconBarButton("doc.badge.arrow.up", L("Arşivden Çıkar…"), #selector(unpack)))
        top.addArrangedSubview(iconBarButton("arrow.left.arrow.right", L("Dosya İçeriğini Karşılaştır…"), #selector(compareContent)))
        top.addArrangedSubview(iconBarButton("magnifyingglass", L("Dosya Ara…"), #selector(find)))
        top.addArrangedSubview(iconBarButton("character.cursor.ibeam", L("Toplu Yeniden Adlandır…"), #selector(batchRename)))
        top.addArrangedSubview(iconBarButton("arrow.triangle.2.circlepath", L("Klasörleri Eşitle…"), #selector(sync)))
        top.addArrangedSubview(iconBarButton("network", L("FTP / SFTP Bağlantı Yöneticisi…"), #selector(showSiteManager)))
        queueButton.target = self; queueButton.action = #selector(showQueue)
        queueButton.bezelStyle = .texturedRounded
        top.addArrangedSubview(queueButton)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        top.addArrangedSubview(spacer)
        top.addArrangedSubview(iconBarButton("gearshape", L("Ayarlar…"), #selector(settings)))
        let bottom = NSStackView(); bottom.distribution = .fillEqually; bottom.spacing = 4
        for (i, pair) in [(L("F3 Önizle"), #selector(preview)), (L("F4 Düzenle"), #selector(editFile)), (L("F5 Kopyala"), #selector(copyFiles)), (L("F6 Taşı"), #selector(moveFiles)), (L("F7 Klasör"), #selector(newFolder)), (L("F8 Çöpe Taşı"), #selector(trash))].enumerated() { let b = button(pair.0, pair.1); actionButtons[i + 3] = b; bottom.addArrangedSubview(b) }
        progress.isIndeterminate = false; progress.minValue = 0; progress.maxValue = 1; progress.style = .bar; progress.widthAnchor.constraint(equalToConstant: 180).isActive = true; progress.isHidden = true
        cancel.target = self; cancel.action = #selector(cancelJob); cancel.isHidden = true
        indicator.font = .systemFont(ofSize: 11, weight: .medium)
        let jobRow = NSStackView(views: [indicator, NSView(), progress, cancel]); jobRow.spacing = 8
        command.placeholderString = L("Etkin klasörde Terminal komutu çalıştır…"); command.font = .monospacedSystemFont(ofSize: 12, weight: .regular); command.target = self; command.action = #selector(runCommand)
        let commandRow = NSStackView(views: [NSTextField(labelWithString: L("Komut:")), command, button(L("Çalıştır"), #selector(runCommand))]); commandBar = commandRow; commandRow.spacing = 8; command.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let stack = NSStackView(views: [top, split, jobRow, commandRow, bottom]); stack.orientation = .vertical; stack.spacing = 8; stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10), stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10), stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 10), stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -10)])
        for v in [top, split, jobRow, commandRow, bottom] { v.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true }
        left.navigate(URL(fileURLWithPath: Prefs.string("leftStart"))); right.navigate(URL(fileURLWithPath: Prefs.string("rightStart")))
        if Prefs.bool("restoreTabs") { left.restore("leftTabs"); right.restore("rightTabs") }
        applySettings()
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); window.makeFirstResponder(left.table)
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in guard let self else { return event }; return self.key(event) }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.checkAutomaticUpdates() }
        DispatchQueue.main.async { [weak self] in self?.checkAutomaticUpdates() }
    }
    func button(_ title: String, _ action: Selector) -> NSButton { NSButton(title: title, target: self, action: action) }
    func iconBarButton(_ symbol: String, _ tooltip: String, _ action: Selector) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip) ?? NSImage(), target: self, action: action)
        b.bezelStyle = .texturedRounded
        b.toolTip = tooltip
        b.imageScaling = .scaleProportionallyDown
        b.widthAnchor.constraint(equalToConstant: 32).isActive = true
        b.heightAnchor.constraint(equalToConstant: 24).isActive = true
        return b
    }
    func buildMenus() {
        let root = NSMenu(); NSApp.mainMenu = root
        func submenu(_ title: String, _ items: [(String, Selector?, String)]) {
            let item = NSMenuItem(); item.title = title; root.addItem(item); let menu = NSMenu(title: title); item.submenu = menu
            for (label, action, key) in items {
                if label == "-" || action == nil {
                    menu.addItem(NSMenuItem.separator())
                } else {
                    let child = NSMenuItem(title: label, action: action, keyEquivalent: key)
                    child.target = self
                    menu.addItem(child)
                }
            }
        }
        submenu("Total Command", [
            (L("Total Command Hakkında"), #selector(about), ""),
            (L("Güncellemeleri Kontrol Et…"), #selector(checkUpdates), ""),
            (L("Ayarlar…"), #selector(settings), ","),
            ("-", nil, ""),
            (L("Çık"), #selector(quit), "q")
        ])
        submenu(L("Dosyalar"), [
            (L("Paketle / Sıkıştır…"), #selector(pack), ""),
            (L("Arşivden Çıkar…"), #selector(unpack), ""),
            (L("Arşivde Gezin…"), #selector(browse), ""),
            ("-", nil, ""),
            (L("Dosya İçeriğini Karşılaştır…"), #selector(compareContent), ""),
            (L("Özellikler / Bilgi Al"), #selector(info), "i"),
            (L("Toplu Yeniden Adlandır…"), #selector(batchRename), "m"),
            (L("Dosyayı Böl…"), #selector(splitFile), ""),
            (L("Dosyaları Birleştir…"), #selector(combineFiles), ""),
            ("-", nil, ""),
            (L("Klasör Aç…"), #selector(chooseFolder), "o"),
            (L("Yeni Klasör…"), #selector(newFolder), "n"),
            (L("Yeni Metin Dosyası…"), #selector(newFile), ""),
            (L("Yeniden Adlandır…"), #selector(rename), ""),
            (L("Finder’da Göster"), #selector(reveal), ""),
            (L("Çöpe Taşı…"), #selector(trash), "\u{7f}")
        ])
        submenu(L("Seçim"), [
            (L("Desene Göre Seç…"), #selector(selectPattern), "+"),
            (L("Tümünü Seç"), #selector(selectAll), "a"),
            (L("Seçimi Temizle"), #selector(clearSelection), "-"),
            (L("Seçimi Tersine Çevir"), #selector(invert), "*"),
            (L("Aynı Uzantıdakileri Seç"), #selector(selectSameExt), ""),
            ("-", nil, ""),
            (L("Seçili Adları Kopyala"), #selector(copySelectedNames), ""),
            (L("Yolu Kopyala"), #selector(copyPath), ""),
            ("-", nil, ""),
            (L("Panelleri Karşılaştır"), #selector(compare), "")
        ])
        submenu(L("Komutlar"), [
            (L("Dosya Ara…"), #selector(find), "f"),
            (L("Sık Kullanılan Klasörler…"), #selector(bookmarks), "d"),
            (L("Klasörleri Eşitle…"), #selector(sync), ""),
            ("-", nil, ""),
            (L("Geri"), #selector(goBackHistory), "["),
            (L("İleri"), #selector(goForwardHistory), "]"),
            ("-", nil, ""),
            (L("Terminal’de Aç"), #selector(terminal), ""),
            (L("İşlem Kuyruğu…"), #selector(showQueue), ""),
            ("-", nil, ""),
            (L("Panelleri Değiştir"), #selector(swap), "u"),
            (L("Hedefi Kaynağa Eşitle"), #selector(targetEqualsSource), "")
        ])
        submenu(L("Ağ"), [
            (L("FTP / SFTP Bağlantı Yöneticisi…"), #selector(showSiteManager), "F"),
            (L("Hızlı Bağlan…"), #selector(showQuickConnect), "N"),
            (L("Bağlantıyı Kes"), #selector(disconnectRemote), ""),
            (L("Sunucuya Bağlan…"), #selector(connectServer), "k")
        ])
        submenu(L("Görünüm"), [
            (L("Liste Görünümü"), #selector(showListMode), "1"),
            (L("Simgeler / Küçük Resimler"), #selector(showGridMode), "2"),
            (L("Önizle"), #selector(preview), "y"),
            ("-", nil, ""),
            (L("Yeni Sekme"), #selector(newTab), "t"),
            (L("Sekmeyi Kapat"), #selector(closeTab), "w"),
            (L("Sekmeyi Kilitle / Kilidi Aç"), #selector(toggleLockTab), "l"),
            ("-", nil, ""),
            (L("Ada Göre Sırala"), #selector(sortByName), ""),
            (L("Uzantıya Göre Sırala"), #selector(sortByExt), ""),
            (L("Boyuta Göre Sırala"), #selector(sortBySize), ""),
            (L("Tarihe Göre Sırala"), #selector(sortByDate), ""),
            ("-", nil, ""),
            (L("Yenile"), #selector(refresh), "r"),
            (L("Gizli Dosyaları Göster/Gizle"), #selector(hidden), ".")
        ])
        submenu(L("Yapılandırma"), [
            (L("Ayarlar…"), #selector(settings), ","),
            (L("Pencere Konumunu Kaydet"), #selector(saveWindowPosition), ""),
            (L("Ayarları Kaydet"), #selector(saveSettingsAction), "")
        ])
        submenu(L("Başlat"), [
            (L("Bu Klasörü Sık Kullanılanlara Ekle"), #selector(addBookmark), "D"),
            (L("Sık Kullanılan Klasörler…"), #selector(bookmarks), "b")
        ])
        submenu(L("Yardım"), [
            (L("Total Command Hakkında"), #selector(about), ""),
            (L("Güncellemeleri Kontrol Et…"), #selector(checkUpdates), "")
        ])
        let editItem = NSMenuItem(); root.addItem(editItem); let edit = NSMenu(title: L("Düzen")); editItem.submenu = edit
        for (title, action, key) in [(L("Kes"), #selector(cutClipboard), "x"), (L("Kopyala"), #selector(copyClipboard), "c"), (L("Yapıştır"), #selector(pasteClipboard), "v")] { let item = edit.addItem(withTitle: title, action: action, keyEquivalent: key); item.target = self }
    }
    @objc func selectSameExt() { guard let sel = active.selected.first else { return }; let ext = sel.pathExtension; active.selectPattern(ext.isEmpty ? "*" : "*." + ext) }
    @objc func copySelectedNames() { let names = (active.selected.isEmpty ? [active.location] : active.selected).map(\.lastPathComponent).joined(separator: "\n"); NSPasteboard.general.clearContents(); NSPasteboard.general.setString(names, forType: .string) }
    @objc func goBackHistory() { active.goBack() }
    @objc func goForwardHistory() { active.goForward() }
    @objc func targetEqualsSource() { other.navigate(active.location) }
    @objc func showListMode() { active.mode.selectedSegment = 0; active.switchViewMode() }
    @objc func showGridMode() { active.mode.selectedSegment = 1; active.switchViewMode() }
    @objc func sortByName() { active.sortKey = "name"; active.ascending = true; active.reload() }
    @objc func sortByExt() { active.sortKey = "ext"; active.ascending = true; active.reload() }
    @objc func sortBySize() { active.sortKey = "size"; active.ascending = false; active.reload() }
    @objc func sortByDate() { active.sortKey = "date"; active.ascending = false; active.reload() }
    @objc func saveWindowPosition() { window.saveFrame(usingName: "TotalCommandMainWindow"); indicator.stringValue = L("Pencere konumu kaydedildi.") }
    @objc func saveSettingsAction() { applySettings(); indicator.stringValue = L("Ayarlar kaydedildi.") }
    func key(_ event: NSEvent) -> NSEvent? {
        guard NSApp.keyWindow === window, window.attachedSheet == nil, NSApp.modalWindow == nil, !(window.firstResponder is NSTextView) else { return event }
        let cmd = event.modifierFlags.contains(.command)
        if cmd, event.keyCode == 126 { active.goUp(); return nil }
        if event.keyCode == 48 { activate(!activeLeft); window.makeFirstResponder(active.gridMode ? active.grid : active.table); return nil }
        if event.keyCode == 36 { active.openSelected(); return nil }
        if event.keyCode == 49, Prefs.bool("spacePreview") { preview(); return nil }
        if event.keyCode == 53 {
            if !active.search.stringValue.isEmpty {
                active.search.stringValue = ""
                active.reload()
                window.makeFirstResponder(active.gridMode ? active.grid : active.table)
                return nil
            }
            if job != nil { cancelJob(); return nil }
        }
        if Prefs.bool("functionKeys") {
            if event.keyCode == 120 { rename(); return nil }
            let keys: [UInt16: String] = [99: "keyF3", 118: "keyF4", 96: "keyF5", 97: "keyF6", 98: "keyF7", 100: "keyF8"]
            if let key = keys[event.keyCode] { dispatchAction(Prefs.string(key)); return nil }
        }
        if !cmd && !event.modifierFlags.contains(.control) && !event.modifierFlags.contains(.option),
           let chars = event.characters, !chars.isEmpty {
            let scalar = chars.unicodeScalars.first?.value ?? 0
            if scalar >= 32 && event.keyCode != 49 && event.keyCode != 36 && event.keyCode != 48 && event.keyCode != 51 && event.keyCode != 53 {
                active.search.stringValue += chars
                active.reload()
                window.makeFirstResponder(active.search)
                if let editor = window.fieldEditor(true, for: active.search) as? NSTextView {
                    editor.setSelectedRange(NSRange(location: active.search.stringValue.count, length: 0))
                }
                return nil
            }
        }
        return event
    }
    func dispatchAction(_ action: String) { switch action { case "preview": preview(); case "edit": editFile(); case "copy": copyFiles(); case "move": moveFiles(); case "folder": newFolder(); case "trash": trash(); case "rename": rename(); case "find": find(); default: break } }
    @objc func settings() {
        if settingsController == nil { settingsController = SettingsController(); settingsController?.changed = { [weak self] in self?.applySettings() }; settingsController?.checkForUpdates = { [weak self] in self?.checkUpdates() } }
        settingsController?.checkingUpdates = updateChecker.isChecking
        settingsController?.showWindow(nil); settingsController?.window?.makeKeyAndOrderFront(nil)
    }
    func applySettings() {
        let priorActive = activeLeft
        Prefs.applyAppearance()
        commandBar?.isHidden = !Prefs.bool("commandBar")
        for pane in [left, right] {
            pane.table.rowHeight = CGFloat(Prefs.int("rowHeight")); pane.showHidden = Prefs.bool("hiddenDefault")
            pane.table.tableColumn(withIdentifier: NSUserInterfaceItemIdentifier("ext"))?.isHidden = !Prefs.bool("extensions")
            pane.mode.selectedSegment = Prefs.int("defaultView"); pane.switchViewMode(); pane.reload()
        }
        let labels = ["preview": L("Önizle"), "edit": L("Düzenle"), "copy": L("Kopyala"), "move": L("Taşı"), "folder": L("Klasör"), "trash": L("Çöpe Taşı"), "rename": L("Adlandır"), "find": L("Ara")]
        for n in 3...8 { if let button = actionButtons[n] { let action = Prefs.string("keyF\(n)"); button.title = "F\(n) " + (labels[action] ?? action); button.action = #selector(functionButton(_:)); button.tag = n } }
        activate(priorActive)
    }
    var actionButtons: [Int: NSButton] = [:]
    @objc func functionButton(_ sender: NSButton) { dispatchAction(Prefs.string("keyF\(sender.tag)")) }
    func activate(_ value: Bool) { activeLeft = value; if !operations.busy { indicator.stringValue = value ? L("Sol panel etkin → Hedef: sağ panel") : L("Sağ panel etkin → Hedef: sol panel") } }
    func show(_ error: Error) { NSAlert(error: error).runModal() }
    func perform(_ action: () throws -> Void) { guard !operations.busy else { show(PanelError(message: L("Önce işlem kuyruğunu tamamlayın veya bekleyen işleri iptal edin."))); return }; do { try action(); refresh() } catch { show(error); refresh() } }
    func ask(_ title: String, initial: String, detail: String = "") -> String? {
        let a = NSAlert(); a.messageText = title; a.informativeText = detail; a.addButton(withTitle: L("Tamam")); a.addButton(withTitle: L("Vazgeç"))
        let f = NSTextField(frame: NSRect(x: 0, y: 0, width: 380, height: 24)); f.stringValue = initial; a.accessoryView = f; a.window.initialFirstResponder = f
        return a.runModal() == .alertFirstButtonReturn ? f.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }
    func startJob(_ title: String, queued: Bool = false, detail: String = "", work: @escaping FileJob.Work, complete: @escaping () -> Void = {}) {
        guard queued || !operations.busy else { show(PanelError(message: L("Bu işlem için önce kuyruğun tamamlanmasını bekleyin. Kopyalama ve taşıma işlerini kuyruğa ekleyebilirsiniz."))); return }
        operations.enqueue(title: title, detail: detail, reportFailure: !queued, work: work, complete: complete)
    }
    func refreshQueueStatus() {
        queueController?.refresh()
        let waiting = operations.waitingCount
        queueButton.title = waiting > 0 ? L("İşlem Kuyruğu ({0} bekleyen)", waiting) : L("İşlem Kuyruğu")
        progress.isHidden = operations.current == nil; cancel.isHidden = operations.current == nil
        if let current = operations.current {
            progress.doubleValue = current.progress
            indicator.stringValue = current.control.cancelled ? L("İptal bekleniyor…") : L("{0}: {1} · {2} bekleyen", current.title, current.progressText, waiting)
        } else if waiting > 0 {
            indicator.stringValue = L("Sıra duraklatıldı · {0} bekleyen işlem", waiting)
        } else if let last = operations.jobs.last, last.status == .failed {
            indicator.stringValue = L("İşlem tamamlanamadı: {0} · Ayrıntılar: İşlem Kuyruğu", last.errorText)
        } else { activate(activeLeft) }
    }
    @objc func showQueue() {
        if queueController == nil { queueController = QueueWindowController(queue: operations) }
        queueController?.refresh(); queueController?.showWindow(nil); queueController?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func cancelJob() { if let current = operations.current { operations.cancel(current.id) } }
    @objc func refresh() {
        for pane in [left, right] {
            for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? [] {
                if !pane.disk.itemArray.contains(where: { ($0.representedObject as? URL) == url }) { pane.disk.addItem(withTitle: url.lastPathComponent.isEmpty ? "Macintosh HD" : url.lastPathComponent); pane.disk.lastItem?.representedObject = url }
            }
            pane.reload()
        }
    }
    @objc func chooseFolder() { let p = NSOpenPanel(); p.canChooseDirectories = true; p.canChooseFiles = false; if p.runModal() == .OK, let u = p.url { active.navigate(u) } }
    @objc func swap() { let u = left.location; left.navigate(right.location); right.navigate(u) }
    @objc func hidden() { active.showHidden.toggle(); active.reload() }
    @objc func newTab() { active.newTab() }
    @objc func closeTab() { active.closeTab() }
    @objc func toggleLockTab() { active.toggleLockTab() }
    @objc func selectAll() { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.selectAll(nil) } else { active.select(active.entries.map(\.url)) } }
    @objc func clearSelection() { active.select([]) }
    @objc func invert() { let set = Set(active.selected); active.select(active.entries.filter { !set.contains($0.url) }.map(\.url)) }
    @objc func selectPattern() { if let pattern = ask(L("Dosya seçimi"), initial: "*.jpg", detail: L("* herhangi bir metin, ? tek karakter.")) { active.selectPattern(pattern) } }
    @objc func showSiteManager() {
        let sm = SiteManagerController()
        sm.onConnect = { [weak self] site in self?.connectRemote(site: site) }
        siteManagerController = sm
        sm.showWindow(nil)
        sm.window?.makeKeyAndOrderFront(nil)
    }
    @objc func showQuickConnect() {
        let qc = QuickConnectController()
        qc.onConnect = { [weak self] site in self?.connectRemote(site: site) }
        quickConnectController = qc
        qc.showWindow(nil)
        qc.window?.makeKeyAndOrderFront(nil)
    }
    func connectRemote(site: RemoteSite) {
        let session = RemoteSession(site: site)
        active.remoteSession = session
        active.reload()
    }
    @objc func disconnectRemote() {
        if active.remoteSession != nil {
            active.remoteSession = nil
            active.navigate(FileManager.default.homeDirectoryForCurrentUser)
        } else if other.remoteSession != nil {
            other.remoteSession = nil
            other.navigate(FileManager.default.homeDirectoryForCurrentUser)
        }
    }
    @objc func compareContent() {
        var fileA: URL?
        var fileB: URL?

        if active.selected.count == 2 {
            fileA = active.selected[0]
            fileB = active.selected[1]
        } else if let selA = active.selected.first, let selB = other.selected.first, selA != selB {
            fileA = selA
            fileB = selB
        } else if let selA = active.selected.first {
            fileA = selA
            let candidate = other.location.appendingPathComponent(selA.lastPathComponent)
            if FileManager.default.fileExists(atPath: candidate.path) {
                fileB = candidate
            } else {
                let panel = NSOpenPanel()
                panel.title = L("Karşılaştırılacak İkinci Dosyayı Seçin")
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                if panel.runModal() == .OK, let u = panel.url {
                    fileB = u
                }
            }
        } else {
            let panel = NSOpenPanel()
            panel.title = L("Karşılaştırılacak Dosyaları Seçin")
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = true
            if panel.runModal() == .OK {
                if panel.urls.count >= 2 {
                    fileA = panel.urls[0]
                    fileB = panel.urls[1]
                } else if panel.urls.count == 1 {
                    fileA = panel.urls[0]
                    let p2 = NSOpenPanel()
                    p2.title = L("Karşılaştırılacak İkinci Dosyayı Seçin")
                    p2.canChooseFiles = true
                    p2.canChooseDirectories = false
                    if p2.runModal() == .OK, let u2 = p2.url {
                        fileB = u2
                    }
                }
            }
        }

        guard let left = fileA, let right = fileB else { return }
        diffController = DiffWindowController(leftURL: left, rightURL: right)
        diffController?.showWindow(nil)
        diffController?.window?.makeKeyAndOrderFront(nil)
    }
    @objc func copyFiles() { transfer(active.selected, to: other.location, move: false) }
    @objc func moveFiles() { transfer(active.selected, to: other.location, move: true) }
    func transfer(_ originalURLs: [URL], to destination: URL, move: Bool) {
        var urls = originalURLs; guard !urls.isEmpty else { return }
        if let remote = active.remoteSession, other.remoteSession == nil {
            let sources = urls
            let targetDir = destination
            startJob(move ? L("Taşınıyor") : L("Kopyalanıyor"), queued: true, detail: remote.site.host, work: { state, progress in
                for (index, src) in sources.enumerated() {
                    if state.cancelled { throw PanelError(message: L("İşlem iptal edildi.")) }
                    let name = src.lastPathComponent
                    let remotePath = remote.currentPath.hasSuffix("/") ? "\(remote.currentPath)\(name)" : "\(remote.currentPath)/\(name)"
                    let targetFile = FileTasks.unique(targetDir.appendingPathComponent(name))
                    try remote.download(remotePath: remotePath, to: targetFile, control: state, progress: { _, _, _ in
                        progress(index, sources.count, name)
                    })
                    if move {
                        try? remote.remove(path: remotePath, isDirectory: false)
                    }
                    progress(index + 1, sources.count, name)
                }
            })
            return
        }
        if active.remoteSession == nil, let remote = other.remoteSession {
            let sources = urls
            let targetDir = remote.currentPath
            startJob(move ? L("Taşınıyor") : L("Kopyalanıyor"), queued: true, detail: remote.site.host, work: { state, progress in
                for (index, src) in sources.enumerated() {
                    if state.cancelled { throw PanelError(message: L("İşlem iptal edildi.")) }
                    try remote.upload(localURL: src, to: targetDir, control: state, progress: { _, _, _ in
                        progress(index, sources.count, src.lastPathComponent)
                    })
                    if move {
                        try? FileManager.default.removeItem(at: src)
                    }
                    progress(index + 1, sources.count, src.lastPathComponent)
                }
            })
            return
        }
        if active.remoteSession != nil && other.remoteSession != nil {
            show(PanelError(message: L("Uzak sunucudan uzak sunucuya doğrudan aktarım desteklenmiyor.")))
            return
        }
        if move, Prefs.bool("confirmMove") { let a = NSAlert(); a.messageText = L("{0} öğe taşınsın mı?", urls.count); a.informativeText = destination.path; a.addButton(withTitle: L("Taşı")); a.addButton(withTitle: L("Vazgeç")); guard a.runModal() == .alertFirstButtonReturn else { return } }
        if Prefs.string("collision") == "skip" { urls = urls.filter { !FileManager.default.fileExists(atPath: destination.appendingPathComponent($0.lastPathComponent).path) }; guard !urls.isEmpty else { indicator.stringValue = L("Hedefte bulunan dosyalar atlandı."); return } }
        let collisions = urls.filter { FileManager.default.fileExists(atPath: destination.appendingPathComponent($0.lastPathComponent).path) }
        if !collisions.isEmpty, Prefs.string("collision") == "ask" { let a = NSAlert(); a.messageText = L("{0} dosyanın adı hedefte kullanılıyor.", collisions.count); a.informativeText = L("Gelen dosyalara (2), (3)… eklenerek iki kopya da korunacak."); a.addButton(withTitle: L("İkisini de Koru")); a.addButton(withTitle: L("Vazgeç")); guard a.runModal() == .alertFirstButtonReturn else { return } }
        let skipExisting = Prefs.string("collision") == "skip"
        let sources = urls
        do { try FileTasks.validateTransfer(sources, to: destination) } catch { show(error); return }
        let detail = sources.map(\.path).joined(separator: "\n") + "\n→ " + destination.path
        startJob(move ? L("Taşınıyor") : L("Kopyalanıyor"), queued: true, detail: detail, work: { state, progress in
            let eligible = skipExisting ? sources.filter { !FileManager.default.fileExists(atPath: destination.appendingPathComponent($0.lastPathComponent).path) } : sources
            try FileTasks.transfer(eligible, to: destination, move: move, cancelled: { state.cancelled }, progress: progress)
        })
    }
    @objc func newFolder() {
        guard let name = ask(L("Yeni klasör"), initial: L("Yeni Klasör")) else { return }
        if let remote = active.remoteSession {
            let path = remote.currentPath.hasSuffix("/") ? "\(remote.currentPath)\(name)" : "\(remote.currentPath)/\(name)"
            do {
                try remote.makeDirectory(path: path)
                active.reload()
            } catch { show(error) }
            return
        }
        let directory = active.location; perform { try FileTasks.validateName(name); try FileManager.default.createDirectory(at: directory.appendingPathComponent(name), withIntermediateDirectories: false) }
    }
    @objc func newFile() { guard let name = ask(L("Yeni metin dosyası"), initial: L("Yeni Dosya.txt")) else { return }; let directory = active.location; perform { try FileTasks.validateName(name); let target = directory.appendingPathComponent(name); guard !FileManager.default.fileExists(atPath: target.path) else { throw PanelError(message: L("Bu adda bir dosya zaten var.")) }; try Data().write(to: target, options: .withoutOverwriting) } }
    @objc func rename() {
        guard let u = active.selected.first, let name = ask(L("Yeniden adlandır"), initial: u.lastPathComponent) else { return }
        if let remote = active.remoteSession {
            let oldPath = remote.currentPath.hasSuffix("/") ? "\(remote.currentPath)\(u.lastPathComponent)" : "\(remote.currentPath)/\(u.lastPathComponent)"
            let newPath = remote.currentPath.hasSuffix("/") ? "\(remote.currentPath)\(name)" : "\(remote.currentPath)/\(name)"
            do {
                try remote.rename(oldPath: oldPath, newPath: newPath)
                active.reload()
            } catch { show(error) }
            return
        }
        perform { try FileTasks.validateName(name); try FileManager.default.moveItem(at: u, to: u.deletingLastPathComponent().appendingPathComponent(name)) }
    }
    @objc func batchRename() {
        let urls = active.selected
        guard !urls.isEmpty else {
            show(PanelError(message: L("Yeniden adlandırmak için dosya seçin.")))
            return
        }
        let mr = MultiRenameWindowController(urls: urls)
        mr.onApplied = { [weak self] in
            self?.refresh()
        }
        multiRenameController = mr
        mr.showWindow(nil)
        mr.window?.makeKeyAndOrderFront(nil)
    }
    @objc func splitFile() {
        guard active.selected.count == 1, let file = active.selected.first else {
            show(PanelError(message: L("Dosyayı bölmek için tek bir dosya seçin.")))
            return
        }
        let targetDir = other.location
        let splitWin = SplitWindowController(sourceURL: file, destinationDir: targetDir)
        splitWin.onStartSplit = { [weak self] source, dest, chunkSize, makeCRC in
            guard let self else { return }
            self.startJob(L("Bölünüyor: {0}", source.lastPathComponent), queued: true) { state, progress in
                _ = try FileSplitter.split(source: source, destinationDir: dest, chunkSize: chunkSize, generateCRC: makeCRC, control: state) { done, total, name in
                    progress(Int(done), Int(total), name)
                }
            }
        }
        splitController = splitWin
        splitWin.showWindow(nil)
        splitWin.window?.makeKeyAndOrderFront(nil)
    }
    @objc func combineFiles() {
        guard active.selected.count == 1, let file = active.selected.first else {
            show(PanelError(message: L("Birleştirmek için .001 uzantılı bir parça dosyası seçin.")))
            return
        }
        let detected = FileSplitter.detectParts(firstPart: file)
        guard !detected.parts.isEmpty else {
            show(PanelError(message: L("Birleştirmek için .001 uzantılı bir parça dosyası seçin.")))
            return
        }
        let targetDir = other.location
        let combineWin = CombineWindowController(parts: detected.parts, originalName: detected.originalName, destinationDir: targetDir, crcURL: detected.crcURL)
        combineWin.onStartCombine = { [weak self] parts, outName, dest, crcURL, verify in
            guard let self else { return }
            self.startJob(L("Birleştiriliyor: {0}", outName), queued: true) { state, progress in
                _ = try FileSplitter.combine(parts: parts, originalName: outName, destinationDir: dest, crcURL: crcURL, verifyCRC: verify, control: state) { done, total, name in
                    progress(Int(done), Int(total), name)
                }
            }
        }
        combineController = combineWin
        combineWin.showWindow(nil)
        combineWin.window?.makeKeyAndOrderFront(nil)
    }
    @objc func trash() {
        let urls = active.selected; guard !urls.isEmpty else { return }
        if let remote = active.remoteSession {
            if Prefs.bool("confirmTrash") {
                let a = NSAlert()
                a.messageText = L("Uzak sunucudaki seçili {0} öğe kalıcı olarak silinecek. Emin misiniz?", urls.count)
                a.addButton(withTitle: L("Sil"))
                a.addButton(withTitle: L("Vazgeç"))
                guard a.runModal() == .alertFirstButtonReturn else { return }
            }
            startJob(L("Çöpe taşınıyor"), work: { state, progress in
                for (i, u) in urls.enumerated() {
                    if state.cancelled { break }
                    let name = u.lastPathComponent
                    let p = remote.currentPath.hasSuffix("/") ? "\(remote.currentPath)\(name)" : "\(remote.currentPath)/\(name)"
                    let isDir = self.active.entries.first(where: { $0.url == u })?.directory ?? false
                    try? remote.remove(path: p, isDirectory: isDir)
                    progress(i + 1, urls.count, name)
                }
            })
            return
        }
        let a = NSAlert(); a.messageText = L("{0} öğe Çöp Kutusu’na taşınsın mı?", urls.count); a.informativeText = L("Çöp Kutusu’ndan geri alabilirsiniz."); a.addButton(withTitle: L("Çöpe Taşı")); a.addButton(withTitle: L("Vazgeç"))
        if !Prefs.bool("confirmTrash") || a.runModal() == .alertFirstButtonReturn { startJob(L("Çöpe taşınıyor"), work: { state, progress in for (i, u) in urls.enumerated() { if state.cancelled { break }; try FileManager.default.trashItem(at: u, resultingItemURL: nil); progress(i + 1, urls.count, u.lastPathComponent) } }) }
    }
    @objc func preview() { previewURLs = active.selected; guard !previewURLs.isEmpty, let panel = QLPreviewPanel.shared() else { return }; panel.dataSource = self; panel.reloadData(); panel.makeKeyAndOrderFront(nil) }
    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int { previewURLs.count }
    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! { previewURLs[index] as NSURL }
    @objc func editFile() { guard let u = active.selected.first else { return }; NSWorkspace.shared.open([u], withApplicationAt: URL(fileURLWithPath: Prefs.string("editor")), configuration: NSWorkspace.OpenConfiguration()) }
    @objc func reveal() { NSWorkspace.shared.activateFileViewerSelecting(active.selected.isEmpty ? [active.location] : active.selected) }
    var clipboardMove = false
    var clipboardVersion = -1
    @objc func openItem() { active.openSelected() }
    @objc func copyClipboard() { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.copy(nil); return }; clipboardMove = false; NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(active.selected.map { $0 as NSURL }) }
    @objc func cutClipboard() { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.cut(nil); return }; copyClipboard(); clipboardMove = true; clipboardVersion = NSPasteboard.general.changeCount }
    @objc func pasteClipboard() { if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.paste(nil); return }; let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []; transfer(urls, to: active.location, move: clipboardMove && clipboardVersion == NSPasteboard.general.changeCount); clipboardMove = false }
    @objc func copyPath() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString((active.selected.isEmpty ? [active.location] : active.selected).map(\.path).joined(separator: "\n"), forType: .string) }
    @objc func terminal() { NSWorkspace.shared.open([active.location], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration()) }
    @objc func info() { guard let u = active.selected.first else { return }; do { let a = try FileManager.default.attributesOfItem(atPath: u.path); let alert = NSAlert(); alert.messageText = u.lastPathComponent; alert.informativeText = L("Yol: {0}\nBoyut: {1} bayt\nDeğiştirilme: {2}\nİzinler: {3}", u.path, a[.size] ?? 0, a[.modificationDate] ?? "—", String((a[.posixPermissions] as? NSNumber)?.intValue ?? 0, radix: 8)); alert.runModal() } catch { show(error) } }
    @objc func sync() {
        let sw = SyncWindowController(leftDir: left.location, rightDir: right.location)
        sw.onStartSync = { [weak self] actionableItems in
            guard let self else { return }
            self.startJob(L("Eşitleniyor"), queued: true) { state, progress in
                try SyncEngine.executeSync(items: actionableItems, control: state) { done, total, name in
                    progress(done, total, name)
                }
            }
        }
        syncWindowController = sw
        sw.showWindow(nil)
        sw.window?.makeKeyAndOrderFront(nil)
    }
    @objc func compare() {
        let a = left.entries.filter { !$0.directory }, b = right.entries.filter { !$0.directory }
        let l = Dictionary(uniqueKeysWithValues: a.map { ($0.url.lastPathComponent, $0) }), r = Dictionary(uniqueKeysWithValues: b.map { ($0.url.lastPathComponent, $0) })
        left.select(a.filter { e in guard let x = r[e.url.lastPathComponent] else { return true }; return x.size != e.size || abs(x.date.timeIntervalSince(e.date)) > 2 }.map(\.url))
        right.select(b.filter { e in guard let x = l[e.url.lastPathComponent] else { return true }; return x.size != e.size || abs(x.date.timeIntervalSince(e.date)) > 2 }.map(\.url))
        indicator.stringValue = L("Karşılaştırma: adı, boyutu veya tarihi farklı dosyalar seçildi (içerik karşılaştırılmaz).")
    }
    @objc func find() {
        guard let query = ask(L("Alt klasörlerde dosya ara"), initial: "", detail: L("Dosya adının bir bölümünü yazın. Sonuçlardan birini seçerek konumuna gidebilirsiniz.")), !query.isEmpty else { return }
        let directory = active.location; let pane = active; var results: [URL] = []
        startJob(L("Aranıyor"), work: { state, progress in
            let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey], options: Prefs.bool("searchHidden") ? [.skipsPackageDescendants] : [.skipsHiddenFiles, .skipsPackageDescendants])
            var count = 0
            while let u = enumerator?.nextObject() as? URL { if state.cancelled { throw PanelError(message: L("Arama iptal edildi.")) }; count += 1; if u.lastPathComponent.localizedCaseInsensitiveContains(query) { results.append(u) }; if results.count == Prefs.int("searchLimit") { break }; if count % 200 == 0 { progress(0, 1, L("{0} öğe tarandı", count)) } }
        }, complete: {
            let a = NSAlert(); a.messageText = L("{0} sonuç (en fazla {1})", results.count, Prefs.int("searchLimit"))
            let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 650, height: 28)); for u in results { popup.addItem(withTitle: String(u.path.dropFirst(directory.path.count + 1))) }; a.accessoryView = popup
            a.addButton(withTitle: L("Konumuna Git")); a.addButton(withTitle: L("Kapat"))
            if a.runModal() == .alertFirstButtonReturn, results.indices.contains(popup.indexOfSelectedItem) { let u = results[popup.indexOfSelectedItem]; pane.navigate(u.deletingLastPathComponent()); pane.select([u]) }
        })
    }
    func execute(_ executable: String, _ args: [String], directory: URL, state: JobState) throws -> String {
        if state.cancelled { throw PanelError(message: L("İşlem iptal edildi.")) }
        let p = Process(); p.executableURL = URL(fileURLWithPath: executable); p.arguments = args; p.currentDirectoryURL = directory
        let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: output.path, contents: nil); let handle = try FileHandle(forWritingTo: output); defer { try? handle.close(); try? FileManager.default.removeItem(at: output) }
        p.standardOutput = handle; p.standardError = handle; p.standardInput = FileHandle.nullDevice
        try p.run(); DispatchQueue.main.async { self.process = p; if state.cancelled, p.isRunning { p.terminate() } }; p.waitUntilExit()
        let text = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        if state.cancelled { throw PanelError(message: L("İşlem iptal edildi.")) }
        guard p.terminationStatus == 0 else { throw PanelError(message: text.isEmpty ? L("İşlem tamamlanamadı (çıkış kodu {0}).", p.terminationStatus) : String(text.prefix(2000))) }; return text
    }
    @objc func pack() { createArchive(format: Prefs.string("archiveFormat")) }
    @objc func packZIP() { createArchive(format: "zip") }
    @objc func pack7z() { createArchive(format: "7zip") }
    func createArchive(format: String) {
        let urls = active.selected; let directory = active.location; guard !urls.isEmpty else { return }; let ext = format == "zip" ? "zip" : "7z"
        guard let name = ask(L("{0} arşivi oluştur", ext.uppercased()), initial: L("Arşiv.{0}", ext)) else { return }
        do { try FileTasks.validateName(name) } catch { show(error); return }
        let target = directory.appendingPathComponent(name.hasSuffix(".\(ext)") ? name : name + ".\(ext)")
        guard !FileManager.default.fileExists(atPath: target.path) else { show(PanelError(message: L("Bu adda bir dosya zaten var."))); return }
        let staging = directory.appendingPathComponent(".panelmac-archive-" + UUID().uuidString)
        startJob(L("Arşiv oluşturuluyor"), work: { state, progress in
            defer { try? FileManager.default.removeItem(at: staging) }
            _ = try self.execute("/usr/bin/bsdtar", ["--format", format, "-cf", staging.path, "--"] + urls.map(\.lastPathComponent), directory: directory, state: state)
            try FileManager.default.moveItem(at: staging, to: target); progress(1, 1, target.lastPathComponent)
        })
    }
    @objc func browse() { guard let u = active.selected.first else { return }; browseArchive(u, pane: active) }
    func browseArchive(_ archive: URL, pane: FilePane) {
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("TotalCommand-Archive-" + UUID().uuidString)
        extract(archive, to: target) { self.temporary.append(target); pane.archiveRoot = target; pane.archiveSource = archive; pane.navigate(target); self.indicator.stringValue = L("Arşiv geçici klasörde açıldı. Değişiklikler özgün arşive yazılmaz.") }
    }
    @objc func unpack() { guard let u = active.selected.first else { return }; let target = FileTasks.unique(other.location.appendingPathComponent(u.deletingPathExtension().lastPathComponent)); extract(u, to: target) }
    func extract(_ archive: URL, to target: URL, complete: @escaping () -> Void = {}) {
        guard ["zip", "7z", "rar", "tar", "gz", "bz2", "xz", "tgz"].contains(archive.pathExtension.lowercased()) else { show(PanelError(message: L("Desteklenen arşivler: ZIP, 7z, RAR, TAR, GZ, BZ2, XZ."))); return }
        startJob(L("Arşiv açılıyor"), work: { state, progress in
            let listing = try self.execute("/usr/bin/bsdtar", ["-tf", archive.path], directory: archive.deletingLastPathComponent(), state: state); try FileTasks.validateArchivePaths(listing)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            do { _ = try self.execute("/usr/bin/bsdtar", ["-xf", archive.path, "-C", target.path, "--no-same-owner", "--no-same-permissions"], directory: target, state: state) }
            catch { try? FileManager.default.removeItem(at: target); throw error }; progress(1, 1, archive.lastPathComponent)
        }, complete: complete)
    }
    @objc func connectServer() {
        guard let text = ask(L("Ağ sunucusuna bağlan"), initial: "smb://", detail: L("SMB veya AFP adresi girin. Bağlantı Finder’da açılır. Bağlandıktan sonra Yenile’ye basarak diski panel listesinden seçebilirsiniz.")), let url = URL(string: text), ["smb", "afp"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return }
        NSWorkspace.shared.open(url)
    }
    @objc func runCommand() {
        let text = command.stringValue.trimmingCharacters(in: .whitespacesAndNewlines); guard !text.isEmpty else { return }; let directory = active.location; var output = ""
        startJob(L("Komut çalışıyor"), work: { state, progress in output = try self.execute("/bin/zsh", ["-c", text], directory: directory, state: state); progress(1, 1, L("Bitti")) }, complete: {
            let log = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 480), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false); log.title = L("Komut çıktısı — ") + directory.lastPathComponent; log.isReleasedWhenClosed = false
            let view = NSTextView(); view.isEditable = false; view.font = .monospacedSystemFont(ofSize: 12, weight: .regular); view.string = "$ " + text + "\n\n" + (output.isEmpty ? L("Komut çıktı vermeden tamamlandı.") : output); view.textContainerInset = NSSize(width: 12, height: 12)
            let scroll = NSScrollView(frame: log.contentView!.bounds); scroll.autoresizingMask = [.width, .height]; scroll.documentView = view; scroll.hasVerticalScroller = true; view.isVerticallyResizable = true; view.isHorizontallyResizable = false; view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true; log.contentView?.addSubview(scroll); self.logWindows.removeAll { !$0.isVisible }; self.logWindows.append(log); log.center(); log.makeKeyAndOrderFront(nil)
        })
    }
    @objc func addBookmark() { var paths = UserDefaults.standard.stringArray(forKey: "bookmarks") ?? []; if !paths.contains(active.location.path) { paths.append(active.location.path); UserDefaults.standard.set(paths, forKey: "bookmarks") }; indicator.stringValue = L("Favorilere eklendi: ") + active.location.lastPathComponent }
    @objc func bookmarks() { let paths = UserDefaults.standard.stringArray(forKey: "bookmarks") ?? []; guard !paths.isEmpty else { show(PanelError(message: L("Henüz favori yok. Command+D ile klasör ekleyin."))); return }; let a = NSAlert(); a.messageText = L("Favori klasörler"); let popup = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 550, height: 28)); popup.addItems(withTitles: paths); a.accessoryView = popup; a.addButton(withTitle: L("Git")); a.addButton(withTitle: L("Vazgeç")); if a.runModal() == .alertFirstButtonReturn { active.navigate(URL(fileURLWithPath: paths[popup.indexOfSelectedItem])) } }
    @objc func about() { let a = NSAlert(); a.messageText = "Total Command \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.1")"; a.informativeText = L("macOS için çift panelli dosya yöneticisi.\n© 2026 Ferdi Sahin · GNU GPL sürüm 3\nBu özgür yazılımı GPLv3 koşullarıyla dağıtabilir ve değiştirebilirsiniz. Hiçbir garanti verilmez.\nTotal Commander’dan esinlenen bağımsız uygulama."); a.addButton(withTitle: L("Tamam")); a.addButton(withTitle: L("Lisansı Gör")); a.addButton(withTitle: L("Kaynak Kod")); let result = a.runModal(); if result == .alertSecondButtonReturn { self.showLicense() } else if result == .alertThirdButtonReturn { NSWorkspace.shared.open(URL(string: "https://github.com/ferdisahin/total-command")!) } }
    @objc func checkUpdates() { performUpdateCheck(manual: true) }
    func checkAutomaticUpdates() {
        guard NSApp.isActive, !operations.busy, NSApp.modalWindow == nil, window.attachedSheet == nil else { return }
        if let release = pendingUpdate {
            pendingUpdate = nil
            if (pendingUpdateIsManual || Prefs.int("updateInterval") != 0) && (!release.isPreview || Prefs.bool("updatePreviews")) { presentUpdate(release) }
            return
        }
        guard ReleaseFeed.isDue(interval: Prefs.int("updateInterval"), lastAttempt: Prefs.store.object(forKey: "updateLastAttempt") as? Date) else { return }
        performUpdateCheck(manual: false)
    }
    func performUpdateCheck(manual: Bool) {
        if updateChecker.isChecking { manualUpdateRequested = manualUpdateRequested || manual; return }
        manualUpdateRequested = manual
        settingsController?.checkingUpdates = true
        settingsController?.updateMessage = L("GitHub’da yeni sürüm aranıyor…")
        Prefs.set("updateLastAttempt", Date())
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.2"
        updateChecker.check(current: current, includePreviews: Prefs.bool("updatePreviews")) { [weak self] result in
            guard let self else { return }
            let requested = self.manualUpdateRequested; self.manualUpdateRequested = false
            self.settingsController?.checkingUpdates = false
            switch result {
            case .success(let release):
                self.settingsController?.updateMessage = release.map { L("Yeni sürüm: {0}", $0.tag) } ?? L("Seçili kanalda {0} sürümünden daha yeni bir sürüm yok.", current)
                if let release {
                    if (requested || Prefs.int("updateInterval") != 0) && (!release.isPreview || Prefs.bool("updatePreviews")) && (requested || Prefs.string("updateNotifiedTag") != release.tag) { self.pendingUpdate = release; self.pendingUpdateIsManual = requested }
                } else if requested {
                    let alert = NSAlert(); alert.messageText = L("Yeni sürüm bulunamadı"); alert.informativeText = L("Yüklü sürüm: {0}.\nÖnizleme sürümlerini Ayarlar → Güncellemeler’den dahil edebilirsiniz.", current); alert.runModal()
                }
            case .failure(let error):
                self.settingsController?.updateMessage = L("Kontrol tamamlanamadı. ") + error.localizedDescription
                if requested { self.show(PanelError(message: L("Güncelleme kontrolü tamamlanamadı.\n") + error.localizedDescription)) }
            }
            if (requested || NSApp.isActive), !self.operations.busy, NSApp.modalWindow == nil, self.window.attachedSheet == nil, let release = self.pendingUpdate { self.pendingUpdate = nil; self.presentUpdate(release) }
        }
    }
    func presentUpdate(_ release: AppRelease) {
        Prefs.set("updateNotifiedTag", release.tag)
        let alert = NSAlert(); alert.messageText = L("Total Command {0} hazır", release.tag)
        alert.informativeText = L("{0}Sürüm notlarını ve imzalı indirmeleri GitHub’da açabilirsiniz. Homebrew ile kurduysanız brew update ve brew upgrade --cask total-command komutlarını kullanabilirsiniz.", release.isPreview ? L("Bu bir önizleme sürümüdür.\n") : "")
        alert.addButton(withTitle: L("İndirme Sayfasını Aç")); alert.addButton(withTitle: L("Daha Sonra"))
        if alert.runModal() == .alertFirstButtonReturn { NSWorkspace.shared.open(release.pageURL) }
    }
    func showLicense() {
        guard let url = Bundle.main.url(forResource: "LICENSE", withExtension: nil), let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let log = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 560), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false); log.title = "Total Command — GNU GPLv3"; log.isReleasedWhenClosed = false
        let view = NSTextView(); view.isEditable = false; view.font = .monospacedSystemFont(ofSize: 12, weight: .regular); view.string = text; view.textContainerInset = NSSize(width: 16, height: 16); view.isVerticallyResizable = true; view.autoresizingMask = [.width]; view.textContainer?.widthTracksTextView = true
        let scroll = NSScrollView(frame: log.contentView!.bounds); scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.documentView = view; log.contentView?.addSubview(scroll); logWindows.removeAll { !$0.isVisible }; logWindows.append(log); log.center(); log.makeKeyAndOrderFront(nil)
    }
    @objc func quit() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { if operations.busy { let a = NSAlert(); a.messageText = L("Önce çalışan ve bekleyen işlemleri tamamlayın veya İşlem Kuyruğu’ndan iptal edin."); a.runModal(); return .terminateCancel }; return .terminateNow }
    func applicationWillTerminate(_ notification: Notification) { updateTimer?.invalidate(); left.save("leftTabs"); right.save("rightTabs"); for u in temporary { try? FileManager.default.removeItem(at: u) } }
    func windowShouldClose(_ sender: NSWindow) -> Bool { !operations.busy }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
let app = NSApplication.shared
Prefs.register()
Prefs.applyAppearance()
let delegate = AppDelegate()
app.delegate = delegate
app.run()
