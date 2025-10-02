import Foundation

// 订阅卡片样式
public enum SubscriptionCardStyle: String, CaseIterable, Codable {
    case classic = "紧凑"
    case modern = "简洁"
    
    var description: String {
        return self.rawValue
    }
}

// 代理切换卡片样式
public enum ModeSwitchCardStyle: String, CaseIterable, Codable {
    case classic = "紧凑"
    case modern = "简洁"
    
    var description: String {
        return self.rawValue
    }
}

// 订阅信息卡片数据模型
public struct SubscriptionCardInfo: Identifiable, Codable, Sendable {
    public let id: UUID
    public let name: String?
    public let expiryDate: Date?
    public let lastUpdateTime: Date
    public let usedTraffic: Double
    public let totalTraffic: Double
    
    public init(name: String?, expiryDate: Date?, lastUpdateTime: Date, usedTraffic: Double, totalTraffic: Double) {
        self.id = UUID()
        self.name = name
        self.expiryDate = expiryDate
        self.lastUpdateTime = lastUpdateTime
        self.usedTraffic = usedTraffic
        self.totalTraffic = totalTraffic
    }
    
    public var percentageUsed: Double {
        guard totalTraffic > 0 else { return 0 }
        return (usedTraffic / totalTraffic * 100).rounded(to: 1)
    }
    
    public var remainingTraffic: Double {
        guard totalTraffic > 0 else { return 0 }
        return totalTraffic - usedTraffic
    }
} 