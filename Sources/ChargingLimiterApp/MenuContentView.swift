import SwiftUI

struct MenuContentView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusHeader
            Divider()
            limiterControls
            contextualMessages
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 320)
        .task { model.start() }
    }

    private var statusHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: model.menuBarSymbol)
                .font(.system(size: 30, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(model.faultMessage == nil ? Color.accentColor : Color.red)
                .frame(width: 40, height: 40)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.batteryPercent.map { "\($0)%" } ?? "—")
                    .font(.title2.weight(.semibold))
                    .monospacedDigit()
                Text(model.statusText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Battery status")
    }

    private var limiterControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(
                "Charging limiter",
                isOn: Binding(
                    get: { model.limiterEnabled },
                    set: { isEnabled in model.setLimiterEnabled(isEnabled) }
                )
            )
            .toggleStyle(.switch)
            .accessibilityHint("Charging notifications stay active when this switch is off.")

            HStack {
                Text("Charge limit")
                    .font(.subheadline.weight(.medium))
                Spacer()
                Stepper(
                    "\(model.limitPercent)%",
                    value: Binding(
                        get: { model.limitPercent },
                        set: { newValue in model.setLimit(newValue) }
                    ),
                    in: 50...100,
                    step: 1
                )
                .monospacedDigit()
                .accessibilityLabel("Charge limit")
                .accessibilityValue("\(model.limitPercent) percent")
            }

            Slider(
                value: Binding(
                    get: { Double(model.limitPercent) },
                    set: { model.setLimit(Int($0.rounded())) }
                ),
                in: 50...100,
                step: 1
            ) {
                Text("Charge limit")
            } minimumValueLabel: {
                Text("50")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } maximumValueLabel: {
                Text("100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityValue("\(model.limitPercent) percent")
        }
    }

    @ViewBuilder
    private var contextualMessages: some View {
        if let message = model.helperState.message {
            NoticeView(symbol: "gearshape.2", message: message, color: .orange) {
                if model.helperState == .requiresApproval {
                    Button("Open Login Items", action: model.approveHelper)
                }
            }
        }

        if model.notificationPermission == .denied {
            NoticeView(
                symbol: "bell.slash",
                message: "Notifications are disabled in System Settings.",
                color: .orange
            ) {
                Button("Open Notification Settings", action: model.openNotificationSettings)
            }
        }

        if model.showBatterySettingsAdvice {
            NoticeView(
                symbol: "exclamationmark.triangle",
                message: "Turn off Apple Charge Limit and Optimized Battery Charging so they do not compete with this limiter.",
                color: .orange
            ) {
                HStack {
                    Button("Open Battery Settings", action: model.openBatterySettings)
                    Button("Done", action: model.dismissBatteryAdvice)
                }
            }
        }

        if let fault = model.faultMessage, !fault.isEmpty {
            NoticeView(symbol: "xmark.octagon", message: fault, color: .red) { EmptyView() }
        }
    }

    private var footer: some View {
        HStack {
            Menu("More") {
                Button("Notification Settings", action: model.openNotificationSettings)
                Button("Battery Settings", action: model.openBatterySettings)
                Divider()
                Button("Remove Background Helper", role: .destructive, action: model.removeHelper)
            }
            .menuStyle(.borderlessButton)

            Spacer()

            Button("Quit", action: model.quit)
                .keyboardShortcut("q")
        }
        .controlSize(.small)
    }
}

private struct NoticeView<Actions: View>: View {
    let symbol: String
    let message: String
    let color: Color
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(message)
                    .font(.caption)
                    .fixedSize(horizontal: false, vertical: true)
                actions()
                    .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }
}
