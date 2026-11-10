import SwiftUI
import UIKit
import WidgetKit

@main
struct MayflyApp: App {
    @StateObject private var model = AppModel()
    @StateObject private var themeModel = ThemeModel()

    init() {
        BackgroundRefresh.register()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(themeModel)
                .onOpenURL { url in
                    model.handleDeepLink(url)
                }
                .task {
                    Notifier.request()
                    BackgroundRefresh.scheduleNext()
                }
        }
    }
}

enum WidgetCenterReload {
    static func refresh() {
        WidgetCenter.shared.reloadAllTimelines()
    }
}
