//
//  guilinuxApp.swift
//  guilinux
//
//  Created by ticktech on 2025/8/4.
//

import SwiftUI

@main
struct guilinuxApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
  var body: some Scene {
    WindowGroup {
      ContentView()
        .frame(minWidth: 800, minHeight: 480)
    }
    .commandsRemoved()
    .commands {
      CommandGroup(replacing: .appTermination) {
        Button("退出") {
          print("quit")
          NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
      }
    }
  }
}

class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    if let mainMenu = NSApplication.shared.mainMenu {
      if let viewMenuItemIndex = mainMenu.items.firstIndex(where: { $0.title == "View" }) {
        mainMenu.removeItem(at: viewMenuItemIndex)
      }
    }
  }

  // terminate app
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
}
