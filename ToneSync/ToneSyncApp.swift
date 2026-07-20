//
//  ToneSyncApp.swift
//  ToneSync
//
//  Created by Helmy LuqmanulHakim on 21/12/24.
//
//

import SwiftUI
import UserNotifications

@main
struct ToneSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { }  // Empty settings scene since we're using popover
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    var statusBarManager: StatusBarManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set up activation policy first
        DispatchQueue.main.async { [weak self] in
            self?.setupApp()
        }
    }

    private func setupApp() {
        // Hide dock icon
        NSApp.setActivationPolicy(.accessory)

        // Set up notification handling
        UNUserNotificationCenter.current().delegate = self

        // Request notification permissions
        requestNotificationPermissions()

        // Initialize status bar
        initializeStatusBar()

        // Register defaults
        registerDefaults()
    }

    private func requestNotificationPermissions() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            DispatchQueue.main.async {
                if granted {
                    print("Notification permission granted")
                } else if let error = error {
                    print("Notification permission error: \(error)")
                }
            }
        }
    }

    private func initializeStatusBar() {
        DispatchQueue.main.async { [weak self] in
            self?.statusBarManager = StatusBarManager()
        }
    }

    private func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            "AutoOptimizeOnLaunch": true
        ])
    }

    // Notification delegate methods
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        completionHandler()
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Clean up resources
        if let device = CameraManager.shared.currentDevice {
            CameraManager.shared.resetCamera(device)
        }
    }
}
