import SwiftUI

@main
struct Desk2ShellApp: App {
    @StateObject private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 860, minHeight: 680)
        }
        .windowResizability(.contentSize)
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
                StepRow(number: 1, title: "目标", active: model.packagePath.isEmpty)
                StepRow(number: 2, title: "授权", active: model.packagePath.isEmpty)
                StepRow(number: 3, title: "传输", active: !model.packagePath.isEmpty && model.targetIPv4.isEmpty)
                StepRow(number: 4, title: "连接", active: !model.targetIPv4.isEmpty)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                Label("普通 SSH", systemImage: "terminal")
                Label("Tailscale 网络", systemImage: "point.3.connected.trianglepath.dotted")
                Label("默认 24 小时", systemImage: "clock.arrow.circlepath")
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
            Text("建立一个临时 Windows 节点")
                .font(.system(size: 27, weight: .bold, design: .rounded))
            Text("从任意远程桌面传入一次安装包，之后让终端和 AI 编程工具直接使用标准 SSH。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var targetCard: some View {
        ProductCard(number: "01", title: "目标与有效期", subtitle: "远端账号的现有权限保持不变") {
            HStack(spacing: 12) {
                TextField("设备名，例如 lab-win", text: $model.targetAlias)
                    .textFieldStyle(.roundedBorder)
                TextField("Windows 登录名（可稍后导入）", text: $model.windowsUser)
                    .textFieldStyle(.roundedBorder)
            }
            Stepper("访问 \(model.durationHours) 小时后自动撤销", value: $model.durationHours, in: 1...168)
                .font(.callout)
        }
    }

    private var authCard: some View {
        ProductCard(number: "02", title: "一次性网络授权", subtitle: "此码由 Tailscale 账户签发，Desk2Shell 不会也不能代替账户生成") {
            SecureField("tskey-auth-…", text: $model.authKey)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("在 Tailscale 创建", systemImage: "arrow.up.right.square") {
                    model.openTailscaleAuthKeyPage()
                }
                Button("从剪贴板粘贴", systemImage: "clipboard") {
                    model.pasteAuthKey()
                }
                Spacer()
                Button {
                    model.createPackage()
                } label: {
                    Label(model.busy ? "正在生成…" : "生成 Windows 安装包", systemImage: "shippingbox.fill")
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
        ProductCard(number: "03", title: "传输与配对", subtitle: "把 ZIP 传到 Windows 并运行 Bootstrap，再粘贴配对码") {
            HStack(spacing: 12) {
                Text(model.pairingCode.isEmpty ? "正在生成安全配对码…" : model.pairingCode)
                    .font(.system(.callout, design: .monospaced, weight: .medium))
                    .foregroundStyle(model.pairingCode.isEmpty ? .secondary : .primary)
                    .textSelection(.enabled)
                    .lineLimit(2)
                Spacer()
                Button("复制", systemImage: "doc.on.doc") { model.copyPairingCode() }
                    .disabled(model.pairingCode.isEmpty)
            }
            .padding(12)
            .background(Color.accentColor.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            Text("配对码由 Desk2Shell 自动生成，并用于加密这次安装；它不是 Tailscale Auth Key。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var connectionCard: some View {
        ProductCard(number: "04", title: "发现并验证", subtitle: "优先通过 Taildrop 自动收取结果，并固定 SSH 主机指纹") {
            HStack {
                Button("立即检查", systemImage: "arrow.clockwise") { model.checkConnection() }
                    .disabled(model.busy || model.packagePath.isEmpty)
                Button("导入结果", systemImage: "square.and.arrow.down") { model.importResult() }
                    .disabled(model.packagePath.isEmpty)
                Button("复制 ssh 命令", systemImage: "terminal") { model.copySSHCommand() }
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
                Image(systemName: model.status.hasPrefix("连接成功") ? "checkmark.circle.fill" : "info.circle.fill")
                    .foregroundStyle(model.status.hasPrefix("连接成功") ? .green : .secondary)
                Text(model.status).font(.callout).textSelection(.enabled)
            }
            Toggle("自愿发送匿名成功/失败回执", isOn: Binding(
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
