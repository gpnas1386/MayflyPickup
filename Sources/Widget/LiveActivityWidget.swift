import SwiftUI
import WidgetKit
import ActivityKit

struct MayflyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MayflyActivityAttributes.self) { context in
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("待取 \(context.state.total) 件")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "9AA0A6"))
                    Text(context.state.topCode)
                        .font(.system(size: 30, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                    Text(context.state.stationName.isEmpty ? "驿站取件" : context.state.stationName)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "9AA0A6")).lineLimit(1)
                }
                Spacer()
                Text(context.state.speech)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "1C1D1F"))
                    .lineLimit(2)
                    .padding(8)
                    .frame(width: 120, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(hex: "FFF6E5")))
            }
            .padding(14)
            .activityBackgroundTint(Color(hex: "1C1D1F"))
            .activitySystemActionForegroundColor(Color(hex: "3CA1DD"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("待取 \(context.state.total)").font(.system(size: 10)).foregroundColor(.gray)
                        Text(context.state.topCode).font(.system(size: 20, weight: .heavy, design: .rounded))
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Image("Whale-HE").resizable().scaledToFit().frame(width: 44)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.stationName.isEmpty ? context.state.speech : context.state.stationName)
                        .font(.system(size: 11)).foregroundColor(.gray).lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "shippingbox.fill").font(.system(size: 11))
            } compactTrailing: {
                Text("\(context.state.total)").font(.system(size: 12, weight: .bold))
            } minimal: {
                Text(context.state.topCode).font(.system(size: 9, weight: .bold)).minimumScaleFactor(0.5)
            }
            .widgetURL(URL(string: "mayfly://codes"))
            .keylineTint(Color(hex: "3CA1DD"))
        }
    }
}
