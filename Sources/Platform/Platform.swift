import SwiftUI

#if os(iOS)
import UIKit
/// The system image type: UIImage on iPhone, NSImage on the Mac.
typealias PlatformImage = UIImage
#else
import AppKit
import ImageIO
import UniformTypeIdentifiers
typealias PlatformImage = NSImage
#endif

/// The few things that differ between the iPhone and the Mac, kept in one place so
/// views don't need `#if` blocks.
enum Platform {
    /// What the system settings app is called, for user-facing copy.
    static var settingsName: String {
        #if os(iOS)
        "iOS Settings"
        #else
        "System Settings"
        #endif
    }

    /// The device type, for user-facing copy.
    static var deviceName: String {
        #if os(iOS)
        "iPhone"
        #else
        "Mac"
        #endif
    }

    /// For example "iOS 26.1" or "macOS 26.1".
    @MainActor
    static var systemVersion: String {
        #if os(iOS)
        return "iOS \(UIDevice.current.systemVersion)"
        #else
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
        #endif
    }

    /// The hardware model, for example "iPhone17,3" or "Mac15,3".
    @MainActor
    static var hardwareModel: String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let model = withUnsafeBytes(of: &systemInfo.machine) { bytes in
            String(decoding: bytes.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
        return model.isEmpty ? UIDevice.current.model : model
        #else
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var bytes = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &bytes, &size, nil, 0)
        let model = String(decoding: bytes.prefix(while: { $0 != 0 }).map(UInt8.init), as: UTF8.self)
        return model.isEmpty ? "Mac" : model
        #endif
    }

    /// Opens the app's page in system settings, where calendar access is turned on.
    @MainActor
    static func openAppSettings() {
        #if os(iOS)
        open(UIApplication.openSettingsURLString)
        #else
        open("x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        #endif
    }

    /// Opens the app's notification settings.
    @MainActor
    static func openNotificationSettings() {
        #if os(iOS)
        open(UIApplication.openNotificationSettingsURLString)
        #else
        open("x-apple.systempreferences:com.apple.Notifications-Settings.extension")
        #endif
    }

    /// Opens a URL. `completion` says whether something could open it.
    @MainActor
    static func open(_ url: URL, completion: @escaping @MainActor (Bool) -> Void = { _ in }) {
        #if os(iOS)
        UIApplication.shared.open(url) { opened in
            Task { @MainActor in completion(opened) }
        }
        #else
        completion(NSWorkspace.shared.open(url))
        #endif
    }

    @MainActor
    private static func open(_ string: String) {
        if let url = URL(string: string) { open(url) }
    }

    /// Puts text on the clipboard.
    @MainActor
    static func copy(_ string: String) {
        #if os(iOS)
        UIPasteboard.general.string = string
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #endif
    }

    /// The image as a JPEG no larger than `maxDimension` on either side. Nil if it
    /// isn't an image.
    static func jpegData(from data: Data, maxDimension: CGFloat) -> Data? {
        #if os(iOS)
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.8)
        #else
        guard let image = thumbnail(from: data, maxDimension: maxDimension) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output, UTType.jpeg.identifier as CFString, 1, nil
        ) else { return nil }
        let options = [kCGImageDestinationLossyCompressionQuality: 0.8] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
        #endif
    }

    /// A small copy of the image for previews.
    static func thumbnailImage(from data: Data, maxDimension: CGFloat) -> PlatformImage? {
        #if os(iOS)
        UIImage(data: data)?.preparingThumbnail(of: CGSize(width: maxDimension, height: maxDimension))
        #else
        thumbnail(from: data, maxDimension: maxDimension).map {
            NSImage(cgImage: $0, size: CGSize(width: $0.width, height: $0.height))
        }
        #endif
    }

    #if os(macOS)
    /// Decodes and shrinks in one pass, turned upright to match the photo's orientation.
    private static func thumbnail(from data: Data, maxDimension: CGFloat) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
        ] as CFDictionary
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
    #endif
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(iOS)
        self.init(uiImage: platformImage)
        #else
        self.init(nsImage: platformImage)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Top left on iPhone, the start of the window toolbar on the Mac.
    static var udLeading: ToolbarItemPlacement {
        #if os(iOS)
        .topBarLeading
        #else
        .navigation
        #endif
    }

    /// Top right on iPhone, the end of the window toolbar on the Mac.
    static var udTrailing: ToolbarItemPlacement {
        #if os(iOS)
        .topBarTrailing
        #else
        .primaryAction
        #endif
    }
}

extension View {
    /// A small centered title on iPhone. The Mac has only one title style.
    func udInlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Space between list sections on iPhone. Mac lists set their own.
    func udListSectionSpacing(_ spacing: CGFloat) -> some View {
        #if os(iOS)
        listSectionSpacing(spacing)
        #else
        self
        #endif
    }

    /// Keeps a list in edit mode so rows show drag handles on iPhone. Mac lists
    /// reorder by dragging without it.
    func udAlwaysEditing() -> some View {
        #if os(iOS)
        environment(\.editMode, .constant(.active))
        #else
        self
        #endif
    }
}
