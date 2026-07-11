import SwiftUI

#if os(iOS)
struct iOSFilterAndSortView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var statusFilter: [TorrentStatusCalc]
    @Binding var labelFilter: TorrentLabelFilter
    @Binding var sortProperty: SortProperty
    @Binding var sortOrder: SortOrder

    let availableLabels: [String]
    let labelCounts: [String: Int]
    let noLabelCount: Int

    var body: some View {
        NavigationStack {
            List {
                Section("Filter") {
                    Picker("Status", selection: statusOptionBinding) {
                        ForEach(iOSStatusFilterOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    NavigationLink {
                        iOSLabelFilterView(
                            labelFilter: $labelFilter,
                            availableLabels: availableLabels,
                            labelCounts: labelCounts,
                            noLabelCount: noLabelCount
                        )
                    } label: {
                        LabeledContent("Labels", value: labelSelectionSummary)
                    }
                }

                Section("Sort") {
                    Picker("Sort By", selection: $sortProperty) {
                        ForEach(SortProperty.allCases, id: \.self) { property in
                            Text(property.rawValue).tag(property)
                        }
                    }
                    .pickerStyle(.navigationLink)

                    Picker("Order", selection: $sortOrder) {
                        Text("Ascending").tag(SortOrder.ascending)
                        Text("Descending").tag(SortOrder.descending)
                    }
                    .pickerStyle(.navigationLink)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Filter & Sort")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: dismiss.callAsFunction)
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

private extension iOSFilterAndSortView {
    var statusOptionBinding: Binding<iOSStatusFilterOption> {
        Binding(
            get: {
                iOSStatusFilterOption.allCases.first { $0.statuses == statusFilter } ?? .all
            },
            set: { statusFilter = $0.statuses }
        )
    }

    var labelSelectionSummary: String {
        switch labelFilter.activeCount {
        case 0:
            return "None"
        case 1 where labelFilter.showsUnlabeledOnly:
            return "No labels"
        default:
            return "\(labelFilter.activeCount) Active"
        }
    }
}

private struct iOSLabelFilterView: View {
    @Binding var labelFilter: TorrentLabelFilter

    let availableLabels: [String]
    let labelCounts: [String: Int]
    let noLabelCount: Int

    var body: some View {
        List {
            Section {
                ForEach(availableLabels, id: \.self) { label in
                    let rule = labelFilter.rule(for: label)
                    Button {
                        labelFilter.advanceRule(for: label)
                    } label: {
                        iOSLabelRuleRow(
                            label: label,
                            count: labelCounts[label, default: 0],
                            rule: rule
                        )
                    }
                    .buttonStyle(.plain)
                    .listRowSeparator(
                        label == availableLabels.last ? .visible : .hidden,
                        edges: .bottom
                    )
                    .accessibilityValue(rule.rawValue)
                    .accessibilityHint("Cycles between no filter, include, and exclude")
                }

                Button {
                    labelFilter.setShowsUnlabeledOnly(!labelFilter.showsUnlabeledOnly)
                } label: {
                    iOSNoLabelsFilterRow(
                        count: noLabelCount,
                        isSelected: labelFilter.showsUnlabeledOnly
                    )
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
                .accessibilityValue(labelFilter.showsUnlabeledOnly ? "Selected" : "Not selected")
            }

            if labelFilter.isActive {
                Section {
                    Button("Clear All Filters") {
                        labelFilter.clear()
                    }
                }
            }
        }
        .navigationTitle("Labels")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct iOSLabelRuleRow: View {
    let label: String
    let count: Int
    let rule: TorrentLabelRule

    var body: some View {
        HStack {
            Image(systemName: rule.systemImage)
                .foregroundStyle(rule.color)
                .accessibilityHidden(true)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}

private extension TorrentLabelRule {
    var systemImage: String {
        switch self {
        case .none:
            return "circle"
        case .include:
            return "checkmark.circle.fill"
        case .exclude:
            return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .none:
            return .secondary
        case .include:
            return .accent
        case .exclude:
            return .red
        }
    }
}

private struct iOSNoLabelsFilterRow: View {
    let count: Int
    let isSelected: Bool

    var body: some View {
        HStack {
            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isSelected ? Color.accent : Color.secondary)
                .accessibilityHidden(true)
            Text("No labels")
                .foregroundStyle(.primary)
                .italic()
            Spacer()
            Text("\(count)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .contentShape(.rect)
    }
}

private enum iOSStatusFilterOption: String, CaseIterable, Identifiable {
    case all = "All"
    case downloading = "Downloading"
    case complete = "Complete"
    case paused = "Paused"
    case excludeComplete = "Exclude Complete"

    var id: Self { self }

    var statuses: [TorrentStatusCalc] {
        switch self {
        case .all:
            return TorrentStatusCalc.allCases
        case .downloading:
            return [.downloading]
        case .complete:
            return [.complete]
        case .paused:
            return [.paused]
        case .excludeComplete:
            return TorrentStatusCalc.allCases.filter { $0 != .complete }
        }
    }
}
#endif

#if os(iOS) && DEBUG
#Preview("iOS Filter and Sort") {
    @Previewable @State var statusFilter = TorrentStatusCalc.allCases
    @Previewable @State var labelFilter = TorrentLabelFilter()
    @Previewable @State var sortProperty = SortProperty.name
    @Previewable @State var sortOrder = SortOrder.ascending

    iOSFilterAndSortView(
        statusFilter: $statusFilter,
        labelFilter: $labelFilter,
        sortProperty: $sortProperty,
        sortOrder: $sortOrder,
        availableLabels: ["Archive", "ISO", "Linux", "Movies"],
        labelCounts: ["Archive": 1, "ISO": 1, "Linux": 1, "Movies": 1],
        noLabelCount: 1
    )
}
#endif
