import SwiftUI
import UIKit

/// 设备检测工具
struct DeviceDetection {
    
    /// 设备类型枚举
    enum DeviceType {
        case iPhone
        case iPad
        case mac
    }
    
    /// 屏幕尺寸类别
    enum ScreenSize {
        case compact    // iPhone 竖屏
        case regular    // iPad 或 iPhone 横屏
        case expanded   // Mac 或超大 iPad
    }
    
    /// 当前设备类型
    static var deviceType: DeviceType {
        #if targetEnvironment(macCatalyst)
        return .mac
        #else
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            return .iPhone
        case .pad:
            return .iPad
        default:
            return .iPhone
        }
        #endif
    }
    
    /// 是否为大屏设备（iPad 或 Mac）
    static var isLargeScreen: Bool {
        deviceType == .iPad || deviceType == .mac
    }
    
    /// 根据水平Size Class判断屏幕尺寸
    static func screenSize(for horizontalSizeClass: UserInterfaceSizeClass?) -> ScreenSize {
        switch horizontalSizeClass {
        case .compact:
            return .compact
        case .regular:
            if deviceType == .mac {
                return .expanded
            }
            return .regular
        default:
            return .compact
        }
    }
}

/// SwiftUI环境值扩展
struct DeviceTypeKey: EnvironmentKey {
    static let defaultValue = DeviceDetection.DeviceType.iPhone
}

extension EnvironmentValues {
    var deviceType: DeviceDetection.DeviceType {
        get { self[DeviceTypeKey.self] }
        set { self[DeviceTypeKey.self] = newValue }
    }
} 