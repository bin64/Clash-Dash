import Foundation
import SwiftUI

final class LogManager: ObservableObject {
    static let shared = LogManager()
    @Published var logs: [LogEntry] = []
    
    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp: Date
        let message: String
        let level: LogLevel
        // 源信息：用于定位日志来源（Swift 文件、函数、行号）
        let fileID: String
        let function: String
        let line: Int
        
        var levelInfo: (String, Color) {
            switch level {
            case .info:
                return ("信息", .blue)
            case .warning:
                return ("警告", .orange)
            case .error:
                return ("错误", .red)
            case .debug:
                return ("调试", .secondary)
            }
        }
        
        // 便捷显示文件名（去掉模块和路径）
        var fileName: String {
            let parts = fileID.split(separator: "/")
            return parts.last.map(String.init) ?? fileID
        }
    }
    
    enum LogLevel {
        case info
        case warning
        case error
        case debug
        
        var color: Color {
            switch self {
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            case .debug: return .secondary
            }
        }
    }
    
    private init() {}
    
    // 使用编译器标识收集来源信息，保持默认参数以兼容旧调用
    func log(
        _ message: String,
        level: LogLevel = .info,
        fileID: String = #fileID,
        function: String = #function,
        line: Int = #line
    ) {
        DispatchQueue.main.async {
            self.logs.append(LogEntry(
                timestamp: Date(),
                message: message,
                level: level,
                fileID: fileID,
                function: function,
                line: line
            ))
            
            // 保持最近的 1000 条日志
            if self.logs.count > 1000 {
                self.logs.removeFirst(self.logs.count - 1000)
            }
        }
    }
    
    // 便捷方法（透传来源信息，确保捕获原始调用点）
    func info(_ message: String, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .info, fileID: fileID, function: function, line: line)
    }
    
    func warning(_ message: String, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .warning, fileID: fileID, function: function, line: line)
    }
    
    func error(_ message: String, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .error, fileID: fileID, function: function, line: line)
    }
    
    func debug(_ message: String, fileID: String = #fileID, function: String = #function, line: Int = #line) {
        log(message, level: .debug, fileID: fileID, function: function, line: line)
    }
    
    func clearLogs() {
        logs.removeAll()
    }
    
    // 导出文本：增加 includeSource 参数，保持默认值以兼容现有调用
    func exportLogs(includeSource: Bool = false) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        return logs.map { entry in
            let timePart = "[\(dateFormatter.string(from: entry.timestamp))]"
            let levelPart = "[\(entry.levelInfo.0)]"
            if includeSource {
                let sourcePart = "[\(entry.fileName):\(entry.line) \(entry.function)]"
                return "\(timePart) \(levelPart) \(sourcePart) \(entry.message)"
            } else {
                return "\(timePart) \(levelPart) \(entry.message)"
            }
        }.joined(separator: "\n")
    }
} 
