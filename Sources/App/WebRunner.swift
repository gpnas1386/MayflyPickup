import Foundation
import WebKit

struct ScrapeResult {
    var pickups: [PickupItem] = []
    var identity: String = ""
    var nick: String = ""
    var account: AccountInfo?
    var pageText: String = ""
    /// 每一步的抓取诊断（写入运行日志，便于排查）
    var debug: [String] = []
}

enum LoginCheck {
    static func loggedIn(_ cookies: [HTTPCookie], _ p: Platform) -> Bool {
        let names = Set(cookies.map { $0.name })
        switch p {
        // 只认真实登录 Cookie；cookie2/_m_h5_tk/_tb_token_ 等访客 Cookie 未登录也存在，会造成假"已登录"
        case .taobao: return names.contains("unb") || names.contains("_nk_") || names.contains("lgc") || names.contains("tracknick") || names.contains("dnk") || names.contains("skt") || names.contains("csg")
        // 注意：api_uid 是访客追踪 Cookie，未登录也存在，不能作为登录依据
        case .pdd: return names.contains("pdd_user_id") || names.contains("PDDAccessToken")
        case .jd: return names.contains("pt_key") || names.contains("pt_pin")
        case .mi: return names.contains("cUserId") || names.contains("passToken") || names.contains("userId")
        case .manual: return false
        }
    }

    static func uid(_ cookies: [HTTPCookie], _ p: Platform) -> String {
        func val(_ n: String) -> String { cookies.first { $0.name == n }?.value ?? "" }
        switch p {
        case .taobao: return val("unb").isEmpty ? val("_nk_") : val("unb")
        case .pdd: return val("pdd_user_id").isEmpty ? val("api_uid") : val("pdd_user_id")
        case .jd: return val("pt_pin")
        case .mi: return val("cUserId").isEmpty ? val("userId") : val("cUserId")
        case .manual: return ""
        }
    }
}

extension Platform {
    /// 各平台的登录 Cookie 域
    var cookieHosts: [String] {
        switch self {
        case .taobao: return ["taobao.com", "tmall.com", "cainiao.com", "alicdn.com"]
        case .pdd: return ["pinduoduo.com", "yangkeduo.com"]
        case .jd: return ["jd.com", "jd.hk", "360buy.com"]
        case .mi: return ["mi.com", "xiaomi.com", "miui.com"]
        case .manual: return []
        }
    }
}

/// 直接在默认 Cookie 仓上清除指定域的 Cookie（无需创建 WebView）
enum CookieCleaner {
    static func clear(hosts: [String]) async {
        let store = WKWebsiteDataStore.default().httpCookieStore
        let all = await withCheckedContinuation { (c: CheckedContinuation<[HTTPCookie], Never>) in
            store.getAllCookies { c.resume(returning: $0) }
        }
        for cookie in all where hosts.contains(where: { cookie.domain.contains($0) }) {
            await withCheckedContinuation { (con: CheckedContinuation<Void, Never>) in
                store.delete(cookie) { con.resume() }
            }
        }
    }
}

/// 隐藏 WKWebView 执行器：复用 App 默认 Cookie 仓，登录态与登录页共享
@MainActor
final class WebRunner: NSObject, WKNavigationDelegate, WKScriptMessageHandler, WKUIDelegate {
    private var web: WKWebView!
    private var loadWaiter: CheckedContinuation<Void, Never>?
    private var payloads: [(kind: String, json: String)] = []
    private static let ua = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Mobile/15E148 Safari/604.1"

    override init() {
        super.init()
        // 关键：WKWebView 初始化时会拷贝 configuration，
        // 之后对 cfg 的修改（注入脚本/注册消息桥）不会生效，必须先配置再创建 WebView
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        cfg.userContentController.add(self, name: "mayfly")
        cfg.userContentController.addUserScript(
            WKUserScript(source: ScrapeScripts.bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: cfg)
        web.navigationDelegate = self
        web.uiDelegate = self
        web.customUserAgent = Self.ua
    }

    func dispose() {
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: "mayfly")
        web.navigationDelegate = nil
    }

    // MARK: - 基础动作

