//
//  OutrunnApp.swift
//  outrunn
//

import SwiftUI

@main
struct OutrunnApp: App {
    init() {
        Neu.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.font, Neu.body())
                .background(Neu.canvas.ignoresSafeArea())
        }
    }
}
