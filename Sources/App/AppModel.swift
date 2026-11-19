import Foundation
import SwiftUI
import WidgetKit
import BackgroundTasks

@MainActor
final class AppModel: ObservableObject {
    @Published var snap: Snapshot
    @Published var busy = false
    @Published var statusLine = ""
    @Published var logs: [String] = []
    @Published var whaleSpeech = "人家在看着快递哦"
    @Published var toast: String?
    @Published var whaleFlash: String?
    @Published var requestedTab: Int?
    var selectedTab = 0

    private let store = SharedStore.shared
    private var lastArrivedIDs: Set<String> = []

    init() {
        snap = store.load()
        whaleSpeech = snap.whaleSpeech.isEmpty ? WhaleLines.random() : snap.whaleSpeech
        lastArrivedIDs = Set(snap.pending.map { $0.id })
        AppRegistry.model = self
    }

    func log(_ s: String) {
        let line = "[\(Date().formatted(date: .omitted, time: .shortened))] \(s)"
        logs.append(line)
        if logs.count > 200 { logs.removeFirst(logs.count - 200) }
        statusLine = s
        NSLog("[Mayfly] \(s)")
    }

    // MARK: - 持久化

    func persist(reloadWidgets: Bool = true) {
        snap.updatedAt = Date().timeIntervalSince1970
        snap.whaleSpeech = whaleSpeech
        store.save(snap)
        if reloadWidgets { WidgetRefresh.all() }
        LiveIsland.sync(snap)
    }

    // MARK: - 取件码操作

    func addManual(waybill: String, code: String, station: String, goods: String, source: Platform = .manual) {
        let item = PickupItem(waybillNo: waybill, code: code, stationName: station,
                              goodsName: goods, source: source)
        snap.upsert(item)
        if let t = transitByWaybill(item.waybillNo) { /* already known */ _ = t }
        persist()
        log("添加 \(source.short)：\(item.id) → \(code)")
        toast = "已添加：\(code)"
    }

    func remove(_ item: PickupItem) {
        snap.pickup.removeAll { $0.id == item.id }
        persist()
    }

    func markPicked(_ item: PickupItem) {
        if let i = snap.pickup.firstIndex(where: { $0.id == item.id }) {
            snap.pickup[i].status = "picked"
            snap.pickup[i].pickedAt = Date().timeIntervalSince1970
            snap.pickup[i].updatedAt = Date().timeIntervalSince1970
        }
        persist()
    }

    func togglePicked(_ item: PickupItem) {
        if item.isPending { markPicked(item) } else {
            if let i = snap.pickup.firstIndex(where: { $0.id == item.id }) {
                snap.pickup[i].status = "pending"
                snap.pickup[i].pickedAt = nil
                snap.pickup[i].updatedAt = Date().timeIntervalSince1970
            }
            persist()
        }
    }

    func transitByWaybill(_ wb: String) -> TransitItem? {
        snap.transit.first { $0.waybillNo.uppercased() == wb.uppercased() }
    }

    func speak() -> String {
        let line = WhaleLines.speak(pendingCount: snap.pending.count,
                                    transitCount: snap.transit.filter { !$0.arrived }.count)
        whaleSpeech = line
        snap.whaleSpeech = line
        store.save(snap)
        return line
    }

    // MARK: - 途中快递

    func addWaybill(_ raw: String) async {
        let nums = Kuaidi100.extractWaybills(raw)
        guard !nums.isEmpty else {
            toast = "没识别到运单号"
            return
        }
        for n in nums {
            guard snap.transit.first(where: { $0.waybillNo == n }) == nil else { continue }
            snap.upsert(TransitItem(id: n, waybillNo: n, source: .manual))
        }
        persist()
        toast = "已添加 \(nums.count) 个单号，开始查询…"
        await refreshTransit(force: true)
    }

    func removeTransit(_ item: TransitItem) {
        snap.transit.removeAll { $0.id == item.id }
        persist()
    }

    /// 顺路把「已到达」的单补进取件码（无码时留空，等抓取补）
    private func promoteArrivals() {
        for t in snap.transit where t.arrived {
            if snap.pickup.first(where: { $0.waybillNo.uppercased() == t.waybillNo.uppercased() }) == nil {
                let code = Kuaidi100.extractPickupCode(from: t.traces.first?.context ?? "")
                let station = Kuaidi100.extractStation(from: t.traces.first?.context ?? "")
                let item = PickupItem(waybillNo: t.waybillNo, code: code.isEmpty ? "待驿站发放" : code,
                                      stationName: station, stationText: t.traces.first?.context ?? "",
                                      goodsName: "", source: t.platform)
                snap.upsert(item)
            }
        }
    }

