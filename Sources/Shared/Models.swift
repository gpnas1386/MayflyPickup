import Foundation

public enum Platform: String, Codable, CaseIterable, Identifiable {
    case taobao, pdd, jd, mi, manual

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .taobao: return "淘宝 / 菜鸟"
        case .pdd: return "拼多多"
        case .jd: return "京东"
        case .mi: return "小米"
        case .manual: return "手动单号"
        }
    }

    public var short: String {
        switch self {
        case .taobao: return "淘宝"
        case .pdd: return "拼多多"
        case .jd: return "京东"
        case .mi: return "小米"
        case .manual: return "手动"
        }
    }

    public var colorHex: String {
        switch self {
        case .taobao: return "FF6A00"
        case .pdd: return "E1251B"
        case .jd: return "D7000F"
        case .mi: return "FF6900"
        case .manual: return "3CA1DD"
        }
    }
}

public struct Trace: Codable, Hashable {
    public var time: String
    public var context: String
    public init(time: String, context: String) {
        self.time = time
        self.context = context
    }
}

public struct PickupItem: Codable, Identifiable, Hashable {
    public var id: String
    public var waybillNo: String
    public var code: String
    public var stationName: String
    public var stationText: String
    public var goodsName: String
    public var source: String
    public var status: String          // pending / picked
    public var updatedAt: Double
    public var pickedAt: Double?
    public var carrrier: String

    public init(id: String? = nil, waybillNo: String, code: String, stationName: String = "",
                stationText: String = "", goodsName: String = "", source: Platform = .manual,
                status: String = "pending", updatedAt: Double = Date().timeIntervalSince1970,
                pickedAt: Double? = nil, carrrier: String = "") {
        let wb = waybillNo.uppercased().trimmingCharacters(in: .whitespaces)
        self.id = id ?? (wb.isEmpty ? "\(source.rawValue)-\(code)-\(stationName)" : wb)
        self.waybillNo = waybillNo
        self.code = code
        self.stationName = stationName
        self.stationText = stationText
        self.goodsName = goodsName
        self.source = source.rawValue
        self.status = status
        self.updatedAt = updatedAt
        self.pickedAt = pickedAt
        self.carrrier = carrrier
    }

    public var platform: Platform { Platform(rawValue: source) ?? .manual }
    public var isPending: Bool { status == "pending" }
}

public struct TransitItem: Codable, Identifiable, Hashable {
    public var id: String
    public var waybillNo: String
    public var cpName: String
    public var statusText: String
    public var latestTime: String
    public var traces: [Trace]
    public var source: String
    public var updatedAt: Double
    public var failed: Bool

    public init(id: String, waybillNo: String, cpName: String = "", statusText: String = "",
                latestTime: String = "", traces: [Trace] = [], source: Platform = .manual,
                updatedAt: Double = Date().timeIntervalSince1970, failed: Bool = false) {
        self.id = id
        self.waybillNo = waybillNo
        self.cpName = cpName
        self.statusText = statusText
        self.latestTime = latestTime
        self.traces = traces
        self.source = source.rawValue
        self.updatedAt = updatedAt
        self.failed = failed
    }

    public var platform: Platform { Platform(rawValue: source) ?? .manual }
    public var arrived: Bool {
        let s = statusText
        return s.contains("待取") || s.contains("已入柜") || s.contains("已到达") || s.contains("已代收") || s.contains("已放")
    }
}

public struct AccountInfo: Codable, Hashable {
    public var nick: String
    public var uid: String
    public var savedAt: Double
    public var valid: Bool

    public init(nick: String, uid: String, savedAt: Double = Date().timeIntervalSince1970, valid: Bool = true) {
        self.nick = nick
        self.uid = uid
        self.savedAt = savedAt
        self.valid = valid
    }
}

public struct Snapshot: Codable {
    public var version: Int = 1
    public var pickup: [PickupItem] = []
    public var transit: [TransitItem] = []
    public var updatedAt: Double = 0
    public var identityCode: String = ""
    public var identityName: String = ""
    public var whalePick: String = "HE"
    public var whaleSpeech: String = ""
    public var accounts: [String: AccountInfo]? = [:]

    public init() {}

    public var accountsSafe: [String: AccountInfo] { accounts ?? [:] }

    public var pending: [PickupItem] { pickup.filter { $0.isPending }.sorted { $0.updatedAt > $1.updatedAt } }
    public var liveTransit: [TransitItem] { transit.filter { !$0.arrived }.sorted { $0.updatedAt > $1.updatedAt } }

    public mutating func upsert(_ item: PickupItem) {
        if let i = pickup.firstIndex(where: { $0.id == item.id }) {
            var old = pickup[i]
            old.waybillNo = item.waybillNo.isEmpty ? old.waybillNo : item.waybillNo
            old.code = item.code.isEmpty ? old.code : item.code
            old.stationName = item.stationName.isEmpty ? old.stationName : item.stationName
            old.stationText = item.stationText.isEmpty ? old.stationText : item.stationText
            old.goodsName = item.goodsName.isEmpty ? old.goodsName : item.goodsName
            old.carrrier = item.carrrier.isEmpty ? old.carrrier : item.carrrier
            old.updatedAt = max(old.updatedAt, item.updatedAt)
            old.status = item.status
            old.pickedAt = item.pickedAt ?? old.pickedAt
            pickup[i] = old
        } else {
            pickup.append(item)
        }
        updatedAt = Date().timeIntervalSince1970
    }

    public mutating func upsert(_ item: TransitItem) {
        if let i = transit.firstIndex(where: { $0.id == item.id }) {
            var old = transit[i]
            if !item.cpName.isEmpty { old.cpName = item.cpName }
            if !item.statusText.isEmpty { old.statusText = item.statusText }
            if !item.latestTime.isEmpty { old.latestTime = item.latestTime }
            if !item.traces.isEmpty { old.traces = item.traces }
            old.updatedAt = max(old.updatedAt, item.updatedAt)
            old.failed = item.failed && old.traces.isEmpty
            transit[i] = old
        } else {
            transit.append(item)
        }
        updatedAt = Date().timeIntervalSince1970
    }
}
