import SwiftUI

struct TransitView: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    @State private var showImport = false
    @State private var detail: TransitItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    if model.snap.liveTransit.isEmpty {
                        emptyBox
                    } else {
                        ForEach(model.snap.liveTransit) { item in
                            TransitRow(item: item, theme: theme)
                                .onTapGesture { detail = item }
                                .contextMenu {
                                    Button("刷新此单") { Task { await model.refreshOne(item) } }
                                    Button("复制单号") { model.copy(item.waybillNo) }
                                    Button("删除", role: .destructive) { model.removeTransit(item) }
                                }
                        }
                    }
                    if !model.snap.arrivedTransit.isEmpty {
                        Text("已到达待取 \(model.snap.arrivedTransit.count) 件，见取件码页")
                            .font(.system(size: 11)).foregroundColor(theme.sub)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("途中快递")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refreshTransitOnly() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showImport = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showImport) { ImportSheet(theme: theme) }
            .sheet(item: $detail) { item in
                TransitDetail(item: item, theme: theme)
            }
        }
    }

    private var emptyBox: some View {
        VStack(spacing: 8) {
            Image(systemName: "truck.box").font(.system(size: 34)).foregroundColor(theme.sub)
            Text("粘贴运单号即可跟踪轨迹").font(.system(size: 13)).foregroundColor(theme.sub)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.card))
    }
}

struct TransitRow: View {
    let item: TransitItem
    let theme: Theme

    var statusColor: Color {
        if item.failed { return .orange }
        if item.arrived { return Color(hex: "4CAF50") }
        return theme.accent
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(item.cpName.isEmpty ? "识别中…" : item.cpName)
                        .font(.system(size: 14, weight: .bold)).foregroundColor(theme.text)
                    Text(item.statusText.isEmpty ? "查询中" : item.statusText)
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(statusColor.opacity(0.18)))
                        .foregroundColor(statusColor)
                }
                Text(item.waybillNo)
                    .font(.system(size: 12, design: .monospaced)).foregroundColor(theme.sub)
                if let t = item.traces.first {
                    Text("\(t.time)  \(t.context)")
                        .font(.system(size: 11)).foregroundColor(theme.sub).lineLimit(1)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.system(size: 11)).foregroundColor(theme.sub.opacity(0.6))
        }
        .padding(13)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(theme.hairline, lineWidth: 1))
    }
}

struct TransitDetail: View {
    @Environment(\.dismiss) private var dismiss
    let item: TransitItem
    let theme: Theme

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Text(item.cpName.isEmpty ? "未识别快递公司" : item.cpName)
                            .font(.system(size: 16, weight: .bold)).foregroundColor(theme.text)
                        Text(item.statusText).font(.system(size: 12)).foregroundColor(theme.accent)
                    }
                    Text(item.waybillNo).font(.system(size: 13, design: .monospaced)).foregroundColor(theme.sub)
                    ForEach(Array(item.traces.enumerated()), id: \.offset) { _, t in
                        HStack(alignment: .top, spacing: 10) {
                            Text(t.time).font(.system(size: 11, design: .monospaced)).foregroundColor(theme.sub)
                                .frame(width: 118, alignment: .leading)
                            Text(t.context).font(.system(size: 12)).foregroundColor(theme.text)
                            Spacer()
                        }
                        .padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(theme.card))
                    }
                }
                .padding(16)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("轨迹明细")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .preferredColorScheme(theme.dark ? .dark : .light)
    }
}
