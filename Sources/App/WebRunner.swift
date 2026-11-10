import Foundation
import WebKit

struct ScrapeResult {
    var pickups: [PickupItem] = []
    var identity: String = ""
    var nick: String = ""
    var account: AccountInfo?
    var pageText: String = ""
}

enum LoginCheck {
    static func loggedIn(_ cookies: [HTTPCookie], _ p: Platform) -> Bool {
        let names = Set(cookies.map { $0.name })
        switch p {
        case .taobao: return names.contains("unb") || names.contains("cookie2") || names.contains("_m_h5_tk") || names.contains("_nk_")
        case .pdd: return names.contains("pdd_user_id") || names.contains("PDDAccessToken") || names.contains("api_uid")
        case .jd: return names.contains("pt_key") || names.contains("pt_pin")
        case .mi: return names.contains("cUserId") || names.contains("passToken") || names.contains("userId")
        case .manual: return false
        }
    }

    static func uid(_ cookies: [HTTPCookie], _ p: Platform) -> String {
        func val(_ n: String) -> String { cookies.first { $0.name == n }?.value ?? "" }
        switch p {
        case .taobao: return val("unb").isEmpty ? val("cookie2") : val("unb")
        case .pdd: return val("pdd_user_id").isEmpty ? val("api_uid") : val("pdd_user_id")
        case .jd: return val("pt_pin")
        case .mi: return val("cUserId").isEmpty ? val("userId") : val("cUserId")
        case .manual: return ""
        }
    }
}

/// 隐藏 WKWebView 执行器：复用 App 默认 Cookie 仓，登录态与登录页共享
@MainActor
final class WebRunner: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    private let web: WKWebView
    private var loadWaiter: CheckedContinuation<Void, Never>?
    private var payloads: [(kind: String, json: String)] = []

    override init() {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: cfg)
        super.init()
        cfg.userContentController.add(self, name: "mayfly")
        cfg.userContentController.addUserScript(
            WKUserScript(source: ScrapeScripts.bootstrap, injectionTime: .atDocumentStart, forMainFrameOnly: false))
        web.navigationDelegate = self
        web.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 16_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.1 Mobile/15E148 Safari/604.1"
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
        let all = await cookies()
        let store = web.configuration.websiteDataStore.httpCookieStore
        let hosts: [String]
        switch p {
        case .taobao: hosts = ["taobao.com", "tmall.com", "cainiao.com", "alicdn.com"]
        case .pdd: hosts = ["pinduoduo.com", "yangkeduo.com"]
        case .jd: hosts = ["jd.com", "jd.hk", "360buy.com"]
        case .mi: hosts = ["mi.com", "xiaomi.com", "miui.com"]
        case .manual: hosts = []
        }
        for c in all where hosts.contains(where: { c.domain.contains($0) }) {
            await withCheckedContinuation { (con: CheckedContinuation<Void, Never>) in
                store.delete(c) { con.resume() }
            }
        }
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

    func taobaoPass(waybills: [String]) async -> ScrapeResult {
        var res = ScrapeResult()
        await load(URL(string: "https://m.cainiao.com/")!)
        try? await Task.sleep(nanoseconds: 3_500_000_000)
        res.account = await account(.taobao)

        let phone = await eval("(function(){var t=(document.body&&document.body.innerText)||'';var m=t.match(/1\\d{10}/);return m?m[0]:''})()")
        await eval(ScrapeScripts.tbIdentity)
        if let payload = await waitPayload(kind: "identity", timeout: 10),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.identity = DeepScan.identityCode(obj)
        }

        if !waybills.isEmpty || !phone.isEmpty {
            await eval(ScrapeScripts.tbPackages(waybills: waybills, phone: phone))
            if let payload = await waitPayload(kind: "packages", timeout: 16),
               let data = payload.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                res.pickups.append(contentsOf: DeepScan.pickups(fromJSON: obj, source: .taobao))
            }
        }

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
        }
        res.pickups = DeepScan.dedupe(res.pickups)
        return res
    }

    func pddPass() async -> ScrapeResult {
        var res = ScrapeResult()
        await load(URL(string: "https://m.pinduoduo.net/mdkd/package")!)
        try? await Task.sleep(nanoseconds: 7_000_000_000)
        res.account = await account(.pdd)

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
        await eval(ScrapeScripts.dumpPage)
        if let payload = await waitPayload(kind: "page", timeout: 12),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.pageText = obj["text"] as? String ?? ""
            res.pickups.append(contentsOf: DeepScan.pickups(fromCapture: obj, source: .jd))
            res.pickups.append(contentsOf: PickupParser.parse(res.pageText, source: .jd))
        }
        res.pickups = DeepScan.dedupe(res.pickups)
        return res
    }

    func miPass() async -> ScrapeResult {
        var res = ScrapeResult()
        await load(URL(string: "https://m.mi.com/order_list?type=2")!)
        try? await Task.sleep(nanoseconds: 6_000_000_000)
        res.account = await account(.mi)
        await eval(ScrapeScripts.dumpPage)
        if let payload = await waitPayload(kind: "page", timeout: 12),
           let data = payload.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            res.pageText = obj["text"] as? String ?? ""
            res.pickups.append(contentsOf: PickupParser.parse(res.pageText, source: .mi))
            res.pickups.append(contentsOf: DeepScan.pickups(fromCapture: obj, source: .mi))
        }
        res.pickups = DeepScan.dedupe(res.pickups)
        return res
    }
}
