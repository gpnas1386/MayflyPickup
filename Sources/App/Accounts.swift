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

final class LoginBridge: NSObject, ObservableObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    var web: WKWebView!
    private(set) var loadedStart: URL?
    private var payloads: [(kind: String, json: String)] = []

    override init() {
        super.init()
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        // 关键：必须先配置再创建 WebView（WKWebView 初始化时会拷贝 configuration）
        cfg.userContentController.add(self, name: "mayfly")
        cfg.userContentController.addUserScript(
            WKUserScript(source: ScrapeScripts.bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        web = WKWebView(frame: .zero, configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        // 关键：与隐藏抓取 WebView（WebRunner）使用完全相同的 UA，
        // 拼多多等平台会把登录态和 UA 指纹绑定，UA 不一致会被服务器判定会话无效（pdduid=0）
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Mobile/15E148 Safari/604.1"
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

    func cookiesAsync() async -> [HTTPCookie] {
        await withCheckedContinuation { (c: CheckedContinuation<[HTTPCookie], Never>) in
            web.configuration.websiteDataStore.httpCookieStore.getAllCookies { c.resume(returning: $0) }
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let s = "\(message.body)"
        if let d = s.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let kind = obj["t"] as? String {
            payloads.append((kind, s))
        } else {
            payloads.append(("raw", s))
        }
    }

    @discardableResult
    private func eval(_ js: String) async -> String {
        let v = try? await web.evaluateJavaScript(js)
        if let s = v as? String { return s }
        if let v = v { return "\(v)" }
        return ""
    }

    private func waitPayload(kind: String, timeout: TimeInterval = 12) async -> String? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let hit = payloads.last(where: { $0.kind == kind }) {
                payloads.removeAll { $0.kind == kind }
                return hit.json
            }
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        return nil
    }

    /// 登录成功后，直接在登录同一个 WebView 里完成抓取：
    /// Cookie / UA / 会话 / 指纹全程一致，规避拼多多等平台「换 WebView 就掉登录」的风控
    @MainActor
    func scrapePass(_ p: Platform) async -> ScrapeResult {
        var res = ScrapeResult()
        guard let target = p.scrapeURL else { return res }

        let ck = await cookiesAsync()
        if LoginCheck.loggedIn(ck, p) {
            res.account = AccountInfo(nick: p.short + " 账号", uid: LoginCheck.uid(ck, p))
        }
        let names = Set(ck.filter { c in p.cookieHosts.contains { c.domain.contains($0) } }.map { $0.name }).sorted().prefix(18)
        res.debug.append("cookie=" + (names.isEmpty ? "无相关Cookie" : names.joined(separator: ",")))

        // 若当前页面已经在抓取目标页上（用户手动导航过去），不要重载——
        // 重载可能触发二次跳登录/风控，直接抓当前页
        let cur = await eval("(function(){return String(location.href||'')})()")
        let host = target.host ?? ""
        let onTarget = cur.contains(host) && cur.contains(target.path) && !cur.contains("login")
        if !onTarget {
            web.load(URLRequest(url: target))
            try? await Task.sleep(nanoseconds: 8_000_000_000)
        }

        let cur2 = await eval("(function(){return String(location.href||'')})()")
        res.debug.append("url=\(cur2)")
        if cur2.contains("login.html") || cur2.contains("//login.") || cur2.contains("passport") {
            res.debug.append("仍在登录页，未抓取（请确认页面已完成登录）")
            return res
        }

        // 拼多多等懒加载列表：滚动到底再回顶，触发接口请求
        await eval("(function(){try{window.scrollTo(0,document.body?document.body.scrollHeight:0)}catch(e){}})()")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await eval("(function(){try{window.scrollTo(0,0)}catch(e){}})()")
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await eval(ScrapeScripts.dumpPage)
        if let payload = await waitPayload(kind: "page", timeout: 12),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.pageText = obj["text"] as? String ?? ""
            res.pickups.append(contentsOf: DeepScan.pickups(fromCapture: obj, source: p))
            res.pickups.append(contentsOf: PickupParser.parse(res.pageText, source: p))
            if let cap = obj["cap"] as? [[String: Any]] {
                res.debug.append("cap=\(cap.count)")
                for c in cap {
                    res.pickups.append(contentsOf: PickupParser.parse(c["b"] as? String ?? "", source: p))
                }
            }
            let head = String(res.pageText.prefix(200)).replacingOccurrences(of: "\n", with: " / ")
            res.debug.append("textHead=\(head)")
        } else {
            res.debug.append("page=响应超时")
        }

        // 第二轮：给懒加载接口更多时间，__cap 会累积此前的所有响应，再解析一次
        try? await Task.sleep(nanoseconds: 3_000_000_000)
        await eval(ScrapeScripts.dumpPage)
        if let payload = await waitPayload(kind: "page", timeout: 10),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let moreText = obj["text"] as? String ?? ""
            if moreText.count > res.pageText.count { res.pageText = moreText }
            res.pickups.append(contentsOf: DeepScan.pickups(fromCapture: obj, source: p))
            res.pickups.append(contentsOf: PickupParser.parse(res.pageText, source: p))
            if let cap = obj["cap"] as? [[String: Any]] {
                res.debug.append("cap2=\(cap.count)")
                for c in cap {
                    res.pickups.append(contentsOf: PickupParser.parse(c["b"] as? String ?? "", source: p))
                }
            }
        }
        res.pickups = DeepScan.dedupe(res.pickups)
        return res
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
                Task { @MainActor in
                    // 在登录同一个 WebView 里直接抓取（Cookie/UA/会话一致，规避风控）
                    var res = await bridge.scrapePass(platform)
                    if res.account == nil {
                        res.account = AccountInfo(nick: platform.short + " 账号", uid: uid)
                    }
                    onDone(res)
                    dismiss()
                }
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
