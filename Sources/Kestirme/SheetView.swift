import AppKit
import SwiftUI

// MARK: - Environment & colors

private struct SnapshotKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True when rendering offscreen (PDF export, previews): no blur, no AppKit controls.
    var isSnapshot: Bool {
        get { self[SnapshotKey.self] }
        set { self[SnapshotKey.self] = newValue }
    }
}

extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }

    static let keyCapFill = dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.13))
    static let keyCapEdge = dynamic(light: NSColor(white: 0, alpha: 0.16), dark: NSColor(white: 0, alpha: 0.5))
    static let panelTint = dynamic(light: NSColor(white: 1, alpha: 0.42), dark: NSColor(white: 0.08, alpha: 0.38))
    static let panelSolid = dynamic(light: NSColor(red: 0.965, green: 0.965, blue: 0.975, alpha: 1),
                                    dark: NSColor(red: 0.13, green: 0.13, blue: 0.145, alpha: 1))
    static let hairline = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.08))
    static let panelBorder = dynamic(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 1, alpha: 0.14))
    static let selectedPill = dynamic(light: .white, dark: NSColor(white: 1, alpha: 0.16))
}

// MARK: - Root

struct SheetView: View {
    @Bindable var model: PanelModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        let size = model.baseLayout.panelSize
        VStack(spacing: 0) {
            HeaderBar(model: model)
            Rectangle().fill(Color.hairline).frame(height: 1)
            ContentArea(model: model)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            FooterBar(model: model)
        }
        .frame(width: size.width, height: size.height)
        .background(PanelBackground())
        .overlay(alignment: .bottom) { ToastView(text: model.toast).padding(.bottom, Metrics.footer + 14) }
        .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                .strokeBorder(Color.panelBorder, lineWidth: 1)
        )
        .scaleEffect(model.appeared || isSnapshot ? 1 : 0.965)
        .opacity(model.appeared || isSnapshot ? 1 : 0)
    }
}

struct PanelBackground: View {
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            Color.panelSolid
        } else {
            ZStack {
                VisualEffectBackground(material: .hudWindow)
                Color.panelTint
            }
        }
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = .behindWindow
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) { v.material = material }
}

// MARK: - Header

struct HeaderBar: View {
    @Bindable var model: PanelModel
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        HStack(spacing: 14) {
            SheetIcon(image: model.sheet?.icon, size: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.sheet?.name ?? "Kestirme")
                    .font(.system(size: 19, weight: .semibold))
                    .lineLimit(1)
                Text(model.sheet?.subtitle ?? " ")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 12)
            TabSwitcher(model: model)
            if model.mode == .interactive && !isSnapshot {
                SearchField(model: model)
                MoreMenu(model: model)
            } else if model.mode == .interactive {
                SearchFieldPlaceholder(query: model.query)
            } else if let stroke = model.hotKeyStroke {
                HStack(spacing: 6) {
                    KeyCombo(strokes: [stroke], compact: true)
                    Text("sabitle")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Capsule().fill(Color.primary.opacity(0.055)))
            }
        }
        .padding(.horizontal, 22)
        .frame(height: Metrics.header)
    }
}

struct SheetIcon: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                Image(systemName: "command.square.fill").resizable().foregroundStyle(.tint)
            }
        }
        .aspectRatio(contentMode: .fit)
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.18), radius: 3, y: 1.5)
    }
}

