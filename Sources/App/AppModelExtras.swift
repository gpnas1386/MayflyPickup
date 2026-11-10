import Foundation
import SwiftUI
import UIKit

extension Snapshot {
    var pickedList: [PickupItem] {
        pickup.filter { !$0.isPending }.sorted { ($0.pickedAt ?? 0) > ($1.pickedAt ?? 0) }
    }
    var arrivedTransit: [TransitItem] { transit.filter { $0.arrived } }
}

extension AppModel {
    var updatedText: String {
        guard snap.updatedAt > 0 else { return "从未" }
        let d = Date(timeIntervalSince1970: snap.updatedAt)
        return d.formatted(date: .omitted, time: .shortened)
    }

    func copy(_ s: String) {
        guard !s.isEmpty else { return }
        UIPasteboard.general.string = s
        toast = "已复制 \(s)"
        whaleFlash = nil
    }

    func restore(_ item: PickupItem) {
        if let i = snap.pickup.firstIndex(where: { $0.id == item.id }) {
            snap.pickup[i].status = "pending"
            snap.pickup[i].pickedAt = nil
            snap.pickup[i].updatedAt = Date().timeIntervalSince1970
        }
        persist()
    }

    func refreshOne(_ item: TransitItem) async {
        let key = Pref.shared.kd100Key
        let customer = Pref.shared.kd100Customer
        let res = customer.isEmpty ? await Kuaidi100.queryFree(item.waybillNo, key: key)
            : await Kuaidi100.queryPaid(item.waybillNo, com: item.cpName, customer: customer, key: key)
        snap.upsert(TransitItem(id: item.id, waybillNo: item.waybillNo, cpName: res.comName,
                                statusText: res.statusText, latestTime: res.traces.first?.time ?? "",
                                traces: Array(res.traces.prefix(20)), source: item.platform, failed: !res.ok))
        persist()
        toast = "\(item.waybillNo)：\(res.statusText)"
    }

    func refreshTransitOnly() async { await refreshTransit(force: true) }

    func scrapeAll(force: Bool = true) async {
        for p in Platform.allCases where p != .manual {
            await scrape(platform: p, force: force)
        }
    }

    func importParsed(waybills: [String], codes: [ParsedCode]) {
        for c in codes {
            snap.upsert(PickupItem(waybillNo: "", code: c.code, stationName: c.station, source: .manual))
        }
        for wb in waybills where snap.transit.first(where: { $0.waybillNo == wb }) == nil {
            snap.upsert(TransitItem(id: wb, waybillNo: wb, source: .manual))
        }
        persist()
        toast = "已导入 \(codes.count) 个码 / \(waybills.count) 个单号"
        if !waybills.isEmpty { Task { await refreshTransit(force: true) } }
    }

    func attachAccount(_ p: Platform, result: ScrapeResult) {
        var acc = result.account ?? AccountInfo(nick: result.nick.isEmpty ? p.title : result.nick,
                                               uid: (result.account?.uid ?? "").isEmpty ? String(UUID().uuidString.prefix(8)) : (result.account?.uid ?? ""))
        acc.valid = true
        acc.savedAt = Date().timeIntervalSince1970
        Pref.shared.setAccount(p, acc)
        if snap.accounts == nil { snap.accounts = [:] }
        snap.accounts?[p.rawValue] = acc
        persist()
        Task { await scrape(platform: p, force: true) }
        toast = "\(p.short) 已登录：\(acc.nick)"
    }

    func logout(_ p: Platform) {
        Pref.shared.setAccount(p, nil)
        snap.accounts?[p.rawValue] = nil
        persist()
        toast = "已退出 \(p.short)"
    }

    func onForeground() async {
        let last = Pref.shared.lastFetch
        if Date().timeIntervalSince1970 - last < 90 { return }
        await refreshTransit(force: false)
        for p in Platform.allCases where p != .manual {
            if Pref.shared.account(p) != nil { await scrape(platform: p) }
        }
        Pref.shared.lastFetch = Date().timeIntervalSince1970
        LiveIsland.sync(snap)
    }

    func tapWhale() {
        let line = speak()
        whaleFlash = line
        persist()
    }

    func setWhalePick(_ key: String) {
        snap.whalePick = key
        Pref.shared.whaleArt = key
        persist()
    }

    func handleDeepLink(_ url: URL) {
        switch url.host ?? "" {
        case "whale", "widget":
            let line = speak()
            whaleFlash = line
            requestedTab = 0
            persist()
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
                self?.whaleFlash = nil
            }
        case "transit":
            requestedTab = 1
        case "codes", "pickup":
            requestedTab = 0
        case "settings":
            requestedTab = 2
        default:
            requestedTab = 0
        }
    }

    func clearPicked() {
        snap.pickup.removeAll { !$0.isPending }
        persist()
        toast = "已清空历史"
    }

    func fetchIdentity() async -> String {
        let runner = WebRunner()
        defer { runner.dispose() }
        let res = await runner.taobaoPass(waybills: [])
        if !res.identity.isEmpty {
            snap.identityCode = res.identity
            if !res.nick.isEmpty { snap.identityName = res.nick }
            persist()
            return res.identity
        }
        return ""
    }
}
