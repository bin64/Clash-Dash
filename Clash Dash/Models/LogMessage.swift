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