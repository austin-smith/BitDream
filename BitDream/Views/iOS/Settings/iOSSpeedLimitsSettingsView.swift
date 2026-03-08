#if os(iOS)
import SwiftUI
import Foundation

struct iOSSpeedLimitsSettingsView: View {
    @ObservedObject var store: TransmissionStore
    @StateObject private var editModel = SettingsViewModel()

    var body: some View {
        Group {
            if let config = store.sessionConfiguration {
                Form {
                    Section(header: Text("Speed Limits")) {
                        Toggle("Download limit", isOn: Binding(
                            get: { editModel.value(for: \.speedLimitDownEnabled, fallback: config.speedLimitDownEnabled) },
                            set: { editModel.setValue(\.speedLimitDownEnabled, $0, original: config.speedLimitDownEnabled) }
                        ))

                        HStack {
                            Text("Download speed (KB/s)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.value(for: \.speedLimitDown, fallback: config.speedLimitDown) },
                                set: { editModel.setValue(\.speedLimitDown, $0, original: config.speedLimitDown) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.value(for: \.speedLimitDownEnabled, fallback: config.speedLimitDownEnabled))
                            .foregroundColor(editModel.value(for: \.speedLimitDownEnabled, fallback: config.speedLimitDownEnabled) ? .primary : .secondary)
                        }

                        Toggle("Upload limit", isOn: Binding(
                            get: { editModel.value(for: \.speedLimitUpEnabled, fallback: config.speedLimitUpEnabled) },
                            set: { editModel.setValue(\.speedLimitUpEnabled, $0, original: config.speedLimitUpEnabled) }
                        ))

                        HStack {
                            Text("Upload speed (KB/s)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.value(for: \.speedLimitUp, fallback: config.speedLimitUp) },
                                set: { editModel.setValue(\.speedLimitUp, $0, original: config.speedLimitUp) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.value(for: \.speedLimitUpEnabled, fallback: config.speedLimitUpEnabled))
                            .foregroundColor(editModel.value(for: \.speedLimitUpEnabled, fallback: config.speedLimitUpEnabled) ? .primary : .secondary)
                        }
                    }

                    Section(header: Text("Alternate Speed Limits")) {
                        Toggle("Enable alternate speeds", isOn: Binding(
                            get: { editModel.value(for: \.altSpeedEnabled, fallback: config.altSpeedEnabled) },
                            set: { editModel.setValue(\.altSpeedEnabled, $0, original: config.altSpeedEnabled) }
                        ))

                        HStack {
                            Text("Download limit (KB/s)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.value(for: \.altSpeedDown, fallback: config.altSpeedDown) },
                                set: { editModel.setValue(\.altSpeedDown, $0, original: config.altSpeedDown) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.value(for: \.altSpeedEnabled, fallback: config.altSpeedEnabled))
                            .foregroundColor(editModel.value(for: \.altSpeedEnabled, fallback: config.altSpeedEnabled) ? .primary : .secondary)
                        }

                        HStack {
                            Text("Upload limit (KB/s)")
                            Spacer()
                            TextField("", value: Binding(
                                get: { editModel.value(for: \.altSpeedUp, fallback: config.altSpeedUp) },
                                set: { editModel.setValue(\.altSpeedUp, $0, original: config.altSpeedUp) }
                            ), format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .disabled(!editModel.value(for: \.altSpeedEnabled, fallback: config.altSpeedEnabled))
                            .foregroundColor(editModel.value(for: \.altSpeedEnabled, fallback: config.altSpeedEnabled) ? .primary : .secondary)
                        }

                        Toggle("Schedule alternate speeds", isOn: Binding(
                            get: { editModel.value(for: \.altSpeedTimeEnabled, fallback: config.altSpeedTimeEnabled) },
                            set: { editModel.setValue(\.altSpeedTimeEnabled, $0, original: config.altSpeedTimeEnabled) }
                        ))
                        .disabled(!editModel.value(for: \.altSpeedEnabled, fallback: config.altSpeedEnabled))

                        Picker("Days", selection: Binding(
                            get: { editModel.value(for: \.altSpeedTimeDay, fallback: config.altSpeedTimeDay) },
                            set: { editModel.setValue(\.altSpeedTimeDay, $0, original: config.altSpeedTimeDay) }
                        )) {
                            Text("Every Day").tag(127)
                            Text("Weekdays").tag(62)
                            Text("Weekends").tag(65)
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(4)
                            Text("Wednesday").tag(8)
                            Text("Thursday").tag(16)
                            Text("Friday").tag(32)
                            Text("Saturday").tag(64)
                        }
                        .disabled(!editModel.value(for: \.altSpeedTimeEnabled, fallback: config.altSpeedTimeEnabled))

                        DatePicker("Start Time", selection: Binding(
                            get: {
                                let minutes = editModel.value(for: \.altSpeedTimeBegin, fallback: config.altSpeedTimeBegin)
                                let calendar = Calendar.current
                                return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                            },
                            set: { date in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.hour, .minute], from: date)
                                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                                editModel.setValue(\.altSpeedTimeBegin, minutes, original: config.altSpeedTimeBegin)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .disabled(!editModel.value(for: \.altSpeedTimeEnabled, fallback: config.altSpeedTimeEnabled))

                        DatePicker("End Time", selection: Binding(
                            get: {
                                let minutes = editModel.value(for: \.altSpeedTimeEnd, fallback: config.altSpeedTimeEnd)
                                let calendar = Calendar.current
                                return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                            },
                            set: { date in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.hour, .minute], from: date)
                                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                                editModel.setValue(\.altSpeedTimeEnd, minutes, original: config.altSpeedTimeEnd)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .disabled(!editModel.value(for: \.altSpeedTimeEnabled, fallback: config.altSpeedTimeEnabled))
                    }

                    if editModel.saveState != .idle {
                        Section {
                            SettingsSaveStateView(state: editModel.saveState)
                        }
                    }
                }
                .navigationTitle("Speed Limits")
                .bindSettingsViewModel(editModel, to: store)
            } else {
                ContentUnavailableView(
                    "No Server Connected",
                    systemImage: "speedometer",
                    description: Text("Speed limit settings will appear when connected to a server.")
                )
            }
        }
    }
}
#endif
