import AppKit
import SwiftUI

/// Offscreen rendering: PDF export and PNG previews of the panel.
enum Exporter {
    struct ExportError: LocalizedError {
        var errorDescription: String? { "PDF oluşturulamadı." }
    }

    @MainActor
    static func writePDF(sheet: Sheet, groups: [ShortcutGroup], to url: URL) throws {
        let layout = SheetLayout.make(groups: groups, maxSize: CGSize(width: 1700, height: 100_000), targetAspect: 1.414)
        let view = PrintSheet(sheet: sheet, layout: layout)
            .environment(\.isSnapshot, true)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        var ok = false
        NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
            renderer.render { size, draw in
                var box = CGRect(origin: .zero, size: size)
                guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
                ctx.beginPDFPage(nil)
                draw(ctx)
                ctx.endPDFPage()
                ctx.closePDF()
                ok = true
            }
        }
        if !ok { throw ExportError() }
    }

    @MainActor
    static func writePNG<V: View>(_ view: V, dark: Bool, to url: URL) throws {
        let content = view
            .environment(\.isSnapshot, true)
            .environment(\.colorScheme, dark ? .dark : .light)
        let renderer = ImageRenderer(content: content)
        var data: Data?
        let scale: CGFloat = 2
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
            // Draw into an explicit 8-bit sRGB context; the default image follows the
            // display (HDR/PQ on recent Macs) and looks washed out as a PNG.
            renderer.render { size, draw in
                guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                          bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
                ctx.scaleBy(x: scale, y: scale)
                draw(ctx)
                if let cg = ctx.makeImage() {
                    data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
                }
            }
        }
        guard let data else { throw ExportError() }
        try data.write(to: url)
    }
}

/// Print-friendly version of the sheet: white page, title block, same columns.
struct PrintSheet: View {
    let sheet: Sheet
    let layout: SheetLayout

    private var model: PanelModel {
        let m = PanelModel()
        m.tab = sheet.id == "system" ? .system : .app
        return m
    }

    var body: some View {
        let model = self.model
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 16) {
                SheetIcon(image: sheet.icon, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(sheet.name) kısayolları")
                        .font(.system(size: 24, weight: .bold))
                    Text("\(sheet.shortcutCount) kısayol · \(Date.now.formatted(.dateTime.day().month(.wide).year().locale(Locale(identifier: "tr_TR"))))")
                        .font(.system(size: 12.5))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "command").font(.system(size: 11, weight: .bold))
                    Text("Kestirme").font(.system(size: 13, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Metrics.padH + 8)
            .padding(.top, 34)
            .padding(.bottom, 18)
            Rectangle().fill(Color.hairline).frame(height: 1).padding(.horizontal, Metrics.padH)
            HStack(alignment: .top, spacing: Metrics.columnGap) {
                ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                    VStack(alignment: .leading, spacing: Metrics.groupGap) {
                        ForEach(column) { chunk in
                            GroupBlock(model: model, chunk: chunk, icon: sheet.icon)
                        }
                    }
                    .frame(width: layout.columnWidth, alignment: .topLeading)
                }
            }
            .padding(.horizontal, Metrics.padH)
            .padding(.top, 14)
            .padding(.bottom, 36)
        }
        .frame(width: layout.panelSize.width)
        .background(Color.white)
    }
}
