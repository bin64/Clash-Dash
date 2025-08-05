import Foundation
import OSLog

enum PluginType {
    case openClash
    case mihomoTProxy
    
    var versionCommand: String {
        switch self {
        case .openClash:
            return "opkg status luci-app-openclash 2>/dev/null | awk -F ': ' '/Version/{print \"v\"$2}'"
        case .mihomoTProxy:
            return "/usr/libexec/mihomo-call version app"
        }
    }
    
    var displayName: String {
        switch self {
        case .openClash:
            return "OpenClash"
        case .mihomoTProxy:
            return "MihomoTProxy"
        }
    }
}

struct VersionInfo {
    let pluginName: String
    let version: String
    
    var displayVersion: String {
        return "\(pluginName) \(version)"
    }
}

class VersionService {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.mou.clash-dash", category: "VersionService")
    
    func checkNikkiInstallation(baseURL: String, token: String) async throws -> Bool {
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token); sysauth_https=\(token)", forHTTPHeaderField: "Cookie")
        
        let checkCommand: [String: Any] = [
            "method": "exec",
            "params": ["opkg status luci-app-nikki 2>/dev/null | grep 'Status: install'"]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: checkCommand)
        
        let (checkData, _) = try await URLSession.secure.data(for: request)
        let checkResponse = try JSONDecoder().decode(UCIResponse.self, from: checkData)
        
        return !checkResponse.result.isEmpty
    }
    
    func getPluginVersion(
        baseURL: String,
        token: String,
        pluginType: PluginType
    ) async throws -> VersionInfo {
        guard let url = URL(string: "\(baseURL)/cgi-bin/luci/rpc/sys?auth=\(token)") else {
            throw NetworkError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("sysauth=\(token); sysauth_http=\(token); sysauth_https=\(token)", forHTTPHeaderField: "Cookie")
        
        let command: String
        let pluginName: String
        
        if case .mihomoTProxy = pluginType {
            // 检查是否安装了 Nikki
            if try await checkNikkiInstallation(baseURL: baseURL, token: token) {
                command = "opkg status luci-app-nikki 2>/dev/null | awk -F ': ' '/Version/{print \"v\"$2}'"
                pluginName = "Nikki"
            } else {
                command = pluginType.versionCommand
                pluginName = pluginType.displayName
            }
        } else {
            command = pluginType.versionCommand
            pluginName = pluginType.displayName
        }
        
        let requestBody: [String: Any] = [
            "method": "exec",
            "params": [command]
        ]
        
        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)
        
        let (data, response) = try await URLSession.secure.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw NetworkError.serverError((response as? HTTPURLResponse)?.statusCode ?? 500)
        }
        
        guard let jsonResponse = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = jsonResponse["result"] as? String else {
            throw NetworkError.invalidResponse(message: "Invalid JSON response")
        }
        
        logger.debug("版本信息 - 原始响应数据：\(jsonResponse)")
        let version = result.trimmingCharacters(in: .whitespacesAndNewlines)
        let versionInfo = VersionInfo(pluginName: pluginName, version: version)
        logger.info("版本信息 - \(versionInfo.displayVersion)")
        
        return versionInfo
    }
} 