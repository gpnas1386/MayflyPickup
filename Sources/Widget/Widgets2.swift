import SwiftUI
import WidgetKit

struct TransitWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TransitWidget", provider: MayflyProvider()) { entry in
            TransitWidgetView(entry: entry)
        }
        .configurationDisplayName("途中快递")
        .description("在途包裹与最新轨迹，2x2 / 4x2")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct TransitWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: MayflyEntry

    var theme: Theme { Theme(dark: scheme == .dark) }
    var items: [TransitItem] { entry.snap.liveTransit }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "truck.box.fill").font(.system(size: 10)).foregroundColor(theme.accent)
                Text(items.isEmpty ? "暂无在途" : "在途 \(items.count) 件")
                    .font(.system(size: 10, weight: .semibold)).foregroundColor(theme.sub)
                Spacer()
            }
            if items.isEmpty {
                Spacer()
                Text("粘贴运单号即可跟踪").font(.system(size: 11)).foregroundColor(theme.sub)
                Spacer()
            } else if family == .systemSmall {
                if let it = items.first {
                    Text(it.statusText.isEmpty ? "运输中" : it.statusText)
                        .font(.system(size: 16, weight: .heavy, design: .rounded)).foregroundColor(theme.text)
                    Text("\(it.cpName) \(it.waybillNo)")
                        .font(.system(size: 8.5, design: .monospaced)).foregroundColor(theme.sub).lineLimit(1)
                    Text(it.traces.first?.context ?? "等待轨迹")
                        .font(.system(size: 9)).foregroundColor(theme.sub).lineLimit(2)
                }
                Spacer(minLength: 0)
            } else {
                ForEach(items.prefix(2)) { it in
                    HStack(spacing: 6) {
                        Text(it.statusText.isEmpty ? "运输中" : it.statusText)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(theme.text).frame(width: 56, alignment: .leading)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(it.cpName) \(it.waybillNo)")
                                .font(.system(size: 9, design: .monospaced)).foregroundColor(theme.sub).lineLimit(1)
                            Text(it.traces.first?.context ?? "等待轨迹")
                                .font(.system(size: 9)).foregroundColor(theme.sub).lineLimit(1)
                        }
                        Spacer()
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .mayflyBG(theme)
        .widgetURL(URL(string: "mayfly://transit"))
    }
}

struct WhaleWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WhaleWidget", provider: MayflyProvider()) { entry in
            WhaleWidgetView(entry: entry)
        }
        .configurationDisplayName("鲸鱼娘")
        .description("点一下，让她说句话（2x2 / 4x2）")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct WhaleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: MayflyEntry

    var theme: Theme { Theme(dark: scheme == .dark) }
    var speech: String {
        let s = entry.snap.whaleSpeech
        return s.isEmpty ? "主人，人家在看着快递哦" : s
    }
    var art: String { "Whale-\(entry.snap.whalePick)" }

    var body: some View {
        if family == .systemSmall {
            ZStack(alignment: .bottom) {
                theme.ink
                Image(art).resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                Text(speech)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(theme.ink)
                    .lineLimit(2)
                    .padding(.horizontal, 8).padding(.vertical, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(theme.cream))
                    .padding(6)
            }
            .widgetURL(URL(string: "mayfly://whale"))
        } else {
            HStack(spacing: 8) {
                Link(destination: URL(string: "mayfly://whale")!) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("鲸鱼娘").font(.system(size: 9, weight: .bold)).foregroundColor(theme.sub)
                        Text(speech)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(theme.ink)
                            .lineLimit(3)
                        Spacer(minLength: 0)
                        if let c = entry.snap.pending.first {
                            Text(c.code).font(.system(size: 13, weight: .heavy, design: .rounded))
                                .foregroundColor(theme.accent)
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.cream))
                }
                Link(destination: URL(string: "mayfly://codes")!) {
                    Image(art).resizable().scaledToFit()
                        .frame(width: 96)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.ink)
        }
    }
}

struct LockTileWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "LockTile", provider: MayflyProvider()) { entry in
            LockTileView(entry: entry)
        }
        .configurationDisplayName("取件快捷")
        .description("锁屏上直接看最新取件码")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct LockTileView: View {
    let entry: MayflyEntry

    var body: some View {
        if let c = entry.snap.pending.first {
            VStack(alignment: .leading, spacing: 2) {
                Text("取件码").font(.system(size: 10))
                Text(c.code).font(.system(size: 18, weight: .heavy, design: .rounded))
                Text(c.stationName).font(.system(size: 9)).lineLimit(1)
            }
            .widgetURL(URL(string: "mayfly://codes"))
        } else {
            Text("暂无待取包裹").font(.system(size: 11))
        }
    }
}
