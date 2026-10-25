import AppKit

enum Metrics {
    static let rowHeight: CGFloat = 27
    static let groupHeader: CGFloat = 30
    static let groupGap: CGFloat = 22
    static let columnWidth: CGFloat = 304
    static let maxColumnWidth: CGFloat = 390
    static let columnGap: CGFloat = 34
    static let padH: CGFloat = 28
    static let padTop: CGFloat = 18
    static let padBottom: CGFloat = 22
    static let header: CGFloat = 82
    static let footer: CGFloat = 42
    static let minWidth: CGFloat = 760
    static let cornerRadius: CGFloat = 26
    static var chrome: CGFloat { header + footer }
}

struct LayoutChunk: Identifiable, Equatable {
    let id: String
    let group: ShortcutGroup
    let items: [Shortcut]
    let continued: Bool

    var height: CGFloat { Metrics.groupHeader + CGFloat(items.count) * Metrics.rowHeight }
}

struct SheetLayout: Equatable {
    var columns: [[LayoutChunk]]
    var columnWidth: CGFloat
    var panelSize: CGSize
    var contentHeight: CGFloat

    var isEmpty: Bool { columns.allSatisfy { $0.isEmpty } }

    /// Items in reading order (down each column, then across) for keyboard navigation.
    var orderedItems: [Shortcut] { columns.flatMap { $0.flatMap(\.items) } }

    static let empty = SheetLayout(columns: [], columnWidth: Metrics.columnWidth,
                                   panelSize: CGSize(width: Metrics.minWidth, height: Metrics.chrome + 280),
                                   contentHeight: 0)

    /// Picks a column count that keeps the panel on screen and close to a pleasant aspect ratio.
    static func make(groups: [ShortcutGroup], maxSize: CGSize, targetAspect: CGFloat = 1.65) -> SheetLayout {
        let maxContent = maxSize.height - Metrics.chrome - Metrics.padTop - Metrics.padBottom
        let chunks = split(groups, maxContentHeight: maxContent)
        guard !chunks.isEmpty else { return .empty }

        let maxCols = max(1, min(6, Int((maxSize.width - 2 * Metrics.padH + Metrics.columnGap)
                                         / (Metrics.columnWidth + Metrics.columnGap))))
        var best: (score: CGFloat, cols: [[LayoutChunk]], height: CGFloat)?
        for k in 1...min(maxCols, chunks.count) {
            let (cols, height) = partition(chunks, into: k)
            guard height <= maxContent else { continue }
            let w = width(columns: cols.count, columnWidth: Metrics.columnWidth)
            let h = height + Metrics.chrome + Metrics.padTop + Metrics.padBottom
            let score = abs(log(w / h) - log(targetAspect))
            if best == nil || score < best!.score - 0.02 { best = (score, cols, height) }
        }
        if best == nil {
            let (cols, height) = partition(chunks, into: maxCols)
            best = (0, cols, height)
        }
        return finish(best!.cols, contentHeight: best!.height, maxSize: maxSize)
    }

    /// Re-flows (filtered) groups into a fixed number of columns inside an existing panel size.
    static func reflow(groups: [ShortcutGroup], columns k: Int, panelSize: CGSize, columnWidth: CGFloat) -> SheetLayout {
        let maxContent = panelSize.height - Metrics.chrome - Metrics.padTop - Metrics.padBottom
        let chunks = split(groups, maxContentHeight: max(maxContent, 200))
        guard !chunks.isEmpty else {
            return SheetLayout(columns: [], columnWidth: columnWidth, panelSize: panelSize, contentHeight: 0)
        }
        var (cols, height) = partition(chunks, into: max(1, k))
        while cols.count < k { cols.append([]) }
        return SheetLayout(columns: cols, columnWidth: columnWidth, panelSize: panelSize, contentHeight: height)
    }

    private static func finish(_ cols: [[LayoutChunk]], contentHeight: CGFloat, maxSize: CGSize) -> SheetLayout {
        var colWidth = Metrics.columnWidth
        var w = width(columns: cols.count, columnWidth: colWidth)
        if w < Metrics.minWidth {
            let free = Metrics.minWidth - 2 * Metrics.padH - CGFloat(cols.count - 1) * Metrics.columnGap
            colWidth = min(Metrics.maxColumnWidth, free / CGFloat(cols.count))
            w = Metrics.minWidth
        }
        let visible = min(contentHeight, maxSize.height - Metrics.chrome - Metrics.padTop - Metrics.padBottom)
        let h = Metrics.chrome + Metrics.padTop + Metrics.padBottom + max(visible, 160)
        return SheetLayout(columns: cols, columnWidth: colWidth, panelSize: CGSize(width: w, height: h),
                           contentHeight: contentHeight)
    }

    private static func width(columns: Int, columnWidth: CGFloat) -> CGFloat {
        CGFloat(columns) * columnWidth + CGFloat(max(0, columns - 1)) * Metrics.columnGap + 2 * Metrics.padH
    }

    /// Long menus are cut into pieces that each fit in one column.
    private static func split(_ groups: [ShortcutGroup], maxContentHeight: CGFloat) -> [LayoutChunk] {
        let maxRows = max(6, Int((maxContentHeight - Metrics.groupHeader) / Metrics.rowHeight))
        var out: [LayoutChunk] = []
        for g in groups where !g.items.isEmpty {
            if g.items.count <= maxRows {
                out.append(LayoutChunk(id: g.id, group: g, items: g.items, continued: false))
                continue
            }
            // Even pieces read better than one full column and a short tail.
            let pieces = Int(ceil(Double(g.items.count) / Double(maxRows)))
            let size = Int(ceil(Double(g.items.count) / Double(pieces)))
            for (n, start) in stride(from: 0, to: g.items.count, by: size).enumerated() {
                let slice = Array(g.items[start..<min(start + size, g.items.count)])
                out.append(LayoutChunk(id: "\(g.id)#\(n)", group: g, items: slice, continued: n > 0))
            }
        }
        return out
    }

    /// Splits chunks, in order, into at most `k` columns minimising the tallest column.
    private static func partition(_ chunks: [LayoutChunk], into k: Int) -> ([[LayoutChunk]], CGFloat) {
        let heights = chunks.map(\.height)
        var lo = heights.max() ?? 0
        var hi = heights.reduce(0, +) + Metrics.groupGap * CGFloat(max(0, heights.count - 1))
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if greedy(heights, limit: mid).count <= k { hi = mid } else { lo = mid }
        }
        let limit = greedy(heights, limit: lo).count <= k ? lo : hi
        let indexCols = greedy(heights, limit: limit)
        let cols = indexCols.map { $0.map { chunks[$0] } }
        let tallest = indexCols.map { col in
            col.reduce(CGFloat(0)) { $0 + heights[$1] } + Metrics.groupGap * CGFloat(max(0, col.count - 1))
        }.max() ?? 0
        return (cols, tallest)
    }

    private static func greedy(_ heights: [CGFloat], limit: CGFloat) -> [[Int]] {
        var cols: [[Int]] = [[]]
        var current: CGFloat = 0
        for (i, h) in heights.enumerated() {
            if cols[cols.count - 1].isEmpty {
                cols[cols.count - 1].append(i)
                current = h
            } else if current + Metrics.groupGap + h <= limit {
                cols[cols.count - 1].append(i)
                current += Metrics.groupGap + h
            } else {
                cols.append([i])
                current = h
            }
        }
        return cols
    }
}
