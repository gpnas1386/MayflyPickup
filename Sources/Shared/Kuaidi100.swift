import Foundation
import CryptoKit

public struct Kd100Result {
    public var com: String
    public var comName: String
    public var nu: String
    public var state: Int
    public var statusText: String
    public var traces: [Trace]
    public var ok: Bool
    public var message: String
}

public enum Kuaidi100 {
    static let freeAuto = "https://www.kuaidi100.com/autonumber/auto"
    static let freeQuery = "https://www.kuaidi100.com/query"
    static let paidQuery = "https://poll.kuaidi100.com/poll/query.do"

    public static let carrierNames: [String: String] = [
        "shunfeng": "顺丰", "zhongtong": "中通", "yuantong": "圆通", "yunda": "韵达",
        "shentong": "申通", "jtexpress": "极兔", "jd": "京东", "ems": "EMS",
        "youzhengguonei": "邮政", "debangwuliu": "德邦", "baishiwuliu": "百世",
        "huitongkuaidi": "百世", "tiantian": "天天", "zhaijisong": "宅急送",
        "kuaijiesudi": "快捷", "annengwuliu": "安能", "suer": "速尔", "youzhengbk": "邮政包裹",
        "fengwang": "丰网", "zhongtongkuaiyun": "中通快运", "quanfengkuaidi": "全峰",
        "youshuwuliu": "优速", "danniao": "丹鸟", "cainiao": "菜鸟"
    ]

    static let prefixMap: [(String, String)] = [
        ("JDVA", "京东"), ("JDVB", "京东"), ("JDVC", "京东"), ("JD", "京东"),
        ("SF", "顺丰"), ("JT", "极兔"), ("ZTO", "中通"), ("STO", "申通"),
        ("YT", "圆通"), ("YD", "韵达"), ("DPK", "德邦"), ("DBL", "德邦"),
        ("HTKY", "百世"), ("BSHT", "百世"), ("FW", "丰网"), ("CN", "菜鸟"),
        ("TT", "天天"), ("UC", "优速"), ("KY", "跨越"), ("ZJS", "宅急送"),
        ("SUER", "速尔"), ("ANE", "安能"), ("EMS", "EMS")
    ]

    public static func carrierByPrefix(_ nu: String) -> String {
        let u = nu.uppercased()
        for (p, name) in prefixMap where u.hasPrefix(p) { return name }
        return ""
    }

    public static func isValidWaybill(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.count >= 8, t.count <= 32 else { return false }
        let set = CharacterSet.alphanumerics
        return t.unicodeScalars.allSatisfy { set.contains($0) }
    }

