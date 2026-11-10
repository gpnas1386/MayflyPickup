import SwiftUI

struct MeView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var themeModel: ThemeModel
    let theme: Theme
    @State private var login: Platform?
    @State private var showDiagnostics = false
    @State private var showAbout = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach([Platform.taobao, .pdd, .jd, .mi], id: \.self) { p in
                        AccountRow(platform: p, theme: theme,
                                   info: model.snap.accountsSafe[p.rawValue],
                                   login: { login = p },
                                   scrape: { Task { await model.scrape(p, force: true) } },
                                   logout: { model.logout(p) })
                    }
                } header: {
                    Text("账号")
                } footer: {
                    Text("登录态保存在本机 WebView，不上传。iOS 无法监听其它 App 通知，所以用网页登录 + 本地抓取代替。")
                }

                Section("外观") {
                    Picker("主题", selection: Binding(
                        get: { themeModel.mode },
                        set: { themeModel.mode = $0; themeModel.save() })) {
                        Text("跟随系统").tag(Pref.ThemeMode.system)
                        Text("浅色").tag(Pref.ThemeMode.light)
                        Text("深色").tag(Pref.ThemeMode.dark)
                        Text("定时").tag(Pref.ThemeMode.scheduled)
                    }
                    .pickerStyle(.segmented)
                    if themeModel.mode == .scheduled {
                        HStack {
                            Text("深色开始")
                            Spacer()
                            DatePicker("", selection: hhmmBinding($themeModel.start), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                        HStack {
                            Text("深色结束")
                            Spacer()
                            DatePicker("", selection: hhmmBinding($themeModel.end), displayedComponents: .hourAndMinute)
                                .labelsHidden()
                        }
                    }
                }

                Section("鲸鱼娘") {
                    Picker("桌面形象", selection: Binding(
                        get: { model.snap.whalePick },
                        set: { model.setWhalePick($0) })) {
                        ForEach(["HE", "5g", "7t", "E8", "LI", "N5", "SJ", "fI"], id: \.self) { k in
                            Text(k).tag(k)
                        }
                    }
                    Button("让她说句话") { model.tapWhale() }
                    Text(model.snap.whaleSpeech.isEmpty ? "……" : model.snap.whaleSpeech)
                        .font(.system(size: 12)).foregroundColor(theme.sub)
                }

                Section("岛与通知") {
                    Toggle("实况岛（灵动岛 / 锁屏）", isOn: Binding(
                        get: { Pref.shared.liveIsland },
                        set: { Pref.shared.liveIsland = $0; LiveIsland.sync(model.snap) }))
                    Toggle("包裹到达通知", isOn: Binding(
                        get: { Pref.shared.notifyArrival },
                        set: { Pref.shared.notifyArrival = $0 }))
                    Button("发一条测试通知") { Notify.test() }
                }

                Section {
                    NavigationLink("诊断与存储") { DiagnosticsView(theme: theme) }
                    NavigationLink("关于") { AboutView(theme: theme) }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg.ignoresSafeArea())
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $login) { p in
                WebLoginView(platform: p, theme: theme) { result in
                    model.attachAccount(p, result: result)
                }
            }
        }
    }

    private func hhmmBinding(_ value: Binding<String>) -> Binding<Date> {
        Binding(
            get: {
                let parts = value.wrappedValue.split(separator: ":")
                var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                c.hour = Int(parts.first ?? "22") ?? 22
                c.minute = parts.count > 1 ? (Int(parts[1]) ?? 0) : 0
                return Calendar.current.date(from: c) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                value.wrappedValue = String(format: "%02d:%02d", c.hour ?? 22, c.minute ?? 0)
                themeModel.save()
            }
        )
    }
}
