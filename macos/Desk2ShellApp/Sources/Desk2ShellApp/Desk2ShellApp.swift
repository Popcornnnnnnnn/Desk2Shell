import SwiftUI
import Sparkle

@MainActor
private final class CheckForUpdatesViewModel: ObservableObject {
    @Published var canCheckForUpdates = false

    init(updater: SPUUpdater) {
        updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }
}

private struct CheckForUpdatesView: View {
    @ObservedObject private var model: CheckForUpdatesViewModel
    @AppStorage(AppLanguage.defaultsKey) private var languageRaw = AppLanguage.preferred.rawValue
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        model = CheckForUpdatesViewModel(updater: updater)
    }

    var body: some View {
        Button(language.text("检查更新…", "Check for Updates…")) {
            updater.checkForUpdates()
        }
        .disabled(!model.canCheckForUpdates)
    }

    private var language: AppLanguage {
        AppLanguage(rawValue: languageRaw) ?? AppLanguage.preferred
    }
}

@main
struct Desk2ShellApp: App {
    @StateObject private var model = AppViewModel()
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 680)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appInfo) {
                CheckForUpdatesView(updater: updaterController.updater)
            }
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: AppViewModel

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    targetCard
                    authCard
                    pairingCard
                    connectionCard
                    footer
                }
                .padding(28)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .tint(Color(red: 0.16, green: 0.45, blue: 0.96))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 11) {
                BrandIcon(size: 42)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Desk2Shell").font(.headline).foregroundStyle(.white)
                    Text("REMOTE → SSH").font(.caption2.weight(.semibold)).tracking(1.1).foregroundStyle(.white.opacity(0.55))
                }
            }
            VStack(alignment: .leading, spacing: 17) {
                StepRow(number: 1, title: model.text("目标", "Target"), active: model.packagePath.isEmpty)
                StepRow(number: 2, title: model.text("授权", "Authorize"), active: model.packagePath.isEmpty)
                StepRow(number: 3, title: model.text("传输", "Transfer"), active: !model.packagePath.isEmpty && model.targetIPv4.isEmpty)
                StepRow(number: 4, title: model.text("连接", "Connect"), active: !model.targetIPv4.isEmpty)
            }
            Picker(model.text("语言", "Language"), selection: $model.language) {
                Text("中文").tag(AppLanguage.zhHans)
                Text("EN").tag(AppLanguage.english)
            }
            .pickerStyle(.segmented)
            .colorScheme(.dark)
            .labelsHidden()
            .accessibilityLabel(model.text("语言", "Language"))
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                Label(model.text("普通 SSH", "Standard SSH"), systemImage: "terminal")
                Label(model.text("Tailscale 网络", "Tailscale network"), systemImage: "point.3.connected.trianglepath.dotted")
                Label(model.text("默认 24 小时", "24 hours by default"), systemImage: "clock.arrow.circlepath")
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.62))
        }
        .padding(22)
        .frame(width: 205)
        .background(
            LinearGradient(
                colors: [Color(red: 0.035, green: 0.075, blue: 0.16), Color(red: 0.035, green: 0.17, blue: 0.22)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(model.text("建立一个临时 Windows 节点", "Create a temporary Windows node"))
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Text(model.text(
                "从任意远程桌面传入一次安装包，之后让终端和 AI 编程工具直接使用标准 SSH。",
                "Transfer one setup package over any remote desktop, then use standard SSH from terminals and AI coding tools."
            ))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var targetCard: some View {
        ProductCard(
            number: "01",
            title: model.text("目标与有效期", "Target and duration"),
            subtitle: model.text("远端账号的现有权限保持不变", "The remote account keeps its existing permissions")
        ) {
            HStack(spacing: 12) {
                TextField(model.text("设备名，例如 lab-win", "Device name, e.g. lab-win"), text: $model.targetAlias)
                    .textFieldStyle(.roundedBorder)
                TextField(model.text("Windows 登录名（可稍后导入）", "Windows username (can be imported later)"), text: $model.windowsUser)
                    .textFieldStyle(.roundedBorder)
            }
            Stepper(model.text(
                "访问 \(model.durationHours) 小时后自动撤销",
                "Revoke access automatically after \(model.durationHours) hours"
            ), value: $model.durationHours, in: 1...168)
                .font(.callout)
        }
    }

    private var authCard: some View {
        ProductCard(
            number: "02",
            title: model.text("一次性网络授权", "One-off network authorization"),
            subtitle: model.text(
                "此码由 Tailscale 账户签发，Desk2Shell 不会也不能代替账户生成",
                "Issued by your Tailscale account; Desk2Shell cannot generate it for you"
            )
        ) {
            SecureField("tskey-auth-…", text: $model.authKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button(model.text("在 Tailscale 创建", "Create in Tailscale"), systemImage: "arrow.up.right.square") {
                    model.openTailscaleAuthKeyPage()
                }
                Button(model.text("从剪贴板粘贴", "Paste from Clipboard"), systemImage: "clipboard") {
                    model.pasteAuthKey()
                }
                Spacer()
                Button {
                    model.createPackage()
                } label: {
                    Label(
                        model.busy
                            ? model.text("正在生成…", "Generating…")
                            : model.text("生成 Windows 安装包", "Generate Windows Package"),
                        systemImage: "shippingbox.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(model.busy)
            }
            if !model.packagePath.isEmpty {
                Text(model.packagePath)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var pairingCard: some View {
        ProductCard(
            number: "03",
            title: model.text("传输与配对", "Transfer and pair"),
            subtitle: model.text(
                "把 ZIP 传到 Windows 并运行 Bootstrap，再粘贴配对码",
                "Transfer the ZIP to Windows, run Bootstrap, then paste the pairing code"
            )
        ) {
            HStack(spacing: 12) {
                Text(model.pairingCode.isEmpty ? model.text("正在生成安全配对码…", "Generating a secure pairing code…") : model.pairingCode)
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .foregroundStyle(model.pairingCode.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button(model.text("复制", "Copy"), systemImage: "doc.on.doc") { model.copyPairingCode() }
                    .disabled(model.pairingCode.isEmpty)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            Text(model.text(
                "配对码由 Desk2Shell 自动生成，并用于加密这次安装；它不是 Tailscale Auth Key。",
                "Desk2Shell generates this pairing code to encrypt the setup. It is not a Tailscale Auth Key."
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionCard: some View {
        ProductCard(
            number: "04",
            title: model.text("发现并验证", "Discover and verify"),
            subtitle: model.text(
                "优先通过 Taildrop 自动收取结果，并固定 SSH 主机指纹",
                "Receive the result through Taildrop when possible and pin the SSH host fingerprint"
            )
        ) {
            HStack {
                Button(model.text("立即检查", "Check Now"), systemImage: "arrow.clockwise") { model.checkConnection() }
                    .disabled(model.busy || model.packagePath.isEmpty)
                Button(model.text("导入结果", "Import Result"), systemImage: "square.and.arrow.down") { model.importResult() }
                    .disabled(model.packagePath.isEmpty)
                Button(model.text("复制 ssh 命令", "Copy ssh Command"), systemImage: "terminal") { model.copySSHCommand() }
                    .disabled(model.targetIPv4.isEmpty)
                Spacer()
                if !model.targetIPv4.isEmpty {
                    Text(model.targetIPv4)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 9).padding(.vertical, 5)
                        .background(.green.opacity(0.12), in: Capsule())
                }
            }
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: model.statusIsSuccess ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(model.statusIsSuccess ? .green : .secondary)
                Text(model.status).font(.callout).textSelection(.enabled)
            }
            Toggle(model.text("自愿发送匿名成功/失败回执", "Voluntarily send anonymous success/failure events"), isOn: Binding(
                get: { model.telemetryOptIn },
                set: { model.setTelemetryOptIn($0) }
            ))
            .font(.caption)
            .disabled(!model.telemetryAvailable)
        }
        .padding(.horizontal, 2)
    }
}

private struct ProductCard<Content: View>: View {
    let number: String
    let title: String
    let subtitle: String
    @ViewBuilder let content: Content

    init(number: String, title: String, subtitle: String, @ViewBuilder content: () -> Content) {
        self.number = number
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 11) {
                Text(number)
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
            }
            content
        }
        .padding(17)
        .background(.background, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.primary.opacity(0.07)))
        .shadow(color: .black.opacity(0.04), radius: 10, y: 4)
    }
}

private struct StepRow: View {
    let number: Int
    let title: String
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(String(number))
                .font(.caption.weight(.bold))
                .frame(width: 24, height: 24)
                .background(active ? Color.white : Color.white.opacity(0.1), in: Circle())
                .foregroundStyle(active ? Color(red: 0.05, green: 0.18, blue: 0.28) : .white.opacity(0.55))
            Text(title).font(.callout.weight(active ? .semibold : .regular))
                .foregroundStyle(.white.opacity(active ? 1 : 0.55))
        }
    }
}

private struct BrandIcon: View {
    let size: CGFloat

    private var logo: NSImage? {
        let bundle = Bundle.module
        let candidates = [
            bundle.url(forResource: "Desk2ShellLogo", withExtension: "png", subdirectory: "Resources"),
            bundle.resourceURL?.appendingPathComponent("Desk2ShellLogo.png"),
            bundle.bundleURL.appendingPathComponent("Resources/Desk2ShellLogo.png")
        ]
        return candidates.compactMap { $0 }.lazy.compactMap(NSImage.init(contentsOf:)).first
    }

    var body: some View {
        if let image = logo {
            Image(nsImage: image).resizable().scaledToFit().frame(width: size, height: size)
        } else {
            Image(systemName: "terminal.fill")
                .font(.system(size: size * 0.48, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.blue.gradient, in: RoundedRectangle(cornerRadius: size * 0.23))
        }
    }
}
