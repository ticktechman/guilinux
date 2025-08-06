//
//  ContentView.swift
//  guilinux
//
//  Created by ticktech on 2025/8/4.
//

import SwiftUI
import Virtualization

struct VirtualMachineContainer: NSViewRepresentable {
  var onViewCreated: (VZVirtualMachineView) -> Void

  func makeNSView(context: Context) -> VZVirtualMachineView {
    let vmView = VZVirtualMachineView()

    DispatchQueue.main.async {
      onViewCreated(vmView)
    }

    return vmView
  }

  func updateNSView(_ nsView: VZVirtualMachineView, context: Context) {
  }
}

struct ContentView: View {
  @State private var statusMessage: String = ""
  @State private var status: VirtualMachineStatus = .unloaded
  @StateObject var linux = LinuxVirtualMachine()
  @State private var vmViewRef: VZVirtualMachineView?
  var body: some View {
    VStack(spacing: 4) {
      HStack {
        Spacer()
        Button {
          loadConfiguration()
        } label: {
          Text("加载配置")
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }.padding(.trailing, 8)
          .disabled(status > .loaded)

        Button {
          startVM()
        } label: {
          Text("启动")
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .padding(.trailing, 12)
        .disabled(status != .loaded)

        Button {
          shutdownVM()
        } label: {
          Text("关机")
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
        .padding(.trailing, 12)
        .disabled(status <= .loaded)
        Spacer()
      }
      .padding(.top, 4)

      Divider().padding(.horizontal, 2)

      // 主虚拟机视图
      VirtualMachineContainer { vmView in
        self.vmViewRef = vmView
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .padding(.all, 2)
      .cornerRadius(10)

      Divider().padding(.horizontal, 2)

      // 状态栏
      HStack {
        Text("\(statusMessage)")
          .font(.none)
          .padding(.leading, 20)
          .padding(.vertical, 10)
        Spacer()
      }
      .background(Color(red: 1, green: 1, blue: 1).opacity(0.1))
    }
    .onReceive(linux.$log) { log in
      statusMessage = log
    }
    .onReceive(linux.$status) { vmstatus in
      status = vmstatus
    }
  }

  // 加载配置
  func loadConfiguration() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.allowedContentTypes = [.json]

    if panel.runModal() == .OK, let url = panel.url {
      let started = linux.loadProfile(path: url.path())
      if started {
        if let window = NSApp.keyWindow {
          window.title = url.lastPathComponent
        }
      }
      let setCurrentPath = FileManager.default.changeCurrentDirectoryPath
      _ = setCurrentPath(url.deletingLastPathComponent().path())
    }
  }

  func startVM() {
    _ = linux.start(view: vmViewRef)
  }

  func shutdownVM() {
    linux.stop()
  }
}

#Preview {
  ContentView()
}
