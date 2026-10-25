import AppKit
import Observation
import SwiftUI

@Observable
final class PanelModel {
    enum Mode { case hold, interactive }
    enum Tab { case app, system }
    enum Direction { case up, down, left, right }

    var mode: Mode = .hold
    var tab: Tab = .app
    var appSheet: Sheet?
    var systemSheet: Sheet?
    var isLoading = false
    var trusted = true
    var appeared = false
    var focusToken = 0
    var toast: String?

    var query = "" {
        didSet { if query != oldValue { refilter(); selectFirstMatch() } }
    }
    var selectedID: String?
    var hoveredID: String?

    /// Layout of the unfiltered sheet; it decides the panel size.
    private(set) var baseLayout: SheetLayout = .empty
    /// What is on screen (filtered by the search query).
    private(set) var layout: SheetLayout = .empty

    var maxSize = CGSize(width: 1600, height: 1000)

    // Wired up by the controllers.
    @ObservationIgnored var onRun: ((Shortcut) -> Void)?
    @ObservationIgnored var onClose: (() -> Void)?
    @ObservationIgnored var onOpenSettings: (() -> Void)?
    @ObservationIgnored var onExportPDF: (() -> Void)?
    @ObservationIgnored var onRequestPermission: (() -> Void)?
    @ObservationIgnored var onSizeChange: ((CGSize) -> Void)?

    var prefs: Preferences { .shared }

    var sheet: Sheet? { tab == .app ? appSheet : systemSheet }

    var hotKeyStroke: KeyStroke? {
        prefs.hotKeyEnabled ? prefs.hotKey.stroke : nil
    }

    // MARK: Building

    func rebuild() {
        let groups = visibleGroups(sheet?.groups ?? [])
        let new = SheetLayout.make(groups: groups, maxSize: maxSize)
        let sizeChanged = new.panelSize != baseLayout.panelSize
        baseLayout = new
        refilter()
        if sizeChanged { onSizeChange?(new.panelSize) }
    }

    private func refilter() {
        let tokens = Search.tokens(query)
        guard !tokens.isEmpty else {
            layout = baseLayout
            return
        }
        let groups = visibleGroups(sheet?.groups ?? []).compactMap { g -> ShortcutGroup? in
            let items = g.items.filter { Search.matches($0, tokens) }
            return items.isEmpty ? nil : g.with(items: items)
        }
        layout = SheetLayout.reflow(groups: groups, columns: max(1, baseLayout.columns.count),
                                    panelSize: baseLayout.panelSize, columnWidth: baseLayout.columnWidth)
    }

    private func visibleGroups(_ groups: [ShortcutGroup]) -> [ShortcutGroup] {
        groups.compactMap { g in
            if g.isCurated, !prefs.showTips, tab == .app { return nil }
            let items = prefs.showDisabled ? g.items : g.items.filter(\.enabled)
            return items.isEmpty ? nil : g.with(items: items)
        }
    }

    func setAppSheet(_ sheet: Sheet?) {
        guard sheet != appSheet else { return }
        appSheet = sheet
        if tab == .app { rebuild() }
    }

    func switchTab(_ new: Tab? = nil) {
        let target = new ?? (tab == .app ? .system : .app)
        guard target != tab else { return }
        if target == .system, systemSheet == nil { systemSheet = TipsLibrary.shared.systemSheet() }
        withAnimation(.snappy(duration: 0.22)) { tab = target }
        selectedID = nil
        rebuild()
        selectFirstMatch()
    }

    func reset() {
        query = ""
        selectedID = nil
        hoveredID = nil
        toast = nil
    }

    // MARK: Keyboard navigation

    private func selectFirstMatch() {
        if query.isEmpty { selectedID = nil; return }
        selectedID = layout.orderedItems.first?.id
    }

    func move(_ direction: Direction) {
        let columns = layout.columns.map { $0.flatMap(\.items) }
        let flat = columns.flatMap { $0 }
        guard !flat.isEmpty else { return }
        guard let current = selectedID,
              let col = columns.firstIndex(where: { $0.contains { $0.id == current } }),
              let row = columns[col].firstIndex(where: { $0.id == current }) else {
            selectedID = flat.first?.id
            return
        }
        switch direction {
        case .down:
            if let i = flat.firstIndex(where: { $0.id == current }), i + 1 < flat.count { selectedID = flat[i + 1].id }
        case .up:
            if let i = flat.firstIndex(where: { $0.id == current }), i > 0 { selectedID = flat[i - 1].id }
        case .left, .right:
            var target = direction == .left ? col - 1 : col + 1
            while target >= 0, target < columns.count, columns[target].isEmpty {
                target += direction == .left ? -1 : 1
            }
            guard target >= 0, target < columns.count else { return }
            // Keep roughly the same height on screen.
            let y = offset(of: current, inColumn: col)
            let candidates = columns[target]
            let best = candidates.min { abs(offset(of: $0.id, inColumn: target) - y) < abs(offset(of: $1.id, inColumn: target) - y) }
            selectedID = best?.id ?? candidates[min(row, candidates.count - 1)].id
        }
    }

    private func offset(of id: String, inColumn col: Int) -> CGFloat {
        var y: CGFloat = 0
        for chunk in layout.columns[col] {
            y += Metrics.groupHeader
            for item in chunk.items {
                if item.id == id { return y }
                y += Metrics.rowHeight
            }
            y += Metrics.groupGap
        }
        return y
    }

    func runSelected() {
        guard let id = selectedID, let item = layout.orderedItems.first(where: { $0.id == id }) else { return }
        run(item)
    }

    func run(_ item: Shortcut) {
        guard item.isRunnable else {
            NSSound.beep()
            return
        }
        onRun?(item)
    }

    func showToast(_ text: String) {
        withAnimation(.snappy) { toast = text }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard self?.toast == text else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    // MARK: Export

    func markdown() -> String {
        guard let sheet else { return "" }
        var out = "# \(sheet.name) kısayolları\n\n"
        for g in visibleGroups(sheet.groups) {
            out += "## \(g.title)\n\n| Komut | Kısayol |\n| --- | --- |\n"
            for item in g.items {
                let title = [item.path, item.title].compactMap { $0 }.joined(separator: " › ")
                out += "| \(title.replacingOccurrences(of: "|", with: "\\|")) | `\(item.keyText)` |\n"
            }
            out += "\n"
        }
        out += "_Kestirme ile oluşturuldu._\n"
        return out
    }

    func exportGroups() -> [ShortcutGroup] { visibleGroups(sheet?.groups ?? []) }
}
