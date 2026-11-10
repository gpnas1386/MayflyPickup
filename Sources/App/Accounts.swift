import SwiftUI
import WebKit

struct AccountRow: View {
    let platform: Platform
    let theme: Theme
    let info: AccountInfo?
    let login: () -> Void
    let scrape: () -> Void
    let logout: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(Color(hex: platform.colorHex)).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(platform.title).font(.system(size: 14, weight: .semibold))
                Text(info?.nick.isEmpty == false ? "已登录 · \(info?.nick ?? "")" : "未登录")
                    .font(.system(size: 11)).foregroundColor(theme.sub)
            }
            Spacer()
            if info != nil {
                Button("抓取", action: scrape)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.borderless)
                Button("退出", action: logout)
                    .font(.system(size: 12)).foregroundColor(.red)
                    .buttonStyle(.borderless)
            } else {
                Button("登录", action: login)
                    .font(.system(size: 12, weight: .semibold))
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 2)
    }
}

final class LoginBridge: NSObject, ObservableObject, WKNavigationDelegate {
    let web: WKWebView

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        web = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        web.navigationDelegate = self
    }

    func cookies(_ done: @escaping ([HTTPCookie]) -> Void) {
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { done($0) }
    }
}

struct WebLoginView: View {
    let platform: Platform
    let theme: Theme
    let onDone: (ScrapeResult) -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var bridge = LoginBridge()
    @State private var done = false
    @State private var failedLogin = false

    private var startURL: URL {
        switch platform {
        case .taobao: return URL(string: "https://m.cainiao.com/")!
        case .pdd: return URL(string: "https://m.pinduoduo.net/")!
        case .jd: return URL(string: "https://m.jd.com/")!
        case .mi: return URL(string: "https://m.mi.com/")!
        case .manual: return URL(string: "https://example.com")!
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "hand.tap").foregroundColor(theme.sub)
                    Text("在下方页面登录 \(platform.short)，登录后点「完成」")
                        .font(.system(size: 12)).foregroundColor(theme.sub)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(theme.card)
                LoginWeb(bridge: bridge, url: startURL)
            }
            .navigationTitle("登录 \(platform.short)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(done ? "处理中…" : "完成") {
                        guard !done else { return }
                        done = true
                        finish()
                    }
                    .disabled(done)
                }
            }
            .alert("还没检测到登录态", isPresented: $failedLogin) {
                Button("再试试", role: .cancel) {}
            } message: {
                Text("请先在页面里完成登录（可能需要短信验证），再点「完成」")
            }
        }
        .preferredColorScheme(theme.dark ? .dark : .light)
    }

    private func finish() {
        bridge.cookies { cookies in
            if LoginCheck.loggedIn(cookies, platform) {
                let uid = LoginCheck.uid(cookies, platform)
                let acc = AccountInfo(nick: platform.short + " 账号", uid: uid)
                onDone(ScrapeResult(account: acc))
                dismiss()
            } else {
                done = false
                failedLogin = true
            }
        }
    }
}

struct LoginWeb: UIViewRepresentable {
    let bridge: LoginBridge
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        bridge.web.load(URLRequest(url: url))
        return bridge.web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
