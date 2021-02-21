//
//  DigiFrameApp.swift
//  Shared
//
//  Created by Stephen Byatt on 26/11/20.
//

import SwiftUI

@main
struct DigiFrameApp: App {
    @ObservedObject var model = Model()
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
        }
    }
}
