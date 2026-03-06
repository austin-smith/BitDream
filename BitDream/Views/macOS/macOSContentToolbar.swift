import SwiftUI

#if os(macOS)

struct macOSContentToolbar: ToolbarContent {
    @Binding var sortProperty: SortProperty
    @Binding var sortOrder: SortOrder
    @Binding var showingFilterPopover: Bool
    let hasActiveFilters: Bool
    let activeFilterCount: Int
    let accentColor: Color
    let availableLabels: [String]
    @Binding var includedLabels: Set<String>
    @Binding var excludedLabels: Set<String>
    @Binding var showOnlyNoLabels: Bool
    let noLabelCount: Int
    let countForLabel: (String) -> Int
    @Binding var isCompactMode: Bool
    @Binding var isInspectorVisible: Bool
    let onAddTorrent: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .automatic) {
            Menu {
                macOSContentSortMenu(sortProperty: $sortProperty, sortOrder: $sortOrder)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down.circle")
            }
        }

        ToolbarItem(placement: .automatic) {
            Button(action: {
                showingFilterPopover.toggle()
            }, label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    .if(hasActiveFilters) { view in
                        view.foregroundColor(accentColor)
                    }
            })
            .help(hasActiveFilters ? "Active filters (\(activeFilterCount))" : "Filter torrents")
            .popover(isPresented: $showingFilterPopover, arrowEdge: .bottom) {
                macOSContentFilterMenu(
                    accentColor: accentColor,
                    availableLabels: availableLabels,
                    includedLabels: $includedLabels,
                    excludedLabels: $excludedLabels,
                    showOnlyNoLabels: $showOnlyNoLabels,
                    noLabelCount: noLabelCount,
                    countForLabel: countForLabel,
                    hasActiveFilters: hasActiveFilters
                )
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button(action: onAddTorrent) {
                Label("Add Torrent", systemImage: "plus")
            }
            .help("Add torrent")
        }

        ToolbarItem(placement: .automatic) {
            Button(action: {
                withAnimation {
                    isCompactMode.toggle()
                }
            }, label: {
                Label(
                    isCompactMode ? "Expanded View" : "Compact View",
                    systemImage: isCompactMode ? "rectangle.grid.1x2" : "list.bullet"
                )
            })
            .help(isCompactMode ? "Expanded view" : "Compact view")
        }

        ToolbarItem(placement: .automatic) {
            Button(action: {
                withAnimation {
                    isInspectorVisible.toggle()
                }
            }, label: {
                Label("Inspector", systemImage: "sidebar.right")
            })
            .help(isInspectorVisible ? "Hide inspector" : "Show inspector")
        }
    }
}

private struct macOSContentSortMenu: View {
    @Binding var sortProperty: SortProperty
    @Binding var sortOrder: SortOrder

    var body: some View {
        ForEach(SortProperty.allCases, id: \.self) { property in
            let isSelected = Binding<Bool>(
                get: { sortProperty == property },
                set: { if $0 { sortProperty = property } }
            )
            Toggle(isOn: isSelected) {
                Text(property.rawValue)
            }
        }

        Divider()

        let isAscending = Binding<Bool>(
            get: { sortOrder == .ascending },
            set: { if $0 { sortOrder = .ascending } }
        )
        Toggle(isOn: isAscending) {
            Text("Ascending")
        }

        let isDescending = Binding<Bool>(
            get: { sortOrder == .descending },
            set: { if $0 { sortOrder = .descending } }
        )
        Toggle(isOn: isDescending) {
            Text("Descending")
        }
    }
}

private struct macOSContentFilterMenu: View {
    let accentColor: Color
    let availableLabels: [String]
    @Binding var includedLabels: Set<String>
    @Binding var excludedLabels: Set<String>
    @Binding var showOnlyNoLabels: Bool
    let noLabelCount: Int
    let countForLabel: (String) -> Int
    let hasActiveFilters: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Section("Filter by Labels") {
                if !availableLabels.isEmpty {
                    ForEach(availableLabels, id: \.self) { label in
                        Button(action: {
                            toggleLabelFilter(label)
                        }, label: {
                            HStack {
                                Image(systemName: filterIcon(for: label))
                                    .foregroundColor(filterColor(for: label))

                                Text(label)
                                    .foregroundColor(.primary)

                                Spacer()

                                Text("\(countForLabel(label))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .contentShape(Rectangle())
                        })
                        .buttonStyle(.plain)
                    }

                    Divider()
                }

                Button(action: toggleNoLabelsFilter, label: {
                    HStack {
                        Image(systemName: showOnlyNoLabels ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(showOnlyNoLabels ? accentColor : .secondary)

                        Text("No labels")
                            .foregroundColor(.primary)
                            .italic()

                        Spacer()

                        Text("\(noLabelCount)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .contentShape(Rectangle())
                })
                .buttonStyle(.plain)
            }

            if hasActiveFilters {
                Divider()
                Button("Clear All Filters") {
                    clearFilters()
                }
            }
        }
        .padding()
        .frame(minWidth: 250)
    }

    private func filterIcon(for label: String) -> String {
        if includedLabels.contains(label) {
            return "checkmark.circle.fill"
        }
        if excludedLabels.contains(label) {
            return "minus.circle.fill"
        }
        return "circle"
    }

    private func filterColor(for label: String) -> Color {
        if includedLabels.contains(label) {
            return accentColor
        }
        if excludedLabels.contains(label) {
            return .red
        }
        return .secondary
    }

    private func toggleLabelFilter(_ label: String) {
        if showOnlyNoLabels {
            showOnlyNoLabels = false
        }

        if includedLabels.contains(label) {
            includedLabels.remove(label)
            excludedLabels.insert(label)
        } else if excludedLabels.contains(label) {
            excludedLabels.remove(label)
        } else {
            includedLabels.insert(label)
        }
    }

    private func toggleNoLabelsFilter() {
        showOnlyNoLabels.toggle()

        if showOnlyNoLabels {
            includedLabels.removeAll()
            excludedLabels.removeAll()
        }
    }

    private func clearFilters() {
        includedLabels.removeAll()
        excludedLabels.removeAll()
        showOnlyNoLabels = false
    }
}

#endif