    /// 从任意文本里抓运单号（短信/复制内容）
    public static func extractWaybills(_ text: String) -> [String] {
        let pattern = "[A-Za-z]{0,4}[0-9]{8,22}"
        guard let re = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = text as NSString
        var out: [String] = []
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            var s = ns.substring(with: m.range)
            s = s.uppercased()
            if !out.contains(s) { out.append(s) }
        }
        // 纯数字 8-22 位也算
        if let re2 = try? NSRegularExpression(pattern: "\\b[0-9]{10,22}\\b") {
            for m in re2.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                let s = ns.substring(with: m.range)
                if !out.contains(s) { out.append(s) }
            }
        }
        return out
    }

    static func md5(_ s: String) -> String {
        let d = Insecure.MD5.hash(data: Data(s.utf8))
        return d.map { String(format: "%02x", $0) }.joined()
    }

    static func get(_ url: String, timeout: TimeInterval = 12) async -> Data? {
        guard let u = URL(string: url) else { return nil }
        var req = URLRequest(url: u)
        req.timeoutInterval = timeout
        req.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_1_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148", forHTTPHeaderField: "User-Agent")
        req.setValue("https://m.kuaidi100.com/", forHTTPHeaderField: "Referer")
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return data
        } catch {
            return nil
        }
    }

    static func detect(_ nu: String, key: String) async -> String? {
        var url = "\(freeAuto)?num=\(nu.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? nu)"
        if !key.isEmpty { url += "&key=\(key)" }
        guard let data = await get(url) else { return nil }
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = arr.first, let code = first["comCode"] as? String, !code.isEmpty else { return nil }
        return code
    }

    /// 免费通道（自动识别 + 查询），无需 key
    public static func queryFree(_ nu: String, com: String? = nil, key: String = "") async -> Kd100Result {
        var comCode = com ?? ""
        if comCode.isEmpty { comCode = await detect(nu, key: key) ?? "" }
        guard !comCode.isEmpty else {
            return Kd100Result(com: "", comName: carrierByPrefix(nu), nu: nu, state: -1,
                               statusText: "未识别快递公司", traces: [], ok: false, message: "autonumber empty")
        }
        let temp = String(format: "%.6f", Double.random(in: 0.1...0.9))
        let url = "\(freeQuery)?type=\(comCode)&postid=\(nu)&temp=\(temp)&phone="
        guard let data = await get(url) else {
            return Kd100Result(com: comCode, comName: carrierNames[comCode] ?? carrierByPrefix(nu), nu: nu,
                               state: -1, statusText: "网络失败", traces: [], ok: false, message: "network")
        }
        return parse(data, comFallback: comCode, nu: nu)
    }

    /// 企业版（客户号 customer + 授权 key），官方凭据
    public static func queryPaid(_ nu: String, com: String, customer: String, key: String) async -> Kd100Result {
        guard !customer.isEmpty, !key.isEmpty else { return await queryFree(nu, com: com.isEmpty ? nil : com, key: key) }
        let paramObj: [String: Any] = ["com": com, "num": nu, "resultv2": "1", "show": "0"]
        guard let pdata = try? JSONSerialization.data(withJSONObject: paramObj, options: []),
              let param = String(data: pdata, encoding: .utf8) else {
            return Kd100Result(com: com, comName: "", nu: nu, state: -1, statusText: "参数错误", traces: [], ok: false, message: "param")
        }
        let sign = md5(param + key + customer).uppercased()
        guard let u = URL(string: paidQuery) else {
            return Kd100Result(com: com, comName: "", nu: nu, state: -1, statusText: "URL 错误", traces: [], ok: false, message: "url")
        }
        var req = URLRequest(url: u)
        req.httpMethod = "POST"
        req.timeoutInterval = 15
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "customer=\(customer)&sign=\(sign)&param=\(param.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? param)"
        req.httpBody = Data(body.utf8)
        do {
            let (data, _) = try await URLSession.shared.data(for: req)
            return parse(data, comFallback: com, nu: nu)
        } catch {
            return Kd100Result(com: com, comName: "", nu: nu, state: -1, statusText: "网络失败", traces: [], ok: false, message: "network")
        }
    }

    static func parse(_ data: Data, comFallback: String, nu: String) -> Kd100Result {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return Kd100Result(com: comFallback, comName: carrierNames[comFallback] ?? "", nu: nu,
                               state: -1, statusText: "解析失败", traces: [], ok: false, message: "json")
        }
        let status = (obj["status"] as? String) ?? ""
        let message = (obj["message"] as? String) ?? ""
        let com = (obj["com"] as? String) ?? comFallback
        let stateStr = (obj["state"] as? String) ?? "-1"
        let state = Int(stateStr) ?? -1
        var traces: [Trace] = []
        if let arr = obj["data"] as? [[String: Any]] {
            for d in arr {
                let time = (d["time"] as? String) ?? (d["ftime"] as? String) ?? ""
                let ctx = (d["context"] as? String) ?? ""
                if !ctx.isEmpty { traces.append(Trace(time: time, context: ctx)) }
            }
        }
        let ok = status == "200" && !traces.isEmpty
        var text = stateText(state)
        if let first = traces.first, !first.context.isEmpty, ok {
            text = shortStatus(first.context) ?? text
        }
        if !ok {
            if message.contains("查询无结果") || status == "201" { text = "暂无轨迹" }
            else if !message.isEmpty { text = message }
        }
        return Kd100Result(com: com, comName: carrierNames[com] ?? carrierByPrefix(nu), nu: nu,
                           state: state, statusText: text, traces: traces, ok: ok, message: message)
    }

    public static func stateText(_ state: Int) -> String {
        switch state {
        case 0: return "在途"
        case 1: return "已揽收"
        case 2: return "疑难件"
        case 3: return "已签收"
        case 4: return "退签"
        case 5: return "派送中"
        case 6: return "退回"
        case 7: return "转投"
        case 8: return "清关中"
        case 14: return "拒签"
        default: return "运输中"
        }
    }

    static func shortStatus(_ context: String) -> String? {
        let keys = ["已入柜", "已存放", "已到达", "已代收", "待取件", "派送中", "派件中", "已签收", "已揽收", "运输中", "已发货"]
        for k in keys where context.contains(k) { return k }
        return nil
    }
}
