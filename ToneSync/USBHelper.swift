//
// Created by Helmy LuqmanulHakim on 21/12/24.
//

import Foundation
import IOKit
import IOKit.usb

class USBHelper {
    static func findUSBDevice(withVendorID vendorID: Int, productID: Int) -> io_service_t? {
        let matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as NSMutableDictionary
        matchingDict[kUSBVendorID] = NSNumber(value: vendorID)
        matchingDict[kUSBProductID] = NSNumber(value: productID)

        var iterator: io_iterator_t = 0
        let result = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict, &iterator)

        guard result == KERN_SUCCESS else {
            return nil
        }

        let device = IOIteratorNext(iterator)
        IOObjectRelease(iterator)

        return device != 0 ? device : nil
    }

    static func getUSBDeviceInfo(device: io_service_t) -> (vendorID: Int, productID: Int, productName: String?)? {
        var vendorID: Int = 0
        var productID: Int = 0
        var productName: String?

        var propertyIterator: io_iterator_t = 0
        let result = IORegistryEntryCreateIterator(
                device,
                kIOServicePlane,
                IOOptionBits(kIORegistryIterateRecursively),
                &propertyIterator
        )

        guard result == KERN_SUCCESS else {
            return nil
        }

        var current = IOIteratorNext(propertyIterator)
        while current != 0 {
            var propertyDict: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(current, &propertyDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propertyDict?.takeRetainedValue() as NSDictionary? {
                if let idVendor = dict["idVendor"] as? Int {
                    vendorID = idVendor
                }
                if let idProduct = dict["idProduct"] as? Int {
                    productID = idProduct
                }
                if let name = dict["USB Product Name"] as? String {
                    productName = name
                }
            }
            IOObjectRelease(current)
            current = IOIteratorNext(propertyIterator)
        }

        IOObjectRelease(propertyIterator)

        return (vendorID, productID, productName)
    }

    /// Returns true if the given USB device's product name matches (or is contained in / contains)
    /// the AVCaptureDevice's localized name, so that camera controls are only ever applied to the
    /// specific USB device backing the selected camera rather than every device sharing a vendor ID.
    static func matchesCamera(productName: String?, cameraName: String) -> Bool {
        guard let productName = productName, !productName.isEmpty else { return false }
        let normalizedProduct = productName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let normalizedCamera = cameraName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedProduct.isEmpty, !normalizedCamera.isEmpty else { return false }
        return normalizedCamera.contains(normalizedProduct) || normalizedProduct.contains(normalizedCamera)
    }

    static func isControlSupported(device: io_service_t, control: UInt8) -> Bool {
        var supported = false
        var propertyIterator: io_iterator_t = 0

        let result = IORegistryEntryCreateIterator(
                device,
                kIOServicePlane,
                IOOptionBits(kIORegistryIterateRecursively),
                &propertyIterator
        )

        guard result == KERN_SUCCESS else {
            return false
        }

        defer {
            IOObjectRelease(propertyIterator)
        }

        var current = IOIteratorNext(propertyIterator)
        while current != 0 {
            defer {
                IOObjectRelease(current)
                current = IOIteratorNext(propertyIterator)
            }

            var propertyDict: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(current, &propertyDict, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let dict = propertyDict?.takeRetainedValue() as NSDictionary? {
                if let controls = dict["SupportedControls"] as? [String: Any] {
                    let controlKey = String(format: "UVC_CTRL_%02X", control)
                    supported = controls[controlKey] != nil
                    if supported {
                        break
                    }
                }
            }
        }

        return supported
    }
}