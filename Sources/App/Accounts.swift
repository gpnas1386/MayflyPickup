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

final class LoginBridge: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let web: WKWebView
    private(set) var loadedStart: URL?

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        web = WKWebView(frame: .zero, configuration: cfg)
        super.init()
        web.navigationDelegate = self
        web.uiDelegate = self
    }

    /// 同一登录页只加载一次，避免 SwiftUI 重建视图时叠加导航
    func start(_ url: URL) {
        guard loadedStart != url else { return }
        loadedStart = url
        web.load(URLRequest(url: url))
    }

    func cookies(_ done: @escaping ([HTTPCookie]) -> Void) {
        web.configuration.websiteDataStore.httpCookieStore.getAllCookies { done($0) }
    }

    /// 新窗口跳转（target=_blank，如淘宝登录面板）在同一 WebView 内打开，
    /// 否则点击登录按钮无反应，登录浮层叠在原页面上
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
            webView.load(URLRequest(url: url))
        }
        return nil
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
        // m.cainiao.com 根路径是广告跳转页；菜鸟正式 H5（含登录组件与包裹列表）在这里
        case .taobao: return URL(string: "https://page.cainiao.com/mcn/union-post/index.html#/order-list")!
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
                    Text("在下方页面登录 \(platform.short)（登录面板可能整页跳转），登录后点「完成」；页面显示异常可点右上角 ↻ 刷新")
                        .font(.system(size: 12)).foregroundColor(theme.sub)
                    Spacer()
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(theme.card)
                if platform == .taobao {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle").foregroundColor(theme.sub)
                        Text("若「本机号码一键登录」不可用，请点「换个登录方式」改用短信验证码登录，登录完成会自动回到包裹列表")
                            .font(.system(size: 11)).foregroundColor(theme.sub)
                        Spacer()
                    }
                    .padding(.horizontal, 14).padding(.bottom, 8)
                    .background(theme.card)
                }
                LoginWeb(bridge: bridge, url: startURL, platform: platform)
            }
            .navigationTitle("登录 \(platform.short)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        bridge.web.reload()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
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
    let platform: Platform

    func makeUIView(context: Context) -> WKWebView {
        // 先清掉该平台的旧 Cookie（可能是失效/残留 Token，会导致"看着已登录实际没登录"），
        // 再加载登录页，确保这次拿到全新有效 Token
        Task { @MainActor in
            await CookieCleaner.clear(hosts: platform.cookieHosts)
            bridge.start(url)
        }
        return bridge.web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
