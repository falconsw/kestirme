import AppKit
import SwiftUI

/// `Kestirme --render out.png [--dark] [--interactive] [--system] [--query q] [--select n] [--pdf out.pdf]`
/// `Kestirme --dump [bundle-id]`
enum DevTools {
    @MainActor
    static func run(_ args: [String]) {
        func value(_ flag: String) -> String? {
            guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
            return args[i + 1]
        }

        if args.contains("--dump") {
            dump(bundleID: value("--dump"))
            return
        }

        let model = PanelModel()
        model.mode = args.contains("--interactive") ? .interactive : .hold
        model.maxSize = CGSize(width: 1512 * 0.94, height: 945 * 0.9)
        model.appSheet = sampleSheet()
        model.appeared = true
        if args.contains("--system") {
            model.switchTab(.system)
        } else {
            model.rebuild()
        }
        if let q = value("--query") { model.query = q }
        if let n = value("--select").flatMap(Int.init) {
            model.selectedID = model.layout.orderedItems.dropFirst(n).first?.id
        }

        if let pdf = value("--pdf"), let sheet = model.sheet {
            do {
                try Exporter.writePDF(sheet: sheet, groups: model.exportGroups(), to: URL(fileURLWithPath: pdf))
                print("pdf:", pdf)
            } catch { print("pdf error:", error) }
        }

        guard let out = value("--render") else { return }
        let dark = args.contains("--dark")
        let stage = ZStack {
            LinearGradient(colors: dark ? [Color(red: 0.12, green: 0.1, blue: 0.25), Color(red: 0.05, green: 0.2, blue: 0.3)]
                                       : [Color(red: 0.62, green: 0.75, blue: 0.95), Color(red: 0.93, green: 0.78, blue: 0.86)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            SheetView(model: model)
                .compositingGroup()
                .shadow(color: .black.opacity(0.3), radius: 30, y: 12)
                .padding(60)
        }
        .fixedSize()
        do {
            try Exporter.writePNG(stage, dark: dark, to: URL(fileURLWithPath: out))
            let size = model.baseLayout.panelSize
            print("png:", out, "panel:", Int(size.width), "x", Int(size.height),
                  "columns:", model.baseLayout.columns.count)
        } catch { print("render error:", error) }
    }

    @MainActor
    static func dump(bundleID: String?) {
        guard AXIsProcessTrusted() else {
            print("Erişilebilirlik izni yok (bu süreç için).")
            return
        }
        let app = bundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
            ?? NSWorkspace.shared.frontmostApplication
        guard let app else { return }
        let start = Date()
        let groups = MenuReader.read(pid: app.processIdentifier, appName: app.localizedName ?? "")
        print("\(app.localizedName ?? "?") — \(groups.count) menü, \(String(format: "%.0f", Date().timeIntervalSince(start) * 1000)) ms")
        for g in groups {
            print("\n## \(g.title)")
            for i in g.items { print("  \(i.keyText.padding(toLength: 10, withPad: " ", startingAt: 0)) \(i.path.map { $0 + " › " } ?? "")\(i.title)\(i.enabled ? "" : " (pasif)")") }
        }
    }

    static func sampleSheet() -> Sheet {
        func s(_ keys: String, _ title: String, path: String? = nil, enabled: Bool = true, group: String) -> Shortcut {
            Shortcut(id: "\(group).\(title)", title: title, path: path, strokes: KeySymbols.parse(keys),
                     enabled: enabled, source: .menu, groupTitle: group)
        }
        func g(_ title: String, _ items: [(String, String)], appIcon: Bool = false) -> ShortcutGroup {
            var group = ShortcutGroup(
                id: title, title: title, symbol: MenuSymbols.symbol(for: title),
                items: items.map { entry -> Shortcut in
                    let parts = entry.1.components(separatedBy: " › ")
                    let disabled = entry.1.hasSuffix("~")
                    let title = parts.last!.replacingOccurrences(of: "~", with: "")
                    return s(entry.0, title, path: parts.count > 1 ? parts.dropLast().joined(separator: " › ") : nil,
                             enabled: !disabled, group: title)
                },
                isCurated: false)
            group.usesAppIcon = appIcon
            return group
        }
        let groups = [
            g("Safari", [("cmd+,", "Ayarlar…"), ("cmd+h", "Safari'yi Gizle"), ("opt+cmd+h", "Diğerlerini Gizle"), ("cmd+q", "Safari'den Çık")], appIcon: true),
            g("Dosya", [("cmd+n", "Yeni Pencere"), ("shift+cmd+n", "Yeni Özel Pencere"), ("cmd+t", "Yeni Sekme"),
                        ("cmd+o", "Dosya Aç…"), ("cmd+l", "Konum Aç…"), ("shift+cmd+w", "Pencereyi Kapat"),
                        ("cmd+w", "Sekmeyi Kapat"), ("cmd+s", "Farklı Kaydet…"), ("cmd+p", "Yazdır…")]),
            g("Düzen", [("cmd+z", "Geri Al"), ("shift+cmd+z", "Yinele~"), ("cmd+x", "Kes"), ("cmd+c", "Kopyala"),
                        ("cmd+v", "Yapıştır"), ("opt+shift+cmd+v", "Yapıştır ve Stili Eşle"), ("cmd+a", "Tümünü Seç"),
                        ("cmd+f", "Bul › Bul…"), ("cmd+g", "Bul › Sonrakini Bul"), ("shift+cmd+g", "Bul › Öncekini Bul"),
                        ("cmd+e", "Bul › Seçimi Bulmak İçin Kullan"), ("fn+e", "Emoji ve Simgeler")]),
            g("Görüntü", [("shift+cmd+l", "Kenar Çubuğunu Göster"), ("shift+cmd+\\", "Tüm Sekmeleri Göster"),
                          ("shift+cmd+r", "Okuyucuyu Göster"), ("cmd+0", "Gerçek Boyut"), ("cmd+plus", "Büyüt"),
                          ("cmd+-", "Küçült"), ("cmd+r", "Sayfayı Yeniden Yükle"), ("ctrl+cmd+f", "Tam Ekrana Geç")]),
            g("Geçmiş", [("cmd+[", "Geri"), ("cmd+]", "İleri"), ("shift+cmd+h", "Ana Sayfa"), ("cmd+y", "Tüm Geçmişi Göster"),
                         ("shift+cmd+t", "Son Kapatılan Sekmeyi Yeniden Aç")]),
            g("Yer İmleri", [("opt+cmd+b", "Yer İmlerini Göster"), ("cmd+d", "Yer İmi Ekle…"), ("shift+cmd+d", "Okuma Listesine Ekle")]),
            g("Geliştir", [("opt+cmd+i", "Web Denetçisini Göster"), ("opt+cmd+c", "JavaScript Konsolunu Göster"),
                           ("opt+cmd+u", "Sayfa Kaynağını Göster"), ("opt+cmd+e", "Önbellekleri Boşalt"),
                           ("opt+cmd+r", "Duyarlı Tasarım Modu")]),
            g("Pencere", [("cmd+m", "Küçült"), ("ctrl+tab", "Sonraki Sekmeyi Göster"), ("ctrl+shift+tab", "Önceki Sekmeyi Göster"),
                          ("fn+ctrl+f", "Taşı ve Yeniden Boyutlandır › Doldur")]),
        ]
        let tips = TipsLibrary.shared.extraGroups(for: "com.apple.Safari", excluding: groups)
        let count = groups.reduce(0) { $0 + $1.items.count }
        return Sheet(id: "com.apple.Safari", name: "Safari",
                     subtitle: "\(count) kısayol · \(groups.count) menü · \(tips.reduce(0) { $0 + $1.items.count }) gizli ipucu",
                     icon: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari")
                        .map { NSWorkspace.shared.icon(forFile: $0.path) },
                     groups: groups + tips, pid: nil)
    }
}
