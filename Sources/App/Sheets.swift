import SwiftUI

struct AddPickupSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let theme: Theme
    @State private var code = ""
    @State private var station = ""
    @State private var goods = ""
    @State private var waybill = ""
    @State private var source: Platform = .manual

    var body: some View {
        NavigationStack {
            Form {
                Section("取件码") {
                    TextField("如 8-2-3021 或 8821", text: $code)
                        .font(.system(.body, design: .rounded).weight(.semibold))
                    TextField("驿站 / 快递柜（可选）", text: $station)
                    TextField("物品名（可选）", text: $goods)
                    TextField("运单号（可选）", text: $waybill)
                        .font(.system(.body, design: .monospaced))
                }
                Section("来源") {
                    Picker("来源", selection: $source) {
                        ForEach(Platform.allCases, id: \.self) { p in
                            Text(p.title).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Button("添加") {
                    model.addManual(waybill: waybill, code: code, station: station, goods: goods, source: source)
                    dismiss()
                }
                .disabled(code.trimmingCharacters(in: .whitespaces).count < 3)
            }
            .navigationTitle("添加取件码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
        .preferredColorScheme(theme.dark ? .dark : .light)
    }
}

struct ImportSheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let theme: Theme
    @State private var text = ""
    @State private var didParse = false
    @State private var waybills: [String] = []
    @State private var codes: [ParsedCode] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("粘贴内容（短信 / 聊天记录 / 页面文本）") {
                    TextEditor(text: $text)
                        .font(.system(size: 13))
                        .frame(minHeight: 120)
                    Button("解析") { parse() }
                        .disabled(text.isEmpty)
                }
                if didParse {
                    Section("识别到 \(waybills.count) 个运单号 / \(codes.count) 个取件码") {
                        ForEach(waybills, id: \.self) { wb in
                            Label(wb, systemImage: "tray.and.arrow.down").font(.system(.footnote, design: .monospaced))
                        }
                        ForEach(codes) { c in
                            Label("\(c.code) · \(c.station)", systemImage: "number.square").font(.footnote)
                        }
                    }
                    Button("全部导入") {
                        model.importParsed(waybills: waybills, codes: codes)
                        dismiss()
                    }
                    .disabled(waybills.isEmpty && codes.isEmpty)
                }
            }
            .navigationTitle("粘贴导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            }
        }
        .preferredColorScheme(theme.dark ? .dark : .light)
    }

    private func parse() {
        waybills = Kuaidi100.extractWaybills(text)
        let cs = PickupParser.codes(in: text)
        let st = PickupParser.station(in: text)
        codes = cs.map { ParsedCode(code: $0, station: st) }
        didParse = true
    }
}

struct IdentitySheet: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let theme: Theme
    @State private var busy = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if model.snap.identityCode.isEmpty {
                    Image(systemName: "person.text.rectangle").font(.system(size: 40)).foregroundColor(theme.sub)
                    Text("还没有身份码").font(.headline).foregroundColor(theme.text)
                    Text("登录淘宝后，从菜鸟「我的」页自动读取校园驿站身份码")
                        .font(.system(size: 12)).foregroundColor(theme.sub)
                        .multilineTextAlignment(.center).padding(.horizontal, 30)
                } else {
                    Text(model.snap.identityName.isEmpty ? "校园驿站" : model.snap.identityName)
                        .font(.system(size: 13)).foregroundColor(theme.sub)
                    Text(model.snap.identityCode)
                        .font(.system(size: 44, weight: .heavy, design: .rounded))
                        .foregroundColor(theme.text)
                        .minimumScaleFactor(0.6)
                }
                Button {
                    busy = true
                    Task { _ = await model.fetchIdentity(); busy = false }
                } label: {
                    HStack { if busy { ProgressView().scaleEffect(0.7) }
                        Text("获取 / 刷新身份码") }
                        .padding(.horizontal, 18).padding(.vertical, 9)
                        .background(Capsule().fill(theme.accent)).foregroundColor(.white)
                }
                .buttonStyle(.plain)
                Text("身份码仅本地保存，用于本人取件")
                    .font(.system(size: 10)).foregroundColor(theme.sub.opacity(0.8))
                Spacer()
            }
            .padding(.top, 30)
            .navigationTitle("身份码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
        }
        .preferredColorScheme(theme.dark ? .dark : .light)
    }
}
