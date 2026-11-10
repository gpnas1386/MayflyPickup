import SwiftUI
import WidgetKit

struct MayflyEntry: TimelineEntry {
    let date: Date
    let snap: Snapshot
}

struct MayflyProvider: TimelineProvider {
    func placeholder(in context: Context) -> MayflyEntry {
        MayflyEntry(date: Date(), snap: .demo)
    }

    func getSnapshot(in context: Context, completion: @escaping (MayflyEntry) -> Void) {
        let snap = SharedStore.shared.load()
        completion(MayflyEntry(date: Date(), snap: snap.pickup.isEmpty ? .demo : snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MayflyEntry>) -> Void) {
        let snap = SharedStore.shared.load()
        let entry = MayflyEntry(date: Date(), snap: snap.pickup.isEmpty && snap.transit.isEmpty ? .demo : snap)
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: Date()) ?? Date().addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

extension Snapshot {
    static var demo: Snapshot {
        var s = Snapshot()
        s.updatedAt = Date().timeIntervalSince1970
        s.whaleSpeech = "主人主人，3 个包裹到啦——"
        s.pickup = [
            PickupItem(waybillNo: "YT1234567890", code: "8-2-3021", stationName: "菜鸟驿站 · 3 号楼", goodsName: "咖啡豆", source: .taobao),
            PickupItem(waybillNo: "", code: "6-1-1024", stationName: "丰巢 · 东门", goodsName: "耳机", source: .pdd),
            PickupItem(waybillNo: "", code: "2-3-0912", stationName: "菜鸟驿站 · 图书馆", goodsName: "书", source: .jd)
        ]
        s.transit = [
            TransitItem(id: "SF1234567890", waybillNo: "SF1234567890", cpName: "顺丰",
                        statusText: "派送中", latestTime: "11:20",
                        traces: [Trace(time: "11:20", context: "快件已到达【抚州临川】营业点")], source: .taobao)
        ]
        return s
    }
}

struct MayflyBackground: ViewModifier {
    let theme: Theme
    func body(content: Content) -> some View {
        content
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.bg)
    }
}

extension View {
    func mayflyBG(_ theme: Theme) -> some View { modifier(MayflyBackground(theme: theme)) }
}
