//
//  BackApp.swift
//  Back
//
//  Created by Furkan Öztürk on 9/19/25.
//

import SwiftUI
import SwiftData

@main
struct BackApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            SessionRecord.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
