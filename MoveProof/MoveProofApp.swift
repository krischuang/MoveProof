//
//  MoveProofApp.swift
//  MoveProof
//
//  Created by Kai-Hsiang on 18/9/2026.
//

import SwiftUI
import CoreData

@main
struct MoveProofApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
