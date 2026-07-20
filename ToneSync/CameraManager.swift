//
// Created by Helmy LuqmanulHakim on 21/12/24.
//

import AVFoundation
import Foundation
import IOKit
import IOKit.usb


class CameraManager: NSObject {
    static let shared = CameraManager()

    var currentDevice: CaptureDevice? {
        didSet {
            guard let device = currentDevice else { return }
            if oldValue?.avDevice.uniqueID == device.avDevice.uniqueID { return }
            observeUsage(for: device)
            updateOptimizationState()
        }
    }
    var availableDevices: [CaptureDevice] = []
    private(set) var isOptimized: Bool = false

    private var usageObservation: NSKeyValueObservation?
    private var discoverySession: AVCaptureDevice.DiscoverySession?

    override init() {
        super.init()
        loadDevices()
        observeDeviceConnections()
    }

    private func updateOptimizationState() {
        guard let device = currentDevice else { return }

        if device.avDevice.isInUseByAnotherApplication {
            if !isOptimized {
                optimizeCamera(device)
            }
        } else {
            if isOptimized {
                resetCamera(device)
            }
        }
    }

    private func observeUsage(for device: CaptureDevice) {
        usageObservation?.invalidate()
        usageObservation = device.avDevice.observe(\.isInUseByAnotherApplication, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateOptimizationState()
            }
        }
    }

    private func observeDeviceConnections() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnectionChange),
            name: .AVCaptureDeviceWasConnected,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDeviceConnectionChange),
            name: .AVCaptureDeviceWasDisconnected,
            object: nil
        )
    }

    @objc private func handleDeviceConnectionChange() {
        DispatchQueue.main.async { [weak self] in
            self?.loadDevices()
        }
    }

    func loadDevices() {
        if discoverySession == nil {
            let deviceTypes: [AVCaptureDevice.DeviceType]
            if #available(macOS 14.0, *) {
                deviceTypes = [.external, .builtInWideAngleCamera]
            } else {
                deviceTypes = [.externalUnknown, .builtInWideAngleCamera]
            }
            discoverySession = AVCaptureDevice.DiscoverySession(
                deviceTypes: deviceTypes,
                mediaType: .video,
                position: .unspecified
            )
        }

        availableDevices = discoverySession?.devices.map { device in
            CaptureDevice(device: device)
        } ?? []

        if let current = currentDevice, availableDevices.contains(where: { $0.avDevice.uniqueID == current.avDevice.uniqueID }) {
            return
        }

        currentDevice = availableDevices.first
    }

    func optimizeCamera(_ device: CaptureDevice) {
        do {
            isOptimized = false
            try device.avDevice.lockForConfiguration()

            if device.avDevice.isWhiteBalanceModeSupported(.locked) {
                device.avDevice.whiteBalanceMode = .locked
            }

            if device.avDevice.isExposureModeSupported(.locked) {
                device.avDevice.exposureMode = .locked
            }

            applyUSBControls(for: device)

            if device.avDevice.isExposureModeSupported(.continuousAutoExposure) {
                device.avDevice.exposureMode = .continuousAutoExposure
            }

            if device.avDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.avDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            device.avDevice.unlockForConfiguration()
            isOptimized = true
        } catch {
            print("Could not configure camera: \(error)")
            isOptimized = false
        }
    }

    /// Applies vendor-specific USB controls only to the USB device that actually backs `device`,
    /// matched by product name, instead of blindly touching every USB device sharing a vendor ID.
    private func applyUSBControls(for device: CaptureDevice) {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching(kIOUSBDeviceClassName)
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matching, &iterator)

        guard result == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var usbDevice = IOIteratorNext(iterator)
        while usbDevice != 0 {
            defer {
                IOObjectRelease(usbDevice)
                usbDevice = IOIteratorNext(iterator)
            }

            guard let info = USBHelper.getUSBDeviceInfo(device: usbDevice),
                  USBHelper.matchesCamera(productName: info.productName, cameraName: device.name) else {
                continue
            }

            switch info.vendorID {
            case 0x046d: // Logitech
                optimizeLogitech(usbDevice)
            case 0x0c45: // Microdia/Generic
                optimizeGeneric(usbDevice)
            default:
                optimizeGeneric(usbDevice)
            }
        }
    }

    private func optimizeLogitech(_ device: io_service_t) {
        // Logitech specific optimizations
        // Set common Logitech webcam controls for better skin tones
        let controls: [(UInt8, UInt8)] = [
            (0x81, 0x03), // Auto exposure off
            (0x82, 0x80), // Manual exposure value
            (0x80, 0x04), // Manual white balance
            (0x83, 0x60), // White balance temperature
            (0x84, 0x70), // Contrast
            (0x85, 0x60), // Brightness
            (0x86, 0x60), // Saturation
            (0x87, 0x50)  // Sharpness
        ]

        for (control, value) in controls {
            if USBHelper.isControlSupported(device: device, control: control) {
                sendUSBControl(device: device, request: control, value: value)
            }
        }
    }

    private func optimizeGeneric(_ device: io_service_t) {
        // Generic USB webcam optimizations
        // Use standard UVC controls
        let controls: [(UInt8, UInt8)] = [
            (0x02, 0x01), // Manual mode
            (0x03, 0x80), // Exposure
            (0x04, 0x80), // Brightness
            (0x05, 0x80), // Contrast
            (0x06, 0x80), // Gain
            (0x07, 0x80), // Saturation
            (0x08, 0x40)  // White balance
        ]

        for (control, value) in controls {
            if USBHelper.isControlSupported(device: device, control: control) {
                sendUSBControl(device: device, request: control, value: value)
            }
        }
    }

    private func sendUSBControl(device: io_service_t, request: UInt8, value: UInt8) {
        var dataSize: Int = 1
        var data: UInt8 = value

        let kr = IORegistryEntrySetCFProperty(
                device,
                ("UVC_CTRL_" + String(format: "%02X", request)) as CFString,
                NSData(bytes: &data, length: dataSize) as CFData
        )

        if kr != KERN_SUCCESS {
            #if DEBUG
            print("Failed to set USB control: \(String(format: "0x%02X", request))")
            #endif
        }
    }

    func resetCamera(_ device: CaptureDevice) {
        do {
            isOptimized = false
            try device.avDevice.lockForConfiguration()

            if device.avDevice.isExposureModeSupported(.continuousAutoExposure) {
                device.avDevice.exposureMode = .continuousAutoExposure
            }

            if device.avDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                device.avDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            device.avDevice.unlockForConfiguration()
        } catch {
            print("Could not reset camera: \(error)")
        }
    }


    deinit {
        usageObservation?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}