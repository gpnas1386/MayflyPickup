import SwiftUI
import WidgetKit

@main
struct MayflyWidgetBundle: WidgetBundle {
    @WidgetBundleBuilder
    var body: some Widget {
        PickupWidget()
        TransitWidget()
        WhaleWidget()
        LockTileWidget()
        MayflyLiveActivity()
    }
}

struct PickupWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PickupWidget", provider: MayflyProvider()) { entry in
            PickupWidgetView(entry: entry)
        }
        .configurationDisplayName("取件码")
        .description("待取包裹与取件码，2x2 / 4x2")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular])
    }
}

struct PickupWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    let entry: MayflyEntry

    var theme: Theme { Theme(dark: scheme == .dark) }

    var body: some View {
        let items = entry.snap.pending
        if family == .accessoryCircular {
            ZStack {
                Circle().stroke(theme.accent.opacity(0.35), lineWidth: 3)
                VStack(spacing: 0) {
                    Text("取").font(.system(size: 10, weight: .bold)).foregroundColor(theme.accent)
                    Text("\(items.count)").font(.system(size: 16, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.text)
                }
            }
            .widgetURL(URL(string: "mayfly://codes"))
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 5) {
                    Image(systemName: "shippingbox.fill").font(.system(size: 10)).foregroundColor(theme.accent)
                    Text(items.isEmpty ? "暂无待取" : "待取 \(items.count) 件")
                        .font(.system(size: 10, weight: .semibold)).foregroundColor(theme.sub)
                    Spacer()
                }
                if items.isEmpty {
                    Spacer()
                    Text("去登录抓取").font(.system(size: 11)).foregroundColor(theme.sub)
                    Spacer()
                } else if family == .systemSmall {
                    ForEach(items.prefix(4)) { item in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.code)
                                .font(.system(size: 17, weight: .heavy, design: .rounded))
                                .foregroundColor(theme.text)
                                .minimumScaleFactor(0.7).lineLimit(1)
                            Text(item.stationName.isEmpty ? item.platform.short : item.stationName)
                                .font(.system(size: 8.5)).foregroundColor(theme.sub).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                } else {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(0..<2, id: \.self) { col in
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(Array(chunk(col).enumerated()), id: \.offset) { _, item in
                                    HStack(spacing: 5) {
                                        Text(item.code)
                                            .font(.system(size: 15, weight: .heavy, design: .rounded))
                                            .foregroundColor(theme.text)
                                            .minimumScaleFactor(0.6).lineLimit(1)
                                        Text(item.stationName)
                                            .font(.system(size: 8)).foregroundColor(theme.sub).lineLimit(1)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .mayflyBG(theme)
            .widgetURL(URL(string: "mayfly://codes"))
        }
    }

    private func chunk(_ col: Int) -> [PickupItem] {
        let items = Array(entry.snap.pending.prefix(8))
        return items.enumerated().filter { $0.offset % 2 == col }.map { $0.element }
    }
}
