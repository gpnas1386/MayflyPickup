import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject var model: AppModel
    let theme: Theme
    @State private var copied = false

    var body: some View {
        Form {
            Section("存储") {
                row("App Group", SharedStore.appGroupID)
                row("状态文件", SharedStore.shared.groupURL?.appendingPathComponent("state.json").path ?? "未启用")
                row("备用路径", SharedStore.shared.fallbackURL.path)
                row("文件存在", FileManager.default.fileExists(atPath: SharedStore.shared.fileURL.path) ? "是" : "否")
            }
            Section("数据") {
                row("待取", "\(model.snap.pending.count)")
                row("已取", "\(model.snap.pickedList.count)")
                row("途中", "\(model.snap.liveTransit.count)")
                row("身份码", model.snap.identityCode.isEmpty ? "空" : model.snap.identityCode)
                row("更新于", model.updatedText)
            }
            Section("账号") {
                ForEach([Platform.taobao, .pdd, .jd, .mi], id: \.self) { p in
                    row(p.short, model.snap.accountsSafe[p.rawValue]?.nick ?? "未登录")
                }
            }
            Section("维护") {
                Button("刷新全部小组件") {
                    WidgetRefresh.all()
                }
                Button("复制状态 JSON") {
                    if let d = try? JSONEncoder().encode(model.snap),
                       let s = String(data: d, encoding: .utf8) {
                        UIPasteboard.general.string = s
                        copied = true
                    }
                }
                Button("清空已取记录") { model.clearPicked() }
            }
        }
        .navigationTitle("诊断")
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(theme.bg.ignoresSafeArea())
        .alert("已复制", isPresented: $copied) { Button("好", role: .cancel) {} }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .top) {
            Text(k).font(.system(size: 12)).foregroundColor(theme.sub).frame(width: 84, alignment: .leading)
            Text(v).font(.system(size: 12, design: .monospaced)).foregroundColor(theme.text)
                .textSelection(.enabled)
            Spacer()
        }
    }
}

struct AboutView: View {
    let theme: Theme

    private let parity: [(String, String)] = [
        ("取件码抓取", "网页登录 + 本地注入脚本（同 1.3 的 mtop / 页面 Hook 思路）"),
        ("途中快递", "快递100 自动识别 + 轨迹（免费通道 / 企业凭据）"),
        ("桌面小组件", "WidgetKit：取件码 / 途中 / 鲸鱼娘，各 2x2 与 4x2"),
        ("超级岛", "实况活动 + 灵动岛（iPhone 14 Pro 系列）"),
        ("通知监听", "iOS 不开放；改为本地抓取 + 到达本地通知"),
        ("常驻 / 保活", "iOS 无 Shizuku；改为 BGAppRefresh 前台刷新"),
        ("控制中心磁贴", "改为锁屏圆形小组件")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image("Whale-HE").resizable().scaledToFit().frame(width: 64, height: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("蜉蝣·取件通（iOS）").font(.system(size: 17, weight: .bold))
                        Text("v1.3.0 · 移植自 Android 1.3").font(.system(size: 11)).foregroundColor(theme.sub)
                    }
                }
                Text("功能对照").font(.system(size: 13, weight: .semibold)).foregroundColor(theme.sub)
                ForEach(Array(parity.enumerated()), id: \.offset) { _, pair in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(pair.0).font(.system(size: 13, weight: .semibold)).foregroundColor(theme.text)
                        Text(pair.1).font(.system(size: 11)).foregroundColor(theme.sub)
                    }
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 12).fill(theme.card))
                }
                Text("本 App 完全免费、无广告；取件码只来自本人账号，所有数据仅保存在本机，不经过任何服务器。官网商城与 1.3 版一致。")
                    .font(.system(size: 11)).foregroundColor(theme.sub)
            }
            .padding(16)
        }
        .background(theme.bg.ignoresSafeArea())
        .navigationTitle("关于")
        .navigationBarTitleDisplayMode(.inline)
    }
}
