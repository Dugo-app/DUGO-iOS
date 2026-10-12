//
//  ForceUpdateGate.swift
//  DuGo-iOS
//
//  Created by 김승원 on 4/10/26.
//

import SwiftUI

struct ForceUpdateGate<Content: View>: View {
    // MARK: - Properties

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    @StateObject private var monitor = AppVersionMonitor()

    private let content: Content

    // MARK: - Initializer

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    // MARK: - Body

    var body: some View {
        content
            .allowsHitTesting(!monitor.isUpdateRequired)
            .alert(monitor.alertTitle, isPresented: $monitor.isAlertPresented) {
                if !monitor.isUpdateRequired {
                    Button("나중에", role: .cancel) {
                        monitor.dismissOptionalUpdate()
                    }
                }

                Button("업데이트") {
                    monitor.dismissOptionalUpdate()
                    openAppStore()
                }
                .tint(DuGoTheme.accent)
            } message: {
                Text(monitor.alertMessage)
            }
            .onAppear {
                monitor.startListeningForUpdates()
            }
            .onDisappear {
                monitor.stopListeningForUpdates()
            }
            .task {
                await monitor.checkForUpdate()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                monitor.presentAlertIfNeeded()
                Task { await monitor.checkForUpdate() }
            }
    }

    // MARK: - Methods

    private func openAppStore() {
        guard let url = monitor.appStoreURL else {
            monitor.presentAlertIfNeeded()
            return
        }

        openURL(url) { accepted in
            guard !accepted else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(250))
                monitor.presentAlertIfNeeded()
            }
        }
    }
}
