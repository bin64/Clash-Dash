import SwiftUI



@MainActor
class ServerDetailViewModel: ObservableObject {
    let serverViewModel: ServerViewModel
    
    init() {
        self.serverViewModel = ServerViewModel()
    }
    
    func getPluginVersion(server: ClashServer) async throws -> String {
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            throw NetworkError.unauthorized(message: "未设置 OpenWRT 用户名或密码")
        }
        
        let token = try await serverViewModel.getAuthToken(server, username: username, password: password)
        let scheme = server.openWRTUseSSL ? "https" : "http"
        guard let openWRTUrl = server.openWRTUrl else {
            throw NetworkError.invalidURL
        }
        let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
        
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token)", forHTTPHeaderField: "Cookie")
        
        let command: String
        let pluginName: String
        switch server.luciPackage {
        case .openClash:
            command = "opkg status luci-app-openclash 2>/dev/null | awk -F ': ' '/Version/{print \"v\"$2}'"
            pluginName = "OpenClash"
        case .mihomoTProxy:
            // 先检查是否使用 nikki
            let checkCommand: [String: Any] = [
                "method": "exec",
                "params": ["opkg status luci-app-nikki 2>/dev/null | grep 'Status: install'"]
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: checkCommand)
            let (checkData, _) = try await URLSession.shared.data(for: request)
            let checkResponse = try JSONDecoder().decode(UCIResponse.self, from: checkData)
            
            // 如果找到 nikki 包的安装状态，说明使用的是 nikki
            if !checkResponse.result.isEmpty {
                command = "opkg status luci-app-nikki 2>/dev/null | awk -F ': ' '/Version/{print \"v\"$2}'"
                pluginName = "Nikki"
            } else {
                command = "/usr/libexec/mihomo-call version app"
                pluginName = "MihomoTProxy"
            }
        }
        
        let requestBody: [String: Any] = [
            "method": "exec",
            "params": [command]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let session = URLSession.shared
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = jsonResponse["result"] as? String else {
            throw NetworkError.invalidResponse(message: "Invalid JSON response")
        }
        
        // 清理结果字符串，移除换行符等，并添加插件名称
        let version = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(pluginName) \(version)"
    }
    
    func getRunningTime(server: ClashServer) async throws -> (String, String) {
        guard let username = server.openWRTUsername,
              let password = server.openWRTPassword else {
            throw NetworkError.unauthorized(message: "未设置 OpenWRT 用户名或密码")
        }
        
        let token = try await serverViewModel.getAuthToken(server, username: username, password: password)
        let scheme = server.openWRTUseSSL ? "https" : "http"
        guard let openWRTUrl = server.openWRTUrl else {
            throw NetworkError.invalidURL
        }
        let baseURL = "\(scheme)://\(openWRTUrl):\(server.openWRTPort ?? "80")"
        
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token)", forHTTPHeaderField: "Cookie")
        
        let command: String
        switch server.luciPackage {
        case .openClash:
            command = "date -d \"@$(($(date +%s -d \"$(uptime -s)\") + $(cat /proc/$(pidof clash | head -n1)/stat | awk '{print $22}')/100))\" +%s && date -d \"$(uptime -s)\" +%s"
        case .mihomoTProxy:
            command = "date -d \"@$(($(date +%s -d \"$(uptime -s)\") + $(cat /proc/$(pidof mihomo | head -n1)/stat | awk '{print $22}')/100))\" +%s && date -d \"$(uptime -s)\" +%s"
        }
        
        let requestBody: [String: Any] = [
            "method": "exec",
            "params": [command]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let session = URLSession.shared
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = jsonResponse["result"] as? String else {
            throw NetworkError.invalidResponse(message: "Invalid JSON response")
        }
        
        // 分割两个时间戳
        let timestamps = result.split(separator: "\n")
        guard timestamps.count >= 2,
              let kernelTimestamp = Int(timestamps[0].trimmingCharacters(in: .whitespacesAndNewlines)),
              let pluginTimestamp = Int(timestamps[1].trimmingCharacters(in: .whitespacesAndNewlines)) else {
            throw NetworkError.invalidResponse(message: "Invalid timestamp format")
        }
        
        let currentTimestamp = Int(Date().timeIntervalSince1970)
        
        // 计算内核运行时长
        let kernelRunningSeconds = currentTimestamp - kernelTimestamp
        var kernelTimeString = formatRunningTime(seconds: kernelRunningSeconds)
        
        // 计算插件运行时长
        let pluginRunningSeconds = currentTimestamp - pluginTimestamp
        var pluginTimeString = formatRunningTime(seconds: pluginRunningSeconds)
        
        return (kernelTimeString, pluginTimeString)
    }
    
    private func formatRunningTime(seconds: Int) -> String {
        let days = seconds / 86400
        let hours = (seconds % 86400) / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60
        
        var timeString = ""
        if days > 0 { timeString += "\(days)天" }
        if hours > 0 { timeString += "\(hours)时" }
        if minutes > 0 { timeString += "\(minutes)分" }
        timeString += "\(secs)秒"
        
        return timeString
    }
} 