    func load(_ url: URL, timeout: TimeInterval = 30) async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            loadWaiter = c
            var req = URLRequest(url: url)
            req.timeoutInterval = timeout
            req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Mobile/15E148 Safari/604.1", forHTTPHeaderField: "User-Agent")
            req.setValue("zh-CN,zh;q=0.9", forHTTPHeaderField: "Accept-Language")
            web.load(req)
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.finishLoad()
            }
        }
    }

    private func finishLoad() {
        if let c = loadWaiter { loadWaiter = nil; c.resume() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishLoad() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishLoad() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishLoad() }

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
    func eval(_ js: String) async -> String {
        let v = try? await web.evaluateJavaScript(js)
        if let s = v as? String { return s }
        if let v = v { return "\(v)" }
        return ""
    }

    func waitPayload(kind: String, timeout: TimeInterval = 12) async -> String? {
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

    func cookies() async -> [HTTPCookie] {
        await withCheckedContinuation { (c: CheckedContinuation<[HTTPCookie], Never>) in
            web.configuration.websiteDataStore.httpCookieStore.getAllCookies { list in c.resume(returning: list) }
        }
    }

    func clearCookies(_ p: Platform) async {
        await CookieCleaner.clear(hosts: p.cookieHosts)
    }

    private func account(_ p: Platform) async -> AccountInfo? {
        let ck = await cookies()
        guard LoginCheck.loggedIn(ck, p) else { return nil }
        var nick = await eval("(function(){try{return localStorage.getItem('nick')||localStorage.getItem('user_nick')||localStorage.getItem('userInfo')||''}catch(e){return ''}})()")
        if nick.count > 60 { nick = String(nick.prefix(60)) }
        if nick.isEmpty {
            let title = await eval("document.title || ''")
            if !title.isEmpty && title.count < 30 { nick = title }
        }
        let uid = LoginCheck.uid(ck, p)
        return AccountInfo(nick: nick.isEmpty ? p.short + "账号" : nick, uid: uid)
    }

    // MARK: - 平台流程

    /// 汇总当前相关域名的 Cookie 名（诊断用，不含值）
    func cookieDebug(_ hosts: [String]) async -> String {
        let ck = await cookies()
        let names = Set(ck.filter { c in hosts.contains { c.domain.contains($0) } }.map { $0.name })
        let list = names.sorted().prefix(18)
        return list.isEmpty ? "无相关Cookie" : list.joined(separator: ",")
    }

    /// 把 page 载荷里的诊断信息并入 res.debug
    func pageDebug(_ obj: [String: Any], _ res: inout ScrapeResult) {
        if let d = obj["dbg"] as? [String: Any] {
            res.debug.append("hook=\(d["inst"] ?? "?") cap=\(d["capN"] ?? 0) title=\(d["title"] ?? "")")
            if let urls = d["capUrls"] as? [String], !urls.isEmpty {
                res.debug.append("capUrls=" + urls.joined(separator: " | "))
            }
        }
        if let u = obj["url"] as? String { res.debug.append("url=\(u)") }
        let head = String(res.pageText.prefix(220)).replacingOccurrences(of: "\n", with: " / ")
        res.debug.append("textHead=\(head)")
    }

    func taobaoPass(waybills: [String]) async -> ScrapeResult {
        var res = ScrapeResult()
        // 注意：m.cainiao.com 根路径是广告跳转页，会立即重定向到淘宝营销页；
        // 真正的菜鸟 H5 包裹列表在 page.cainiao.com（自带 lib.mtop 与登录组件）
        await load(URL(string: "https://page.cainiao.com/mcn/union-post/index.html#/order-list")!)
        try? await Task.sleep(nanoseconds: 5_000_000_000)
        res.account = await account(.taobao)
        res.debug.append("cookie=" + (await cookieDebug(["taobao.com", "cainiao.com"])))

        // 未登录时会被重定向到淘宝登录页，直接短路返回，避免空耗 30 秒
        let curURL = await eval("(function(){return String(location.href||'')})()")
        if curURL.contains("//login.") || curURL.contains("passport") {
            res.debug.append("未登录（停在登录页），请到「我的→账号」完成淘宝真实登录后再抓取")
            return res
        }

        let phone = await eval("(function(){var t=(document.body&&document.body.innerText)||'';var m=t.match(/1\\d{10}/);return m?m[0]:''})()")
        res.debug.append("phone=\(phone.isEmpty ? "未识别" : phone)")
        await eval(ScrapeScripts.tbIdentity)
        if let payload = await waitPayload(kind: "identity", timeout: 10),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.identity = DeepScan.identityCode(in: obj)
            if let err = obj["err"] as? String { res.debug.append("identityErr=\(err)") }
        } else {
            res.debug.append("identity=响应超时")
        }

        if !waybills.isEmpty || !phone.isEmpty {
            await eval(ScrapeScripts.tbPackages(waybills: waybills, phone: phone))
            if let payload = await waitPayload(kind: "packages", timeout: 16),
               let data = payload.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                res.pickups.append(contentsOf: DeepScan.pickups(fromJSON: obj, source: .taobao))
                if let err = obj["err"] as? String {
                    res.debug.append("packagesErr=\(err)")
                } else if let rows = obj["rows"] as? [[String: Any]] {
                    for r in rows.prefix(8) {
                        res.debug.append("mtop[\(r["tag"] ?? "?")]=ok:\(r["ok"] ?? false) ret=\(r["ret"] ?? "")")
                    }
                }
            } else {
                res.debug.append("packages=响应超时")
            }
        }

        // 滚动触发包裹列表懒加载
        await eval("(function(){try{window.scrollTo(0,document.body?document.body.scrollHeight:0)}catch(e){}})()")
        try? await Task.sleep(nanoseconds: 2_000_000_000)

        await eval(ScrapeScripts.dumpPage)
        if let payload = await waitPayload(kind: "page", timeout: 12),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.pageText = obj["text"] as? String ?? ""
            res.pickups.append(contentsOf: DeepScan.pickups(fromCapture: obj, source: .taobao))
            res.pickups.append(contentsOf: PickupParser.parse(res.pageText, source: .taobao))
            if let cap = obj["cap"] as? [[String: Any]] {
                for c in cap {
                    let body = c["b"] as? String ?? ""
                    res.pickups.append(contentsOf: PickupParser.parse(body, source: .taobao))
                }
            }
            pageDebug(obj, &res)
        } else {
            res.debug.append("page=响应超时")
        }
        res.pickups = DeepScan.dedupe(res.pickups)
        return res
    }

    func pddPass() async -> ScrapeResult {
        var res = ScrapeResult()
        await load(URL(string: "https://m.pinduoduo.net/mdkd/package")!)
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        res.account = await account(.pdd)
        res.debug.append("cookie=" + (await cookieDebug(["pinduoduo.com", "yangkeduo.com"])))

        // 被踢到登录页说明 Cookie 里的 Token 已失效（服务器返回 pdduid=0）：
        // 清掉旧 Cookie，提示重新登录，避免空转
        let pddURL = await eval("(function(){return String(location.href||'')})()")
        if pddURL.contains("login.html") || pddURL.contains("//login.") || pddURL.contains("passport") {
            res.debug.append("登录态失效（旧 Token 被服务器拒绝），已清除旧 Cookie，请到「我的→账号」重新登录")
            await clearCookies(.pdd)
            return res
        }

        // 滚动到底再回顶，触发快递列表的懒加载与接口请求（抓包钩子会记录响应）
        await eval("(function(){try{window.scrollTo(0,document.body?document.body.scrollHeight:0)}catch(e){}})()")
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        await eval("(function(){try{window.scrollTo(0,0)}catch(e){}})()")
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        await eval(ScrapeScripts.dumpPage)
        if let payload = await waitPayload(kind: "page", timeout: 12),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.pageText = obj["text"] as? String ?? ""
            res.pickups.append(contentsOf: DeepScan.pickups(fromCapture: obj, source: .pdd))
            res.pickups.append(contentsOf: PickupParser.parse(res.pageText, source: .pdd))
            if let cap = obj["cap"] as? [[String: Any]] {
                for c in cap {
                    let body = c["b"] as? String ?? ""
                    res.pickups.append(contentsOf: PickupParser.parse(body, source: .pdd))
                }
            }
            pageDebug(obj, &res)
        } else {
            res.debug.append("page=响应超时")
        }
        res.pickups = DeepScan.dedupe(res.pickups)
        return res
    }

    func jdPass() async -> ScrapeResult {
        var res = ScrapeResult()
        let url = URL(string: "https://trade.m.jd.com/order/orderlist_jdm.shtml?source=m_outer_jx_order")!
        await load(url)
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        res.account = await account(.jd)
        res.debug.append("cookie=" + (await cookieDebug(["jd.com", "360buy.com"])))
        let jdURL = await eval("(function(){return String(location.href||'')})()")
        if jdURL.contains("//login.") || jdURL.contains("passport") {
            res.debug.append("登录态失效，请到「我的→账号」重新登录京东")
            await clearCookies(.jd)
            return res
        }
        await eval(ScrapeScripts.dumpPage)
        if let payload = await waitPayload(kind: "page", timeout: 12),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.pageText = obj["text"] as? String ?? ""
            res.pickups.append(contentsOf: DeepScan.pickups(fromCapture: obj, source: .jd))
            res.pickups.append(contentsOf: PickupParser.parse(res.pageText, source: .jd))
            pageDebug(obj, &res)
        } else {
            res.debug.append("page=响应超时")
        }
        res.pickups = DeepScan.dedupe(res.pickups)
        return res
    }

    func miPass() async -> ScrapeResult {
        var res = ScrapeResult()
        await load(URL(string: "https://m.mi.com/order_list?type=2")!)
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        res.account = await account(.mi)
        res.debug.append("cookie=" + (await cookieDebug(["mi.com", "xiaomi.com"])))
        let miURL = await eval("(function(){return String(location.href||'')})()")
        if miURL.contains("//login.") || miURL.contains("passport") || miURL.contains("/login") {
            res.debug.append("登录态失效，请到「我的→账号」重新登录小米")
            await clearCookies(.mi)
            return res
        }
        await eval(ScrapeScripts.dumpPage)
        if let payload = await waitPayload(kind: "page", timeout: 12),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.pageText = obj["text"] as? String ?? ""
            res.pickups.append(contentsOf: PickupParser.parse(res.pageText, source: .mi))
            res.pickups.append(contentsOf: DeepScan.pickups(fromCapture: obj, source: .mi))
            pageDebug(obj, &res)
        } else {
            res.debug.append("page=响应超时")
        }
        res.pickups = DeepScan.dedupe(res.pickups)
        return res
    }

    /// 新窗口跳转（target=_blank，常见于淘宝/拼多多登录按钮）在同一 WebView 内打开，
    /// 否则点击无任何反应 / 登录浮层叠在原页面上
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, !url.absoluteString.isEmpty {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}
