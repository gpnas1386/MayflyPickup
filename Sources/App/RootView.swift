import SwiftUI

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @EnvironmentObject var themeModel: ThemeModel
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var scenePhase
    @State private var tab = 0

    var body: some View {
        let theme = Theme(dark: themeModel.isDark(scheme: scheme))
        TabView(selection: tabBinding) {
            HomeView(theme: theme)
                .tabItem { Label("取件码", systemImage: "shippingbox.fill") }
                .tag(0)
            TransitView(theme: theme)
                .tabItem { Label("途中", systemImage: "truck.box.fill") }
                .tag(1)
            MeView(theme: theme)
                .tabItem { Label("我的", systemImage: "person.crop.circle.fill") }
                .tag(2)
        }
        .preferredColorScheme(colorSchemeOverride)
        .tint(theme.accent)
        .overlay(alignment: .bottom) {
            if let s = model.whaleFlash { WhaleToast(text: s, theme: theme) }
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                Task { await model.onForeground() }
            } else if phase == .background {
                BackgroundRefresh.schedule()
            }
        }
    }

    private var tabBinding: Binding<Int> {
        Binding(get: { tab }, set: { tab = $0 })
    }

    private var colorSchemeOverride: ColorScheme? {
        switch themeModel.mode {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        case .scheduled: return themeModel.isDarkScheduleActive ? .dark : .light
        }
    }
}

struct WhaleToast: View {
    let text: String
    let theme: Theme
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Image("Whale-\(Pref.shared.whalePick)")
                .resizable().scaledToFit()
                .frame(width: 44, height: 44)
                .clipShape(Circle())
            Text(text)
                .font(.system(size: 13))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(theme.cream))
                .foregroundColor(theme.creamText)
        }
        .padding(.bottom, 56)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .animation(.spring(), value: text)
    }
}
