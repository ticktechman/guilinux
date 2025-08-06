//
//  linuxvm.swift
//  guilinux
//
//  Created by ticktech on 2025/8/4.
//

import Foundation
import Virtualization

let MB: UInt64 = 1024 * 1024

struct LinuxVirtualMachineProfile: Codable {
  var cpus: Int
  var memory: UInt64
  var kernel: String
  var initrd: String
  var storage: [String]
  var cmdline: String
  var network: Bool
  var uefi: Bool
  var shared: [String]
}

enum VirtualMachineStatus: Int, Comparable {
  case unloaded = 1
  case loaded = 2
  case starting = 3
  case started = 4
  case halting = 5
  case error = 6
  static func < (lhs: VirtualMachineStatus, rhs: VirtualMachineStatus) -> Bool {
    return lhs.rawValue < rhs.rawValue
  }
}

class LinuxVirtualMachine: NSObject, ObservableObject, VZVirtualMachineDelegate {
  @Published var log: String = "请先加载配置"
  @Published var status: VirtualMachineStatus = .unloaded

  private var vmachine_profile: LinuxVirtualMachineProfile?
  private var virtual_machine: VZVirtualMachine?

  public func loadProfile(path: String) -> Bool {
    do {
      let data = try Data(contentsOf: URL(filePath: path))
      vmachine_profile = try JSONDecoder().decode(LinuxVirtualMachineProfile.self, from: data)
    }
    catch {
      loge("加载配置失败:\(error)")
      return false
    }

    logi("加载配置成功~")
    status = .loaded
    return true
  }

  public func start(view: VZVirtualMachineView?) -> Bool {
    logi("虚拟机正在启动...")
    if view == nil {
      loge("无法使用空视图对象")
      return false
    }

    let config = createVirtualMachineConf(conf: vmachine_profile!)
    let vm = VZVirtualMachine(configuration: config!)

    view!.virtualMachine = vm
    virtual_machine = vm
    virtual_machine?.delegate = self
    status = .starting

    vm.start { result in
      DispatchQueue.main.async {
        switch result {
        case .success:
          self.logi("虚拟机已启动")
          self.status = .started
        case .failure(let error):
          self.loge("启动失败: \(error.localizedDescription)")
          self.status = .error
        }
      }
    }

    return true
  }

  public func stop() {
    logi("正在关机...")
    status = .halting
    virtual_machine?.stop { error in
      if let error = error {
        self.loge("关闭虚拟机失败：\(error.localizedDescription)")
        self.status = .loaded
      }
      else {
        self.logi("虚拟机已关闭")
        self.status = .loaded
      }
    }
  }

  func guestDidStop(_ virtualMachine: VZVirtualMachine) {
    logi("虚拟机停止")
    status = .loaded
  }

  //============================================
  private func logi(_ content: String) {
    log = "提示: \(content)"
  }
  private func loge(_ content: String) {
    log = "错误：\(content)"
  }

  private func createBootLoader(conf: LinuxVirtualMachineProfile) -> VZBootLoader {
    if conf.uefi {
      let bootloader = VZEFIBootLoader()
      do {
        bootloader.variableStore = try VZEFIVariableStore(
          creatingVariableStoreAt: URL(
            fileURLWithPath: "./efistore"
          ),
          options: [.allowOverwrite]
        )
      }
      catch {
        loge("无法创建EFI引导程序")
      }
      return bootloader
    }
    else {
      let boot = VZLinuxBootLoader(kernelURL: URL(fileURLWithPath: conf.kernel))
      if conf.initrd != "" {
        boot.initialRamdiskURL = URL(fileURLWithPath: conf.initrd)
      }
      boot.commandLine = conf.cmdline
      return boot
    }
  }

  private func createConsoleConfiguration() -> VZSerialPortConfiguration {
    let consoleConfiguration = VZVirtioConsoleDeviceSerialPortConfiguration()
    let inputFileHandle = FileHandle.standardInput
    let outputFileHandle = FileHandle.standardOutput
    var attributes = termios()
    tcgetattr(inputFileHandle.fileDescriptor, &attributes)
    attributes.c_iflag &= ~tcflag_t(ICRNL)
    attributes.c_lflag &= ~tcflag_t(ICANON | ECHO)
    tcsetattr(inputFileHandle.fileDescriptor, TCSANOW, &attributes)

    let stdioAttachment = VZFileHandleSerialPortAttachment(
      fileHandleForReading: inputFileHandle,
      fileHandleForWriting: outputFileHandle
    )

    consoleConfiguration.attachment = stdioAttachment
    return consoleConfiguration
  }

  private func createSpiceAgentConsoleDeviceConfiguration() -> VZVirtioConsoleDeviceConfiguration {
    let consoleDevice = VZVirtioConsoleDeviceConfiguration()

    let spiceAgentPort = VZVirtioConsolePortConfiguration()
    spiceAgentPort.name = VZSpiceAgentPortAttachment.spiceAgentPortName
    spiceAgentPort.attachment = VZSpiceAgentPortAttachment()
    consoleDevice.ports[0] = spiceAgentPort

    return consoleDevice
  }

  private func createVirtualMachineConf(conf: LinuxVirtualMachineProfile)
    -> VZVirtualMachineConfiguration?
  {
    let configuration = VZVirtualMachineConfiguration()
    configuration.cpuCount = conf.cpus
    configuration.memorySize = conf.memory * MB
    configuration.bootLoader = createBootLoader(conf: conf)
    configuration.serialPorts = [createConsoleConfiguration()]
    configuration.consoleDevices = [createSpiceAgentConsoleDeviceConfiguration()]
    configuration.graphicsDevices = [createGraphicsDeviceConfiguration()]
    configuration.keyboards = [VZUSBKeyboardConfiguration()]
    configuration.pointingDevices = [VZUSBScreenCoordinatePointingDeviceConfiguration()]

    do {
      for disk in conf.storage {
        let url = URL(fileURLWithPath: disk)
        let attachment = try VZDiskImageStorageDeviceAttachment(url: url, readOnly: false)
        let device = VZVirtioBlockDeviceConfiguration(attachment: attachment)
        configuration.storageDevices.append(device)
      }

      if conf.network {
        let networkDevice = VZVirtioNetworkDeviceConfiguration()
        networkDevice.attachment = VZNATNetworkDeviceAttachment()
        configuration.networkDevices = [networkDevice]
      }

      if !conf.shared.isEmpty {
        var dirs = [String: VZSharedDirectory]()
        for path in conf.shared {
          dirs[path] = VZSharedDirectory(url: URL(fileURLWithPath: path), readOnly: false)
        }
        let share = VZMultipleDirectoryShare(directories: dirs)
        let fs = VZVirtioFileSystemDeviceConfiguration(tag: "shared")
        fs.share = share
        configuration.directorySharingDevices = [fs]
      }

      try configuration.validate()
    }
    catch {
      loge("配置验证失败: \(error)")
      return nil
    }

    return configuration
  }
  private func createGraphicsDeviceConfiguration() -> VZVirtioGraphicsDeviceConfiguration {
    let graphicsDevice = VZVirtioGraphicsDeviceConfiguration()
    graphicsDevice.scanouts = [
      VZVirtioGraphicsScanoutConfiguration(widthInPixels: 1280, heightInPixels: 720)
    ]

    return graphicsDevice
  }
}
