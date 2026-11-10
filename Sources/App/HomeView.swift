import SwiftUI

struct HomeView: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    @State private var showAdd = false
    @State private var showImport = false
    @State private var showIdentity = false
    @State private var showYard = true

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if model.snap.pending.isEmpty {
                        emptyBox
                    } else {
                        ForEach(model.snap.pending) { item in
                            PickupRow(item: item, theme: theme) {
                                model.copy(item.code)
                            }
                            .contextMenu {
                                Button("标记已取") { model.markPicked(item) }
                                Button("复制驿站", action: { model.copy(item.stationName) })
                                Button("删除", role: .destructive) { model.remove(item) }
                            }
                        }
                    }
                    if !model.snap.pickedList.isEmpty {
                        pickedSection
                    }
                    footer
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 24)
            }
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("取件码")
            .navigationBarTitleDisplayMode(.inline)
            .refreshable { await model.refreshAll() }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button("手动添加取件码", systemImage: "plus.square") { showAdd = true }
                        Button("粘贴导入 / 单号查询", systemImage: "doc.on.clipboard") { showImport = true }
                        Button("身份码（校园驿站）", systemImage: "person.text.rectangle") { showIdentity = true }
                        Divider()
                        Button("抓取全部账号", systemImage: "antenna.radiowaves.left.and.right") {
                            Task { await model.scrapeAll(force: true) }
                        }
                        Button("立即刷新", systemImage: "arrow.clockwise") {
                            Task { await model.refreshAll() }
                        }
                    } label: {
                        Image(systemName: model.busy ? "hourglass" : "ellipsis.circle")
                    }
                }
            }
            .sheet(isPresented: $showAdd) { AddPickupSheet(theme: theme) }
            .sheet(isPresented: $showImport) { ImportSheet(theme: theme) }
            .sheet(isPresented: $showIdentity) { IdentitySheet(theme: theme) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image("Whale-\(model.snap.whalePick)")
                    .resizable().scaledToFit()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.snap.pending.isEmpty ? "暂时没有待取包裹" : "\(model.snap.pending.count) 个包裹在等你")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(theme.text)
                    Text(model.snap.whaleSpeech.isEmpty ? WhaleLines.random() : model.snap.whaleSpeech)
                        .font(.system(size: 12))
                        .foregroundColor(theme.sub)
                        .lineLimit(2)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Button {
                    showIdentity = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "person.text.rectangle")
                        Text(model.snap.identityCode.isEmpty ? "身份码" : model.snap.identityCode)
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Capsule().fill(theme.card))
                    .foregroundColor(theme.text)
                }
                .buttonStyle(.plain)
                if model.busy {
                    ProgressView().scaleEffect(0.7)
                    Text(model.statusLine).font(.system(size: 11)).foregroundColor(theme.sub).lineLimit(1)
                }
                Spacer()
                Text("更新 \(model.updatedText)").font(.system(size: 10)).foregroundColor(theme.sub)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.card))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(theme.hairline, lineWidth: 1))
        .padding(.top, 4)
    }

    private var emptyBox: some View {
        VStack(spacing: 8) {
            Image(systemName: "shippingbox").font(.system(size: 34)).foregroundColor(theme.sub)
            Text("登录账号后自动抓取，或手动添加取件码").font(.system(size: 13)).foregroundColor(theme.sub)
            Button("去登录淘宝 / 拼多多") { model.requestedTab = 2 }
                .font(.system(size: 13, weight: .semibold))
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.card))
    }

    private var pickedSection: some View {
        VStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showYard.toggle() }
            } label: {
                HStack {
                    Text("已取 / 历史 \(model.snap.pickedList.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(theme.sub)
                    Spacer()
                    Image(systemName: showYard ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11)).foregroundColor(theme.sub)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.plain)
            if showYard {
                ForEach(model.snap.pickedList.prefix(30)) { item in
                    HStack(spacing: 10) {
                        SourceChip(platform: item.platform)
                        Text(item.code).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundColor(theme.sub)
                        Text(item.stationName).font(.system(size: 11)).foregroundColor(theme.sub).lineLimit(1)
                        Spacer()
                        Button {
                            model.restore(item)
                        } label: {
                            Image(systemName: "arrow.uturn.backward").font(.system(size: 12))
                        }
                        .buttonStyle(.plain).foregroundColor(theme.accent)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(theme.card.opacity(0.7)))
                }
            }
        }
        .padding(.top, 4)
    }

    private var footer: some View {
        HStack(spacing: 4) {
            Image(systemName: "info.circle").font(.system(size: 9))
            Text("取件码来自本人账号；抓取在设备本地完成，不上传服务器")
                .font(.system(size: 10))
        }
        .foregroundColor(theme.sub.opacity(0.7))
        .padding(.top, 8)
    }
}
