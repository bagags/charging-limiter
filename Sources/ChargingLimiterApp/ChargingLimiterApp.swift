import SwiftUI

@main
struct ChargingLimiterApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContentView(model: model)
        } label: {
            Image(systemName: model.menuBarSymbol)
                .accessibilityLabel("Charging Limiter")
        }
        .menuBarExtraStyle(.window)
    }
}
