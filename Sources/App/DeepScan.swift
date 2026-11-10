import Foundation

/// 把各平台 JSON 捕获体深挖成取件码条目
enum DeepScan {
    static let codeKeys = ["pickupCode", "pickup_code", "identificationCode", "shelfNo", "gridNo",
                           "cabinetNo", "pickupNo", "code", "selfPickupCode", "pickCode"]
    static let waybillKeys = ["waybillNo", "mailNo", "trackingNumber", "waybillCode", "expressNo",
                              "expressCode", "waybill", "mailNum", "billCode"]
    static let stationKeys = ["stationName", "station", "selfPickupSiteName", "spotName",
                              "pickupPointName", "siteName", "cabinetName", "pointName"]
    static let goodsKeys = ["goodsName", "productName", "skuName", "itemName", "orderTitle", "title"]

    static func pickups(fromJSON obj: Any?, source: Platform, limit: Int = 60) -> [PickupItem] {
        var out: [PickupItem] = []
        var seen = Set<String>()
        walk(obj) { dict in
            guard out.count < limit else { return }
            var code = ""
            for k in codeKeys {
                if let v = dict[k] as? String, !v.isEmpty { code = v.uppercased(); break }
                if let v = dict[k] as? NSNumber { code = v.stringValue; break }
            }
            var wb = ""
            for k in waybillKeys {
                if let v = dict[k] as? String, !v.isEmpty { wb = v.uppercased(); break }
            }
            guard !code.isEmpty, code.count >= 3, !code.hasPrefix("http") else { return }
            let station = (dict[stationKeys.first { dict[$0] != nil } ?? ""] as? String) ?? ""
            let goods = (dict[goodsKeys.first { dict[$0] != nil } ?? ""] as? String) ?? ""
            let id = "\(source.rawValue)-\(wb.isEmpty ? code : wb)-\(station)-\(code)"
            guard seen.insert(id).inserted else { return }
            let item = PickupItem(id: id, waybillNo: wb, code: code,
                                  stationName: String(station.prefix(24)),
                                  stationText: "", goodsName: String(goods.prefix(40)),
                                  source: source)
            out.append(item)
        }
        return out
    }

    static func pickups(fromCaptureBody body: String, source: Platform) -> [PickupItem] {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        var obj: Any?
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            obj = try? JSONSerialization.jsonObject(with: Data(trimmed.utf8))
        } else if let re = try? NSRegularExpression(pattern: #"^[A-Za-z0-9_$.]+\((.*)\);?\s*$"#, options: [.dotMatchesLineSeparators]),
                  let m = re.firstMatch(in: trimmed, range: NSRange(location: 0, length: (trimmed as NSString).length)) {
            let inner = (trimmed as NSString).substring(with: m.range(at: 1))
            obj = try? JSONSerialization.jsonObject(with: Data(inner.utf8))
        }
        guard obj != nil else { return PickupParser.parse(body, source: source) }
        return pickups(fromJSON: obj, source: source)
    }

    static func identityCode(in obj: Any?) -> String {
        var found = ""
        let re = try? NSRegularExpression(pattern: #"(\d{1,2})-(\d{1,2})-(\d{3,5})"#)
        walk(obj) { dict in
            guard found.isEmpty else { return }
            for k in ["identityCode", "code", "pickupCode", "identityMessage"] {
                if let v = dict[k] as? String, !v.isEmpty {
                    if v.contains("-"), let m = re?.firstMatch(in: v, range: NSRange(location: 0, length: (v as NSString).length)) {
                        found = (v as NSString).substring(with: m.range)
                        return
                    }
                    if v.count <= 12, !v.contains("/") { found = v }
                }
            }
        }
        return found
    }

    static func findNick(in obj: Any?) -> String {
        var nick = ""
        walk(obj) { dict in
            guard nick.isEmpty else { return }
            for k in ["nick", "nickname", "userName", "memberName", "userNick"] {
                if let v = dict[k] as? String, !v.isEmpty {
                    nick = String(v.prefix(24))
                    return
                }
            }
        }
        return nick
    }

    static func dedupe(_ items: [PickupItem]) -> [PickupItem] {
        var seen = Set<String>()
        var out: [PickupItem] = []
        for it in items {
            let key = it.source + "#" + it.code + "#" + it.waybillNo
            if seen.insert(key).inserted { out.append(it) }
        }
        return out
    }

    static func walk(_ any: Any?, _ visit: ([String: Any]) -> Void) {
        if let arr = any as? [Any] {
            for a in arr.prefix(200) { walk(a, visit) }
        } else if let dict = any as? [String: Any] {
            visit(dict)
            for (_, v) in dict.prefix(60) { walk(v, visit) }
        }
    }
}
