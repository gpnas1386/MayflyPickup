import Foundation

/// 文本 → 取件码 / 驿站 解析（复用 1.3 版的判定规则）
public enum PickupParser {
    public static let codeLabelPattern = #"(取件码|取货码|提货码|自提码|驿站码|取件验证码|取件号)\s*[:：]?\s*([A-Za-z0-9][A-Za-z0-9\-]{1,14})"#
    public static let codeBarePattern = #"(?<![0-9A-Za-z])(\d{1,2}-\d{1,2}-\d{3,5})(?![0-9A-Za-z])"#
    public static let stationKeys = ["驿站", "快递柜", "服务站", "代收点", "自提点", "便利店", "超市", "快递超市", "小蜜蜂", "菜鸟"]
    public static let arrivalKeys = ["已到达", "已入柜", "已存放", "已代收", "待取件", "请凭取件码", "凭取件码", "已放至", "到了驿站"]
    public static let pickedKeys = ["已取出", "已取件", "已签收", "已完成取件"]

    public static func codes(in text: String) -> [String] {
        var out: [String] = []
        if let re = try? NSRegularExpression(pattern: codeLabelPattern) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges >= 3 {
                let c = ns.substring(with: m.range(at: 2)).uppercased()
                if !out.contains(c) { out.append(c) }
            }
        }
        if let re = try? NSRegularExpression(pattern: codeBarePattern) {
            let ns = text as NSString
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) where m.numberOfRanges >= 2 {
                let c = ns.substring(with: m.range(at: 1)).uppercased()
                if !out.contains(c) { out.append(c) }
            }
        }
        return out
    }

    public static func station(in text: String) -> String {
        guard !text.isEmpty else { return "" }
        for line in text.components(separatedBy: CharacterSet(charactersIn: "\n。；;")) {
            let t = line.trimmingCharacters(in: .whitespaces)
            if t.count > 32 { continue }
            if stationKeys.contains(where: { t.contains($0) }) {
                return cleanStation(t)
            }
        }
        return ""
    }

    static func cleanStation(_ s: String) -> String {
        var t = s
        if let re = try? NSRegularExpression(pattern: #"^(取件|取货|提货|自提)[:：]?\s*"#) {
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
        }
        if let re = try? NSRegularExpression(pattern: #"(取件码|取货码|提货码|自提码)[A-Za-z0-9\-:：\s]*$"#) {
            t = re.stringByReplacingMatches(in: t, range: NSRange(location: 0, length: (t as NSString).length), withTemplate: "")
        }
        t = t.trimmingCharacters(in: CharacterSet(charactersIn: " ·-—,，"))
        return String(t.prefix(24))
    }

    public static func isArrival(_ text: String) -> Bool {
        arrivalKeys.contains { text.contains($0) }
    }

    public static func status(from text: String) -> String {
        if pickedKeys.contains(where: { text.contains($0) }) { return "picked" }
        return "pending"
    }

    /// 页面文本 → 取件码条目。取件码与最近一条含驿站关键词的行配对。
    public static func parse(_ text: String, source: Platform) -> [PickupItem] {
        guard !text.isEmpty else { return [] }
        var out: [PickupItem] = []
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        var lastStation = ""
        var pendingCode = ""
        var pendingLine = ""

        func flush() {
            guard !pendingCode.isEmpty else { return }
            let station = lastStation
            let id = "\(source.rawValue)-\(pendingCode)-\(station)"
            let item = PickupItem(id: id, waybillNo: Kuaidi100.extractWaybill(from: pendingLine) ?? "",
                                  code: pendingCode, stationName: station, stationText: pendingLine,
                                  goodsName: "", source: source)
            if !out.contains(where: { $0.code == item.code && $0.stationName == item.stationName }) {
                out.append(item)
            }
            pendingCode = ""
            pendingLine = ""
        }

        for line in lines {
            if line.count < 60, stationKeys.contains(where: { line.contains($0) }) {
                let s = cleanStation(line)
                if !s.isEmpty { lastStation = s }
            }
            let codes = codes(in: line)
            if let c = codes.first {
                if pendingCode.isEmpty {
                    pendingCode = c
                    pendingLine = line
                } else if c != pendingCode {
                    flush()
                    pendingCode = c
                    pendingLine = line
                }
            }
            if line.count < 80, isArrival(line), !pendingCode.isEmpty {
                pendingLine = pendingLine + " " + line
            }
        }
        flush()
        return out.filter { $0.code.count >= 3 }
    }
}

public extension Kuaidi100 {
    static func extractPickupCode(from text: String) -> String? {
        PickupParser.codes(in: text).first
    }

    static func extractStation(from text: String) -> String {
        PickupParser.station(in: text)
    }

    static func extractWaybill(from text: String) -> String? {
        let pattern = #"\b[A-Za-z]{0,4}[0-9]{8,22}\b"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let s = ns.substring(with: m.range).uppercased()
        return isValidWaybill(s) ? s : nil
    }
}

/// 页面解析出的取件码条目（导入/抓取共用）
public struct ParsedCode: Identifiable, Hashable {
    public let id = UUID()
    public let code: String
    public let station: String
    public init(code: String, station: String) {
        self.code = code
        self.station = station
    }
}

public extension Kuaidi100 {
    static func extractPickupCode(from text: String) -> String {
        PickupParser.extractPickupCode(from: text) ?? ""
    }
    static func extractStation(from text: String) -> String {
        PickupParser.extractStation(from: text)
    }
}
