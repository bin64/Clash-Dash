import Foundation
import Combine

// 将 LogType 移到外部，使其成为独立的类型
enum ServiceLogType: String, CaseIterable {
    case plugin = "插件日志"
    case kernel = "内核日志"
}

@MainActor
class ServiceLogViewModel: ObservableObject {
    private let server: ClashServer
    @Published private(set) var logs: [ServiceLogEntry] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private var cancellables = Set<AnyCancellable>()
    private var currentLogType: ServiceLogType = .plugin
    private let maxLogLines = 1000  // 最大日志行数
    
    init(server: ClashServer) {
        self.server = server
    }
    
    func fetchLogs(type: ServiceLogType) {
        currentLogType = type
        isLoading = true
        error = nil
        
        switch server.luciPackage {
        case .openClash:
            switch type {
            case .plugin:
                fetchOpenClashPluginLog()
            case .kernel:
                fetchOpenClashKernelLog()
            }
            
        case .mihomoTProxy:
            switch type {
            case .plugin:
                fetchMihomoTProxyPluginLog()
            case .kernel:
                fetchMihomoTProxyKernelLog()
            }
        }
    }
    
    private func fetchOpenClashPluginLog() {
        Task {
            do {
                let logs = try await fetchOpenClashLog(path: "/tmp/openclash.log")
                let entries = logs.compactMap { line -> ServiceLogEntry? in
                    guard !line.contains("time=") else { return nil }
                    return parsePluginLogLine(line)
                }
                // 只保留最新的日志
                self.logs = Array(entries.suffix(maxLogLines))
                self.isLoading = false
            } catch {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func fetchOpenClashKernelLog() {
        Task {
            do {
                let logs = try await fetchOpenClashLog(path: "/tmp/openclash.log")
                let entries = logs.compactMap { line -> ServiceLogEntry? in
                    guard line.contains("time=") else { return nil }
                    return parseKernelLogLine(line)
                }
                // 只保留最新的日志
                self.logs = Array(entries.suffix(maxLogLines))
                self.isLoading = false
            } catch {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func fetchOpenClashLog(path: String) async throws -> [String] {
        let scheme = server.openWRTUseSSL ? "https" : "http"
        guard let openWRTUrl = server.openWRTUrl,
              let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            throw ServiceLogError.invalidServer
        }
        
        let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
        
        // 获取认证令牌
        let token = try await ServerViewModel().getAuthToken(server, username: username, password: password)
        
        // 构建请求 URL
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw ServiceLogError.invalidServer
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token); sysauth_https=\(token)", forHTTPHeaderField: "Cookie")
        
        // 使用 tail 命令只获取最新的日志
        let requestBody: [String: Any] = [
            "id": 1,
            "method": "exec",
            "params": ["tail -n \(maxLogLines) \(path)"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.secure.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServiceLogError.fetchFailed
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw ServiceLogError.parseError
        }
        
        return result.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }
    
    private func parsePluginLogLine(_ line: String) -> ServiceLogEntry? {
        // 插件日志格式：2025-01-10 17:04:32 Step 5: Set Dnsmasq...
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // 尝试提取时间戳和消息
        let components = line.split(separator: " ", maxSplits: 2)
        guard components.count >= 3,
              let date = dateFormatter.date(from: "\(components[0]) \(components[1])") else {
            return nil
        }
        
        let message = String(components[2...].joined(separator: " "))
        
        // 确定日志级别
        let level: ServiceLogEntry.LogLevel
        if message.lowercased().contains("error") {
            level = .error
        } else if message.lowercased().contains("warning") {
            level = .warning
        } else if message.lowercased().contains("tip") {
            level = .info
        } else {
            level = .debug
        }
        
        return ServiceLogEntry(timestamp: date, message: message, level: level)
    }
    
    private func parseKernelLogLine(_ line: String) -> ServiceLogEntry? {
        // 内核日志格式：time="2025-01-10T09:04:34.913541326Z" level=info msg="Start initial configuration in progress"
        
        // 提取时间戳
        guard let timeRange = line.range(of: #"time="([^"]+)""#, options: .regularExpression),
              let time = line[timeRange].split(separator: "\"")[1].split(separator: "\"").first else {
            return nil
        }
        
        // 解析时间戳
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        guard let date = dateFormatter.date(from: String(time)) else {
            return nil
        }
        
        // 提取日志级别
        let level: ServiceLogEntry.LogLevel
        if line.contains("level=error") {
            level = .error
        } else if line.contains("level=warn") {
            level = .warning
        } else if line.contains("level=info") {
            level = .info
        } else {
            level = .debug
        }
        
        // 提取消息内容
        guard let msgRange = line.range(of: #"msg="([^"]+)""#, options: .regularExpression),
              let msg = line[msgRange].split(separator: "\"")[1].split(separator: "\"").first else {
            return nil
        }
        
        return ServiceLogEntry(timestamp: date, message: String(msg), level: level)
    }
    
    private func fetchMihomoTProxyPluginLog() {
        Task {
            do {
                let packageName = try await getPackageName()
                let logs = try await fetchMihomoTProxyLog(path: "/var/log/\(packageName)/app.log")
                let entries = logs.compactMap { line -> ServiceLogEntry? in
                    return parseMihomoTProxyPluginLogLine(line)
                }
                // 只保留最新的日志
                self.logs = Array(entries.suffix(maxLogLines))
                self.isLoading = false
            } catch {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func fetchMihomoTProxyKernelLog() {
        Task {
            do {
                let packageName = try await getPackageName()
                let logs = try await fetchMihomoTProxyLog(path: "/var/log/\(packageName)/core.log")
                let entries = logs.compactMap { line -> ServiceLogEntry? in
                    return parseKernelLogLine(line)  // 可以复用 OpenClash 的内核日志解析，因为格式相同
                }
                // 只保留最新的日志
                self.logs = Array(entries.suffix(maxLogLines))
                self.isLoading = false
            } catch {
                self.error = error
                self.isLoading = false
            }
        }
    }
    
    private func fetchMihomoTProxyLog(path: String) async throws -> [String] {
        let scheme = server.openWRTUseSSL ? "https" : "http"
        guard let openWRTUrl = server.openWRTUrl,
              let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            throw ServiceLogError.invalidServer
        }
        
        let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
        
        // 获取认证令牌
        let token = try await ServerViewModel().getAuthToken(server, username: username, password: password)
        
        // 构建请求 URL
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw ServiceLogError.invalidServer
        }
        
        // 创建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token); sysauth_https=\(token)", forHTTPHeaderField: "Cookie")
        
        // 使用 tail 命令只获取最新的日志
        let requestBody: [String: Any] = [
            "id": 1,
            "method": "exec",
            "params": ["tail -n \(maxLogLines) \(path)"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.secure.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServiceLogError.fetchFailed
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = json["result"] as? String else {
            throw ServiceLogError.parseError
        }
        
        return result.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
    }
    
    private func parseMihomoTProxyPluginLogLine(_ line: String) -> ServiceLogEntry? {
        // 插件日志格式：[2025-01-10 19:18:35] [App] Enabled.
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        
        // 使用正则表达式提取时间戳和消息
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] \[([^\]]+)\] (.*)"#),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
            return nil
        }
        
        // 提取时间戳
        guard let timeRange = Range(match.range(at: 1), in: line),
              let date = dateFormatter.date(from: String(line[timeRange])) else {
            return nil
        }
        
        // 提取组件和消息
        guard let componentRange = Range(match.range(at: 2), in: line),
              let messageRange = Range(match.range(at: 3), in: line) else {
            return nil
        }
        
        let component = String(line[componentRange])
        let message = "\(component): \(line[messageRange])"
        
        // 确定日志级别
        let level: ServiceLogEntry.LogLevel
        if message.lowercased().contains("error") {
            level = .error
        } else if message.lowercased().contains("warning") {
            level = .warning
        } else if component == "App" {
            level = .info
        } else {
            level = .debug
        }
        
        return ServiceLogEntry(timestamp: date, message: message, level: level)
    }
    
    private func parseLogLine(_ line: String) -> ServiceLogEntry? {
        // TODO: 实现日志行解析逻辑
        // 1. 解析时间戳
        // 2. 解析日志级别
        // 3. 解析日志消息
        // 4. 返回 ServiceLogEntry 实例
        return nil
    }
    
    func clearLogs() async throws {
        switch server.luciPackage {
        case .openClash:
            try await clearOpenClashLog()
        case .mihomoTProxy:
            try await clearMihomoTProxyLog()
        }
    }
    
    private func clearOpenClashLog() async throws {
        let scheme = server.openWRTUseSSL ? "https" : "http"
        guard let openWRTUrl = server.openWRTUrl,
              let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            throw ServiceLogError.invalidServer
        }
        
        let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
        let token = try await ServerViewModel().getAuthToken(server, username: username, password: password)
        
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw ServiceLogError.invalidServer
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token); sysauth_https=\(token)", forHTTPHeaderField: "Cookie")
        
        let requestBody: [String: Any] = [
            "id": 1,
            "method": "exec",
            "params": ["cat /dev/null > /tmp/openclash.log"]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (_, response) = try await URLSession.secure.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServiceLogError.clearFailed
        }
        
        // 清理成功后清空本地日志数组
        await MainActor.run {
            logs.removeAll()
        }
    }
    
    private func clearMihomoTProxyLog() async throws {
        let scheme = server.openWRTUseSSL ? "https" : "http"
        guard let openWRTUrl = server.openWRTUrl,
              let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            throw ServiceLogError.invalidServer
        }
        
        let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
        let token = try await ServerViewModel().getAuthToken(server, username: username, password: password)
        
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw ServiceLogError.invalidServer
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token); sysauth_https=\(token)", forHTTPHeaderField: "Cookie")
        
        let packageName = try await getPackageName()
        
        // 根据日志类型选择清理命令
        let clearCommand = currentLogType == .plugin ? 
            "/usr/libexec/\(packageName)-call clear_log app" : 
            "/usr/libexec/\(packageName)-call clear_log core"
        
        let requestBody: [String: Any] = [
            "id": 1,
            "method": "exec",
            "params": [clearCommand]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (_, response) = try await URLSession.secure.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw ServiceLogError.clearFailed
        }
        
        // 清理成功后清空本地日志数组
        await MainActor.run {
            logs.removeAll()
        }
    }
    
    // 添加一个辅助方法来获取包名
    private func getPackageName() async throws -> String {
        let serverViewModel = ServerViewModel()
        let isNikki = try await serverViewModel.checkIsUsingNikki(server)
        return isNikki ? "nikki" : "mihomo"
    }
}

// 扩展 Error 类型
enum ServiceLogError: LocalizedError {
    case fetchFailed
    case parseError
    case invalidServer
    case clearFailed
    
    var errorDescription: String? {
        switch self {
        case .fetchFailed:
            return "获取日志失败"
        case .parseError:
            return "解析日志失败"
        case .invalidServer:
            return "无效的服务器配置"
        case .clearFailed:
            return "清理日志失败"
        }
    }
} 