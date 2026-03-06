import SwiftUI
import Foundation

struct SpeedLimitsContent: View {
    let config: TransmissionSessionResponseArguments
    @ObservedObject var editModel: SessionSettingsEditModel
    var showHeadings: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 12) {
                if showHeadings {
                    Text("Speed Limits")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                Toggle("Download limit", isOn: Binding(
                    get: { editModel.getValue("speedLimitDownEnabled", fallback: config.speedLimitDownEnabled) },
                    set: { editModel.setValue("speedLimitDownEnabled", $0, original: config.speedLimitDownEnabled) }
                ))

                if editModel.getValue("speedLimitDownEnabled", fallback: config.speedLimitDownEnabled) {
                    HStack {
                        Text("Download speed")
                        Spacer()
                        TextField("KB/s", value: Binding(
                            get: { editModel.getValue("speedLimitDown", fallback: config.speedLimitDown) },
                            set: { editModel.setValue("speedLimitDown", $0, original: config.speedLimitDown) }
                        ), format: .number)
                        Text("KB/s")
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Upload limit", isOn: Binding(
                    get: { editModel.getValue("speedLimitUpEnabled", fallback: config.speedLimitUpEnabled) },
                    set: { editModel.setValue("speedLimitUpEnabled", $0, original: config.speedLimitUpEnabled) }
                ))

                if editModel.getValue("speedLimitUpEnabled", fallback: config.speedLimitUpEnabled) {
                    HStack {
                        Text("Upload speed")
                        Spacer()
                        TextField("KB/s", value: Binding(
                            get: { editModel.getValue("speedLimitUp", fallback: config.speedLimitUp) },
                            set: { editModel.setValue("speedLimitUp", $0, original: config.speedLimitUp) }
                        ), format: .number)
                        Text("KB/s")
                            .foregroundColor(.secondary)
                    }
                }
            }

            if showHeadings {
                Divider()
                    .padding(.vertical, 4)
            }

            VStack(alignment: .leading, spacing: 12) {
                if showHeadings {
                    Label("Alternate Speed Limits", systemImage: "tortoise")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 4)
                }

                Toggle("Enable alternate speeds", isOn: Binding(
                    get: { editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled) },
                    set: { editModel.setValue("altSpeedEnabled", $0, original: config.altSpeedEnabled) }
                ))

                if editModel.getValue("altSpeedEnabled", fallback: config.altSpeedEnabled) {
                    HStack {
                        Text("Download limit")
                        Spacer()
                        TextField("KB/s", value: Binding(
                            get: { editModel.getValue("altSpeedDown", fallback: config.altSpeedDown) },
                            set: { editModel.setValue("altSpeedDown", $0, original: config.altSpeedDown) }
                        ), format: .number)
                        Text("KB/s")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Upload limit")
                        Spacer()
                        TextField("KB/s", value: Binding(
                            get: { editModel.getValue("altSpeedUp", fallback: config.altSpeedUp) },
                            set: { editModel.setValue("altSpeedUp", $0, original: config.altSpeedUp) }
                        ), format: .number)
                        Text("KB/s")
                            .foregroundColor(.secondary)
                    }
                }

                Toggle("Schedule alternate speeds", isOn: Binding(
                    get: { editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled) },
                    set: { editModel.setValue("altSpeedTimeEnabled", $0, original: config.altSpeedTimeEnabled) }
                ))
                .padding(.top, 8)

                if editModel.getValue("altSpeedTimeEnabled", fallback: config.altSpeedTimeEnabled) {
                    HStack(spacing: 12) {
                        Picker("", selection: Binding(
                            get: { editModel.getValue("altSpeedTimeDay", fallback: config.altSpeedTimeDay) },
                            set: { editModel.setValue("altSpeedTimeDay", $0, original: config.altSpeedTimeDay) }
                        )) {
                            Text("Every Day").tag(127)
                            Text("Weekdays").tag(62)
                            Text("Weekends").tag(65)
                            Divider()
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(4)
                            Text("Wednesday").tag(8)
                            Text("Thursday").tag(16)
                            Text("Friday").tag(32)
                            Text("Saturday").tag(64)
                        }
                        .pickerStyle(.menu)

                        Text("from")
                            .foregroundColor(.secondary)

                        DatePicker("", selection: Binding(
                            get: {
                                let minutes = editModel.getValue("altSpeedTimeBegin", fallback: config.altSpeedTimeBegin)
                                let calendar = Calendar.current
                                return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                            },
                            set: { date in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.hour, .minute], from: date)
                                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                                editModel.setValue("altSpeedTimeBegin", minutes, original: config.altSpeedTimeBegin)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()

                        Text("to")
                            .foregroundColor(.secondary)

                        DatePicker("", selection: Binding(
                            get: {
                                let minutes = editModel.getValue("altSpeedTimeEnd", fallback: config.altSpeedTimeEnd)
                                let calendar = Calendar.current
                                return calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
                            },
                            set: { date in
                                let calendar = Calendar.current
                                let components = calendar.dateComponents([.hour, .minute], from: date)
                                let minutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
                                editModel.setValue("altSpeedTimeEnd", minutes, original: config.altSpeedTimeEnd)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.compact)
                        .labelsHidden()

                        Spacer()
                    }
                }
            }
        }
    }
}
