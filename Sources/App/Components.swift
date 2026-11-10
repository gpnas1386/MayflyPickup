import SwiftUI

struct SourceChip: View {
    let platform: Platform
    var body: some View {
        Text(platform.short)
            .font(.system(size: 10, weight: .bold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .foregroundColor(.white)
            .background(Capsule().fill(Color(hex: platform.colorHex)))
    }
}

struct StationLine: View {
    let text: String
    let color: Color
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mappin.and.ellipse").font(.system(size: 10))
            Text(text.isEmpty ? "未标注驿站" : text)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundColor(color)
    }
}

struct PickupRow: View {
    let item: PickupItem
    let theme: Theme
    let copy: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    SourceChip(platform: item.platform)
                    Text(item.goodsName.isEmpty ? "待取包裹" : item.goodsName)
                        .font(.system(size: 12)).foregroundColor(theme.sub).lineLimit(1)
                }
                Text(item.code)
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundColor(theme.text)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                StationLine(text: item.stationName, color: theme.sub)
                if !item.waybillNo.isEmpty {
                    Text(item.waybillNo).font(.system(size: 10, design: .monospaced))
                        .foregroundColor(theme.sub.opacity(0.8))
                }
            }
            Spacer(minLength: 6)
            Button(action: copy) {
                VStack(spacing: 3) {
                    Image(systemName: "doc.on.doc").font(.system(size: 14, weight: .semibold))
                    Text("复制").font(.system(size: 10))
                }
                .foregroundColor(.white)
                .frame(width: 52, height: 52)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.accent))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(theme.hairline, lineWidth: 1))
    }
}
