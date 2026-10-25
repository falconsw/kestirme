import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var prefs = Preferences.shared
    @State private var trusted = AXIsProcessTrusted()
    @State private var loginStatus = SMAppService.mainApp.status
    @State private var userFileError: String?
    let onChange: () -> Void
    let onRequestPermission: () -> Void

    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $prefs.holdEnabled) {
                    Text("⌘ tuşunu basılı tutunca göster")
                    Text("Bırakınca kapanır. Başka bir tuşa basarsan açılmaz.")
                }
                if prefs.holdEnabled {
                    LabeledContent("Bekleme süresi") {
                        HStack(spacing: 10) {
                            Slider(value: $prefs.holdDelay, in: 0.3...2.0, step: 0.1)
                                .frame(width: 180)
                            Text(String(format: "%.1f sn", prefs.holdDelay).replacingOccurrences(of: ".", with: ","))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                    }
                }
                Toggle(isOn: $prefs.hotKeyEnabled) {
                    Text("Kısayol tuşuyla aç / kapat")
                    Text("Panel açık kalır: arayabilir, klavyeyle gezip komut çalıştırabilirsin.")
                }
                if prefs.hotKeyEnabled {
                    LabeledContent("Kısayol tuşu") {
                        HotKeyRecorder(spec: $prefs.hotKey)
                    }
                }
            } header: {
                Text("Açılış")
            }

            Section {
                Toggle(isOn: $prefs.showTips) {
                    Text("Menüde olmayan ipuçlarını göster")
                    Text("Finder, tarayıcılar, VS Code, terminal ve Xcode için gizli kısayollar.")
                }
                Toggle(isOn: $prefs.showDisabled) {
                    Text("Şu an kullanılamayan komutları soluk göster")
                }
                LabeledContent {
                    Button("Dosyayı aç") {
                        TipsLibrary.shared.openUserFile()
                    }
                } label: {
                    Text("Kendi kısayolların")
                    Text(userFileError.map { "Dosyada hata var: \($0)" }
                         ?? "kisayollar.json dosyasına uygulamaya ya da sisteme özel kısayollar ekle.")
                        .foregroundStyle(userFileError == nil ? Color.secondary : Color.red)
                }
            } header: {
                Text("İçerik")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { [.enabled, .requiresApproval].contains(loginStatus) },
                    set: { on in
                        prefs.launchAtLogin = on
                        loginStatus = SMAppService.mainApp.status
                    }
                )) {
                    Text("Oturum açıldığında başlat")
                    Text("Kestirme arka planda çalışır; pencere açmaz, Dock'ta görünmez.")
                }
                if loginStatus == .requiresApproval {
                    LabeledContent {
                        Button("Giriş Öğeleri'ni Aç") { SMAppService.openSystemSettingsLoginItems() }
                    } label: {
                        Text("macOS onayı bekleniyor")
                        Text("Sistem Ayarları › Genel › Giriş Öğeleri'nde Kestirme'yi aç.")
                    }
                }
                Toggle(isOn: $prefs.showMenuBarIcon) {
                    Text("Menü çubuğunda göster")
                    Text(prefs.showMenuBarIcon
                         ? "Simgeyi ⌘ basılı tutup menü çubuğundan dışarı sürükleyerek de gizleyebilirsin."
                         : "Gizliyken ayarlara dönmek için Kestirme'yi Spotlight'tan yeniden aç ya da panelde ⌘, kullan.")
                }
                LabeledContent {
                    if trusted {
                        Label("Verildi", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("İzin ver", action: onRequestPermission)
                    }
                } label: {
                    Text("Erişilebilirlik izni")
                    Text("Menüleri okumak ve ⌘ tuşunu algılamak için gerekli.")
                }
            } header: {
                Text("Genel")
            }

            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 40, height: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Kestirme").font(.system(size: 13, weight: .semibold))
                        Text("Sürüm \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")")
                            .font(.system(size: 11.5))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: prefs.holdEnabled) { onChange() }
        .onChange(of: prefs.holdDelay) { onChange() }
        .onChange(of: prefs.hotKeyEnabled) { onChange() }
        .onChange(of: prefs.hotKey) { onChange() }
        .onChange(of: prefs.showMenuBarIcon) { onChange() }
        .onReceive(timer) { _ in
            trusted = AXIsProcessTrusted()
            loginStatus = SMAppService.mainApp.status
            TipsLibrary.shared.reload()
            userFileError = TipsLibrary.shared.validateUserFile()
        }
    }
}

/// Click, then press the new combination. Esc cancels, ⌫ restores the default.
struct HotKeyRecorder: View {
    @Binding var spec: HotKeySpec
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            HStack(spacing: 8) {
                if recording {
                    Text("Tuşlara bas…")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.tint)
                } else {
                    KeyCombo(strokes: [spec.stroke])
                }
            }
            .frame(minWidth: 110, minHeight: 28)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(recording ? 0.02 : 0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(recording ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: recording ? 1.5 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Değiştirmek için tıkla. Esc: vazgeç, ⌫: varsayılana dön")
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        AppController.shared.isRecordingHotKey = true
        HotKeyCenter.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
            let code = Int(e.keyCode)
            let flags = e.modifierFlags.intersection([.command, .option, .control, .shift])
            if code == kVK_Escape { stop(); return nil }
            if code == kVK_Delete && flags.isEmpty { spec = .default; stop(); return nil }
            let isFunctionKey = (KeySymbols.virtualKeys[code] ?? "").hasPrefix("F")
            guard !flags.subtracting(.shift).isEmpty || isFunctionKey else {
                NSSound.beep()
                return nil
            }
            let label = KeyboardLayout.label(for: code)
                ?? KeySymbols.label(forKeyCode: code, characters: e.charactersIgnoringModifiers)
            spec = HotKeySpec(keyCode: code, modifiers: flags.rawValue, label: label)
            stop()
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        guard recording else { return }
        recording = false
        AppController.shared.isRecordingHotKey = false
        AppController.shared.applyPreferences()
    }
}