struct TabSwitcher: View {
    @Bindable var model: PanelModel
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 2) {
            tab(.app, title: model.appSheet?.name ?? "Uygulama") {
                SheetIcon(image: model.appSheet?.icon, size: 15).shadow(radius: 0)
            }
            tab(.system, title: "macOS") {
                Image(systemName: "laptopcomputer").font(.system(size: 11, weight: .semibold))
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }

    private func tab<Icon: View>(_ t: PanelModel.Tab, title: String, @ViewBuilder icon: () -> Icon) -> some View {
        let selected = model.tab == t
        return Button {
            model.switchTab(t)
        } label: {
            HStack(spacing: 6) {
                icon()
                Text(title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
                    .frame(maxWidth: 110)
                    .fixedSize()
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 11)
            .frame(height: 26)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.selectedPill)
                        .shadow(color: .black.opacity(0.12), radius: 1.5, y: 0.5)
                        .matchedGeometryEffect(id: "pill", in: ns)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SearchField: View {
    @Bindable var model: PanelModel
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
            TextField("Kısayol ara", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($focused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 210, height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(focused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08),
                              lineWidth: focused ? 1.5 : 1)
        )
        .onAppear { focused = true }
        .onChange(of: model.focusToken) { focused = true }
    }
}

struct SearchFieldPlaceholder: View {
    let query: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
            Text(query.isEmpty ? "Kısayol ara" : query)
                .font(.system(size: 13))
                .foregroundStyle(query.isEmpty ? .tertiary : .primary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(width: 210, height: 32)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .strokeBorder(Color.accentColor.opacity(0.7), lineWidth: 1.5))
    }
}

struct MoreMenu: View {
    @Bindable var model: PanelModel

    var body: some View {
        Menu {
            Button("PDF olarak kaydet…") { model.onExportPDF?() }
            Button("Markdown olarak kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(model.markdown(), forType: .string)
                model.showToast("Markdown panoya kopyalandı")
            }
            Divider()
            Button("Ayarlar…") { model.onOpenSettings?() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Content

struct ContentArea: View {
    @Bindable var model: PanelModel

    var body: some View {
        if !model.trusted && model.tab == .app {
            PermissionCard { model.onRequestPermission?() }
        } else if model.sheet == nil || (model.isLoading && model.baseLayout.isEmpty && model.tab == .app) {
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text("Menüler okunuyor…").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        } else if model.layout.isEmpty {
            EmptyState(model: model)
        } else {
            ColumnsView(model: model, layout: model.layout)
        }
    }
}

struct ColumnsView: View {
    @Bindable var model: PanelModel
    let layout: SheetLayout
    @Environment(\.isSnapshot) private var isSnapshot

    var body: some View {
        if isSnapshot {
            // NSScrollView-backed views do not render offscreen.
            padded.frame(maxHeight: .infinity, alignment: .top).clipped()
        } else {
            scrolling
        }
    }

    private var padded: some View {
        columns
            .padding(.horizontal, Metrics.padH)
            .padding(.top, Metrics.padTop)
            .padding(.bottom, Metrics.padBottom)
            .frame(maxWidth: .infinity)
    }

    private var scrolling: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) { padded }
            .scrollIndicators(.automatic)
            .onChange(of: model.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.snappy(duration: 0.18)) { proxy.scrollTo(id, anchor: nil) }
            }
        }
    }

    var columns: some View {
        HStack(alignment: .top, spacing: Metrics.columnGap) {
            ForEach(Array(layout.columns.enumerated()), id: \.offset) { _, column in
                VStack(alignment: .leading, spacing: Metrics.groupGap) {
                    ForEach(column) { chunk in
                        GroupBlock(model: model, chunk: chunk, icon: model.sheet?.icon)
                    }
                }
                .frame(width: layout.columnWidth, alignment: .topLeading)
            }
        }
    }
}

struct GroupBlock: View {
    @Bindable var model: PanelModel
    let chunk: LayoutChunk
    let icon: NSImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            GroupHeader(chunk: chunk, icon: icon, showsBadge: model.tab == .app)
                .frame(height: Metrics.groupHeader, alignment: .bottom)
            ForEach(chunk.items) { item in
                ShortcutRow(model: model, item: item)
                    .frame(height: Metrics.rowHeight)
                    .id(item.id)
            }
        }
    }
}

struct GroupHeader: View {
    let chunk: LayoutChunk
    let icon: NSImage?
    let showsBadge: Bool

    var body: some View {
        HStack(spacing: 7) {
            if chunk.group.usesAppIcon, let icon {
                Image(nsImage: icon).resizable().frame(width: 15, height: 15)
            } else {
                Image(systemName: chunk.group.symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 15)
            }
            Text(chunk.group.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .layoutPriority(2)
            if chunk.continued {
                Text("devam")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            if let note = chunk.group.note {
                Text(note)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.tertiary)
                    .fixedSize()
            }
            if chunk.group.isCurated && showsBadge {
                Text("MENÜDE YOK")
                    .font(.system(size: 8.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(.tint)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.13)))
                    .fixedSize()
                    .help("Bu kısayollar uygulamanın menülerinde görünmez; Kestirme'nin ipucu kütüphanesinden gelir.")
            }
            Spacer(minLength: 0)
            Rectangle().fill(Color.hairline).frame(height: 1).frame(maxWidth: .infinity)
                .padding(.leading, 4)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 7)
    }
}

struct ShortcutRow: View {
    @Bindable var model: PanelModel
    let item: Shortcut

    var body: some View {
        let selected = model.selectedID == item.id
        let hovered = model.hoveredID == item.id && item.isRunnable
        HStack(spacing: 10) {
            HStack(spacing: 0) {
                // The submenu path gives way before the command name does.
                if let path = item.path {
                    Text(path + " › ")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(titleText)
                    .font(.system(size: 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .layoutPriority(1)
            }
            .layoutPriority(1)
            Spacer(minLength: 8)
            KeyCombo(strokes: item.strokes)
                .layoutPriority(2)
        }
        .padding(.horizontal, 8)
        .frame(maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? Color.accentColor.opacity(0.2) : (hovered ? Color.primary.opacity(0.065) : .clear))
        )
        .opacity(item.enabled ? 1 : 0.42)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hoveredID = item.id } else if model.hoveredID == item.id { model.hoveredID = nil }
        }
        .onTapGesture { model.run(item) }
        .help(helpText)
    }

    private var helpText: String {
        var parts: [String] = []
        if let note = item.note { parts.append(note) }
        if item.isRunnable { parts.append("Tıkla: komutu çalıştır") }
        else if item.source == .menu && !item.enabled { parts.append("Şu an kullanılamıyor") }
        return parts.joined(separator: " · ")
    }