    func refreshTransit(force: Bool = false) async {
        if busy && !force { return }
        busy = true
        defer { busy = false }
        let items = Array(snap.transit.prefix(24))
        let key = Pref.shared.kd100Key
        let customer = Pref.shared.kd100Customer
        var arrivedNew: [PickupItem] = []
        for (idx, t) in items.enumerated() {
            statusLine = "查询轨迹 \(idx + 1)/\(items.count) \(t.waybillNo)"
            var res: Kd100Result
            if !customer.isEmpty, !key.isEmpty {
                res = await Kuaidi100.queryPaid(t.waybillNo, com: "", customer: customer, key: key)
            } else {
                res = await Kuaidi100.queryFree(t.waybillNo, com: "", key: key)
            }
            let item = TransitItem(id: t.id, waybillNo: t.waybillNo, cpName: res.comName,
                                   statusText: res.statusText, latestTime: res.traces.first?.time ?? "",
                                   traces: Array(res.traces.prefix(20)), source: t.platform,
                                   failed: !res.ok)
            snap.upsert(item)
            if res.ok, item.arrived, !lastArrivedIDs.contains(t.id) {
                lastArrivedIDs.insert(t.id)
                let parsed = Kuaidi100.extractPickupCode(from: res.traces.first?.context ?? "")
                let code = parsed.isEmpty ? "已到 · 码待发放" : parsed
                let st = Kuaidi100.extractStation(from: res.traces.first?.context ?? "")
                arrivedNew.append(PickupItem(waybillNo: t.waybillNo, code: code, stationName: st,
                                             stationText: res.traces.first?.context ?? "", source: t.platform))
            }
            try? await Task.sleep(nanoseconds: 900_000_000)
        }
        promoteArrivals()
        if !arrivedNew.isEmpty {
            for it in arrivedNew {
                Notifier.arrival(code: it.code, station: it.stationName, total: snap.pending.count)
            }
            whaleSpeech = WhaleLines.speak(pendingCount: snap.pending.count,
                                           transitCount: snap.transit.filter { !$0.arrived }.count)
        }
        persist()
        log("轨迹刷新完成，共 \(snap.transit.count) 单")
    }

    // MARK: - 网页数据源

    func scrape(platform: Platform, force: Bool = false) async {
        if busy && platform != .manual { return }
        busy = true
        defer { busy = false }
        let runner = WebRunner()
        defer { runner.dispose() }
        let waybills = snap.transit.map { $0.waybillNo.uppercased() }
        switch platform {
        case .taobao:
            statusLine = "正在抓取淘宝 / 菜鸟…"
            let res = await runner.taobaoPass(waybills: waybills)
            applyScrape(res, source: .taobao)
        case .pdd:
            statusLine = "正在抓取拼多多…"
            let res = await runner.pddPass()
            applyScrape(res, source: .pdd)
        case .jd:
            statusLine = "正在抓取京东…"
            let res = await runner.jdPass()
            applyScrape(res, source: .jd)
        case .mi:
            statusLine = "正在抓取小米…"
            let res = await runner.miPass()
            applyScrape(res, source: .mi)
        case .manual:
            break
        }
    }

    func applyScrape(_ res: ScrapeResult, source: Platform) {
        log("\(source.short) 抓取：取件码 \(res.pickups.count) · 身份码 \(res.identity.isEmpty ? "无" : "有") · 账号 \(res.nick.isEmpty ? "未识别" : res.nick)")
        for d in res.debug { log("  [\(d)]") }
        if let acc = res.account {
            Pref.shared.setAccount(source, acc)
            snap.accounts?[source.rawValue] = acc
        }
        if !res.identity.isEmpty {
            snap.identityCode = res.identity
            snap.identityName = res.nick
        }
        for it in res.pickups {
            snap.upsert(it)
        }
        if !res.pickups.isEmpty {
            whaleSpeech = WhaleLines.speak(pendingCount: snap.pending.count,
                                           transitCount: snap.transit.filter { !$0.arrived }.count)
        }
        persist()
    }

    func refreshAll() async {
        await refreshTransit(force: true)
        for p in Platform.allCases where p != .manual {
            if Pref.shared.account(p) != nil {
                await scrape(platform: p)
            }
        }
        Pref.shared.lastFetch = Date().timeIntervalSince1970
        log("全部刷新完成：待取 \(snap.pending.count) · 在途 \(snap.transit.filter { !$0.arrived }.count)")
    }

    // MARK: - 深链

    func handle(url: URL) {
        let host = url.host ?? url.scheme ?? ""
        switch host {
        case "codes", "pickup":
            selectedTab = 0
            if let c = url.queryParameters?["copy"] {
                UIPasteboard.general.string = c
                toast = "取件码已复制：\(c)"
            }
        case "transit":
            selectedTab = 1
        case "whale":
            snap.whaleSpeech = speak()
            selectedTab = 2
        default:
            break
        }
    }
}

extension URL {
    var queryParameters: [String: String]? {
        guard let comps = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return nil }
        guard let items = comps.queryItems else { return nil }
        var out: [String: String] = [:]
        for i in items { out[i.name] = i.value ?? "" }
        return out
    }
}

// MARK: - 后台刷新

enum BackgroundRefresh {
    static let taskID = "com.agent.idcode.refresh"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskID, using: nil) { task in
            scheduleNext()
            let work = Task { @MainActor in
                let model = AppRegistry.model
                if let model = model {
                    await model.refreshTransit(force: true)
                }
                task.setTaskCompleted(success: true)
            }
            task.expirationHandler = { work.cancel() }
        }
    }

    static func schedule() { scheduleNext() }

    static func scheduleNext() {
        let req = BGAppRefreshTaskRequest(identifier: taskID)
        req.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        do {
            try BGTaskScheduler.shared.submit(req)
        } catch {
            NSLog("[Mayfly] bg submit \(error)")
        }
    }
}

/// 后台任务需要一个不依赖 SwiftUI 生命周期的模型引用
enum AppRegistry {
    static var model: AppModel?
}
