//
//  SessionOverviewIntent.swift
//  BitDreamWidgets
//

import AppIntents

struct SessionOverviewIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Session Overview"
    static var description = IntentDescription("Shows counts and speeds for a selected server.")

    @Parameter(title: "Server")
    var server: ServerEntity?

    init() { }

    init(server: ServerEntity?) {
        self.server = server
    }
}