    private var titleText: AttributedString {
        var out = AttributedString()
        var t = AttributedString(item.title)
        t.foregroundColor = .primary
        for token in Search.tokens(model.query) {
            if let r = t.range(of: token, options: [.caseInsensitive, .diacriticInsensitive]) {
                t[r].foregroundColor = .accentColor
                t[r].font = .system(size: 13, weight: .semibold)
            }
        }
        out += t
        if item.source == .curated, !item.enabled {
            var off = AttributedString("  kapalı")
            off.foregroundColor = .secondary
            off.font = .system(size: 11, weight: .medium)
            out += off
        } else if item.note != nil, item.source == .curated {
            var dot = AttributedString("  ⓘ")
            dot.foregroundColor = .secondary
            dot.font = .system(size: 10)
            out += dot
        }
        return out
    }
}

// MARK: - Keycaps

struct KeyCombo: View {
    let strokes: [KeyStroke]
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 5 : 8) {
            ForEach(Array(strokes.enumerated()), id: \.offset) { _, s in caps(s.caps) }
        }
        .fixedSize()
    }

    private func caps(_ labels: [String]) -> some View {
        HStack(spacing: 3) {
            ForEach(Array(labels.enumerated()), id: \.offset) { _, l in KeyCap(label: l, compact: compact) }
        }
    }
}

struct KeyCap: View {
    let label: String
    var compact = false

    private var isWord: Bool { label.count > 1 }

    var body: some View {
        let side: CGFloat = compact ? 18 : 21
        Text(label)
            .font(.system(size: isWord ? (compact ? 9.5 : 10.5) : (compact ? 11 : 12.5),
                          weight: .medium, design: .rounded))
            .foregroundStyle(Color.primary.opacity(0.8))
            .padding(.horizontal, isWord ? 5 : 0)
            .frame(minWidth: side, minHeight: side, maxHeight: side)
            .background(
                RoundedRectangle(cornerRadius: compact ? 4.5 : 5.5, style: .continuous)
                    .fill(Color.keyCapFill)
                    .shadow(color: Color.keyCapEdge, radius: 0, x: 0, y: 0.9)
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 4.5 : 5.5, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
    }
}

// MARK: - Footer, states, toast

struct FooterBar: View {
    @Bindable var model: PanelModel

    var body: some View {
        HStack(spacing: 18) {
            if model.mode == .hold {
                hint(["⌘"], "bırakınca kapanır")
                hint(nil, "Satıra tıkla: komutu çalıştır", symbol: "cursorarrow.click.2")
            } else {
                hint(["↑", "↓", "←", "→"], "gez")
                hint(["↩"], "çalıştır")
                hint(["⇥"], "sekme")
                hint(["esc"], "kapat")
            }
            Spacer(minLength: 8)
            HStack(spacing: 5) {
                Image(systemName: "command")
                    .font(.system(size: 10, weight: .bold))
                Text("Kestirme")
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 22)
        .frame(height: Metrics.footer)
        .background(Color.primary.opacity(0.035))
        .overlay(alignment: .top) { Rectangle().fill(Color.hairline).frame(height: 1) }
    }

    private func hint(_ caps: [String]?, _ text: String, symbol: String? = nil) -> some View {
        HStack(spacing: 6) {
            if let caps {
                HStack(spacing: 2) { ForEach(caps, id: \.self) { KeyCap(label: $0, compact: true) } }
            }
            if let symbol {
                Image(systemName: symbol).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            Text(text).font(.system(size: 11.5)).foregroundStyle(.secondary)
        }
    }
}

struct EmptyState: View {
    @Bindable var model: PanelModel

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: model.query.isEmpty ? "keyboard" : "magnifyingglass")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(.tertiary)
                .padding(.bottom, 4)
            if model.query.isEmpty {
                Text("Bu uygulamanın menülerinde kısayol yok")
                    .font(.system(size: 15, weight: .semibold))
                if model.tab == .app {
                    Button("macOS kısayollarına göz at") { model.switchTab(.system) }
                        .buttonStyle(.link)
                        .font(.system(size: 13))
                }
            } else {
                Text("“\(model.query)” için sonuç yok")
                    .font(.system(size: 15, weight: .semibold))
                Text("Komut adıyla ya da “cmd shift k” gibi tuşlarla arayabilirsin.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(40)
    }
}

struct PermissionCard: View {
    let action: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tint)
            Text("Menüleri okumak için izin gerekiyor")
                .font(.system(size: 16, weight: .semibold))
            Text("Kestirme, öndeki uygulamanın menülerini Erişilebilirlik izniyle okur.\nHiçbir veri Mac'inden dışarı çıkmaz.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Erişilebilirlik iznini ver", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .padding(40)
    }
}

struct ToastView: View {
    let text: String?

    var body: some View {
        if let text {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(text).font(.system(size: 12.5, weight: .medium))
            }
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(.regularMaterial))
            .overlay(Capsule().strokeBorder(Color.panelBorder, lineWidth: 1))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}
