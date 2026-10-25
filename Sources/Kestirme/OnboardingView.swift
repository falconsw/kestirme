import AppKit
import Combine
import SwiftUI

struct OnboardingView: View {
    @State private var trusted = AXIsProcessTrusted()
    let hotKey: KeyStroke
    let onRequestPermission: () -> Void
    let onDone: () -> Void

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 92, height: 92)
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
                Text("Kestirme'ye hoş geldin")
                    .font(.system(size: 26, weight: .bold))
                Text("Her uygulamanın klavye kısayolları, bir tuş uzağında.")
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 34)
            .padding(.bottom, 26)

            HStack(spacing: 14) {
                FeatureCard(caps: ["⌘"], title: "Basılı tut",
                            text: "⌘ tuşunu bir an basılı tut; öndeki uygulamanın tüm kısayolları belirsin. Bırakınca kaybolur.")
                FeatureCard(caps: hotKey.caps, title: "Sabitle ve ara",
                            text: "Panel açık kalır: yaz, ara, ok tuşlarıyla gez ve ↩ ile komutu doğrudan çalıştır.")
            }
            .padding(.horizontal, 32)

            HStack(spacing: 22) {
                mini("sparkles", "Menüde olmayan gizli kısayollar")
                mini("gearshape", "Mac'indeki gerçek ayarlar")
                mini("doc.richtext", "PDF / Markdown")
            }
            .padding(.top, 18)

            PermissionStep(trusted: trusted, action: onRequestPermission)
                .padding(.horizontal, 32)
                .padding(.top, 24)

            HStack {
                Spacer()
                Button(trusted ? "Başla" : "Sonra") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .disabled(false)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 22)
        }
        .frame(width: 620)
        .background(Color.panelSolid)
        .onReceive(timer) { _ in
            let now = AXIsProcessTrusted()
            if now != trusted { withAnimation(.snappy) { trusted = now } }
        }
    }

    private func mini(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: symbol).foregroundStyle(.tint)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.system(size: 12))
    }
}

private struct FeatureCard: View {
    let caps: [String]
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 4) {
                ForEach(caps, id: \.self) { BigKeyCap(label: $0) }
            }
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(text)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.hairline, lineWidth: 1))
    }
}

struct BigKeyCap: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: label.count > 1 ? 13 : 19, weight: .medium, design: .rounded))
            .foregroundStyle(Color.primary.opacity(0.85))
            .padding(.horizontal, label.count > 1 ? 8 : 0)
            .frame(minWidth: 38, minHeight: 38)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.keyCapFill)
                    .shadow(color: Color.keyCapEdge, radius: 0, x: 0, y: 1.5)
            )
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

private struct PermissionStep: View {
    let trusted: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(trusted ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
                    .frame(width: 40, height: 40)
                Image(systemName: trusted ? "checkmark" : "lock.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(trusted ? .green : .orange)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(trusted ? "Hazırsın! Şimdi ⌘ tuşunu basılı tutmayı dene." : "Erişilebilirlik izni gerekiyor")
                    .font(.system(size: 13.5, weight: .semibold))
                Text(trusted
                     ? "Kestirme arka planda çalışır ve oturum açılınca kendiliğinden başlar. Ayarlar için menü çubuğundaki ⌘ simgesine tıkla."
                     : "Sistem Ayarları › Gizlilik ve Güvenlik › Erişilebilirlik bölümünde Kestirme'yi aç. Veriler Mac'inden çıkmaz.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !trusted {
                Button("Ayarları Aç", action: action)
                    .controlSize(.large)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(trusted ? Color.green.opacity(0.06) : Color.orange.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(trusted ? Color.green.opacity(0.25) : Color.orange.opacity(0.25), lineWidth: 1))
    }
}
