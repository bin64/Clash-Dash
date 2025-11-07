import Foundation
import SwiftUI

struct LogMessage: Identifiable, Codable, Equatable {
    let id = UUID()
    let type: LogType
    let payload: String
    let timestamp: Date
    
    enum LogType: String, Codable, Equatable {
        case info = "info"
        case warning = "warning"
        case error = "error"
        case debug = "debug"
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            case .debug: return .secondary
            }
        }
        
        var displayText: String {
            rawValue.uppercased()
        }
    }
    
    enum CodingKeys: String, CodingKey {
        case type, payload
    }
    
    init(type: LogType, payload: String, timestamp: Date = Date()) {
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(LogType.self, forKey: .type)
        payload = try container.decode(String.self, forKey: .payload)
        timestamp = Date()
    }
    
    static func == (lhs: LogMessage, rhs: LogMessage) -> Bool {
        lhs.id == rhs.id &&
        lhs.type == rhs.type &&
        lhs.payload == rhs.payload &&
        lhs.timestamp == rhs.timestamp
    }
}

// Surge 事件数据模型
struct SurgeEvent: Identifiable, Codable {
    let identifier: String  // API 返回的字段名是 identifier
    let date: String  // ISO 8601 格式的时间字符串
    let type: Int     // 0=信息, 1=警告, 2=错误
    let allowDismiss: Bool  // API 返回的是布尔值，不是整数
    let content: String

    // 实现 Identifiable 协议
    var id: String { identifier }

    var logType: LogMessage.LogType {
        switch type {
        case 0: return .info
        case 1: return .warning
        case 2: return .error
        default: return .info
        }
    }

    var timestamp: Date {
        // 解析 ISO 8601 格式的日期字符串
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        return formatter.date(from: date) ?? Date()
    }

    var logMessage: LogMessage {
        LogMessage(type: logType, payload: content, timestamp: timestamp)
    }
}

// Surge 事件列表响应
struct SurgeEventList: Codable {
    let events: [SurgeEvent]
}