import Foundation
import CloudKit
import OSLog

private let logger = LogManager.shared

class CloudKitManager: ObservableObject {
    static let shared = CloudKitManager()
    private let container = CKContainer.default()
    private let defaults = UserDefaults.standard
    private let recordType = "AppData"
    
    @Published var isSyncing = false
    @Published var isUploadingSyncing = false
    @Published var isDownloadingSyncing = false
    @Published var lastSyncTime: Date?
    @Published var iCloudStatus: String = "未检查"
    
    // 同步选项
    @Published var syncGlobalSettings = true
    @Published var syncServers = true
    @Published var syncAppearance = true
    
    private let globalSettingsKeys: Set<String> = [
        "autoDisconnectOldProxy",
        "hideUnavailableProxies",
        "proxyGroupSortOrder",
        "hideProxyProviders",
        "smartProxyGroupDisplay",
        "pinBuiltinProxies",
        "speedTestURL",
        "speedTestTimeout",
        "allowManualURLTestGroupSwitch",
        "serverStatusTimeout"
    ]
    
    private let serverKeys: Set<String> = [
        "servers",
        "SavedClashServers"
        // "subscription_cache",
        // "subscription_last_update"
    ]
    
    private let appearanceKeys: Set<String> = [
        "appThemeMode",
        "usePureBlackDarkMode",
        "showWaveEffect",
        "proxyViewStyle",
        "overviewCardVisibility",
        "hideDisconnectedServers",
        "overviewCardOrder",
        "modeSwitchCardStyle",
        "enableHapticFeedback",
        "subscriptionCardStyle",
        "showSubscriptionCard",
        "enableWiFiBinding",
        "wifi_bindings",
        "speedChartStyle",
        "connectionRowStyle",
        "defaultConnectionSortOption",
        "defaultConnectionSortAscending",
        "default_servers",
        "lowDelayThreshold",
        "mediumDelayThreshold",
        "showSpeedNumberAnimation",
        "showNumberAnimation",
        "widgetDefaultServer",
        "showDelayRingChart",
        "autoRefreshSubscriptionCard"
    ]
    
    private let excludedKeys = Set([
        "enableCloudSync",  // 不同步 iCloud 开关状态
        "lastSyncTime",     // 不同步上次同步时间
    ])
    
    private init() {
        lastSyncTime = defaults.object(forKey: "lastCloudKitSyncTime") as? Date
        syncGlobalSettings = defaults.bool(forKey: "syncGlobalSettings")
        syncServers = defaults.bool(forKey: "syncServers")
        syncAppearance = defaults.bool(forKey: "syncAppearance")
        Task {
            await checkICloudStatus()
        }
    }
    
    private func checkICloudStatus() async {
        do {
            let status = try await container.accountStatus()
            await MainActor.run {
                switch status {
                case .available:
                    iCloudStatus = "可用"
                    logger.info("iCloud 状态: 可用")
                case .noAccount:
                    iCloudStatus = "未登录 iCloud 账号"
                    logger.warning("iCloud 状态: 未登录")
                case .restricted:
                    iCloudStatus = "iCloud 访问受限"
                    logger.warning("iCloud 状态: 受限")
                case .couldNotDetermine:
                    iCloudStatus = "无法确定 iCloud 状态"
                    logger.warning("iCloud 状态: 未知")
                case .temporarilyUnavailable:
                    iCloudStatus = "暂时不可用"
                    logger.warning("iCloud 状态: 暂时不可用")
                @unknown default:
                    iCloudStatus = "未知状态"
                    logger.warning("iCloud 状态: 未知默认值")
                }
            }
        } catch {
            await MainActor.run {
                iCloudStatus = "检查失败: \(error.localizedDescription)"
            }
            logger.error("检查 iCloud 状态失败: \(error.localizedDescription)")
        }
    }
    
    private func convertValueToJSONSafe(_ value: Any) -> Any {
        // 先处理布尔值
        if let bool = value as? Bool {
            return bool
        }
        // 处理数字（包括 Int 和 Double）
        if let number = value as? NSNumber {
            return number
        }
        // 处理日期
        if let date = value as? Date {
            return date.timeIntervalSince1970
        }
        // 处理数据
        if let data = value as? Data {
            return data.base64EncodedString()
        }
        // 处理字符串
        if let string = value as? String {
            return string
        }
        if let array = value as? [Any] {
            return array.map { convertValueToJSONSafe($0) }
        }
        if let dict = value as? [String: Any] {
            var newDict: [String: Any] = [:]
            for (key, value) in dict {
                newDict[key] = convertValueToJSONSafe(value)
            }
            return newDict
        }
        return value
    }
    
    private func convertJSONSafeToValue(_ value: Any) -> Any {
        // 先处理布尔值
        if let bool = value as? Bool {
            return bool
        }
        // 处理数字
        if let number = value as? NSNumber {
            // 如果是布尔值的特殊情况
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue
            }
            // 检查是否是时间戳（大于 946684800 表示是在 2000 年之后的时间戳）
            if number.doubleValue > 946684800 {
                return Date(timeIntervalSince1970: number.doubleValue)
            }
            // 否则返回原始数值
            return number.intValue
        }
        // 处理字符串
        if let string = value as? String {
            // 尝试 Base64 解码
            if let data = Data(base64Encoded: string) {
                return data
            }
            // 如果不是 Base64，返回原始字符串
            return string
        }
        if let array = value as? [Any] {
            return array.map { convertJSONSafeToValue($0) }
        }
        if let dict = value as? [String: Any] {
            var newDict: [String: Any] = [:]
            for (key, value) in dict {
                newDict[key] = convertJSONSafeToValue(value)
            }
            return newDict
        }
        return value
    }
    
    private func formatValueForLog(_ value: Any) -> String {
        if let bool = value as? Bool {
            return bool ? "true" : "false"
        }
        if let data = value as? Data {
            return "{length = \(data.count), bytes = \(data.prefix(20).map { String(format: "%02x", $0) }.joined(separator: " "))...}"
        }
        if let array = value as? [Any] {
            return "\(array)"
        }
        if let dict = value as? [String: Any] {
            return "\(dict)"
        }
        return String(describing: value)
    }
    
    private func getAllUserDefaults() -> [String: Any] {
        let defaults = UserDefaults.standard.dictionaryRepresentation()
        var filteredData: [String: Any] = [:]
        
        // logger.info("开始处理 UserDefaults，总计 \(defaults.count) 个键值对")
        
        // 特别记录 wifi_bindings 的原始内容
        // if let wifiBindings = defaults["wifi_bindings"] {
        //     logger.info("发现 wifi_bindings 原始数据: \(String(describing: wifiBindings))")
        // } else {
        //     logger.warning("未找到 wifi_bindings 数据")
        // }
//        let wifiBindings = defaults["wifi_bindings"]
        
        for (key, value) in defaults {
            // 记录每个键的处理过程
            if key.hasPrefix("com.apple") || key.hasPrefix("NS") {
                // logger.debug("跳过系统键: \(key)")
                continue
            }
            
            if excludedKeys.contains(key) {
                // logger.debug("跳过被排除的键: \(key)")
                continue
            }
            
            // 记录键所属的类别
            if globalSettingsKeys.contains(key) {
                // logger.debug("发现全局设置键: \(key)")
                if syncGlobalSettings {
                    let jsonSafeValue = convertValueToJSONSafe(value)
                    filteredData[key] = jsonSafeValue
                    // logger.info("添加全局设置键值对: \(key) = \(self.formatValueForLog(value))")
                }
            } else if serverKeys.contains(key) {
                // logger.debug("发现服务器设置键: \(key)")
                if syncServers {
                    let jsonSafeValue = convertValueToJSONSafe(value)
                    filteredData[key] = jsonSafeValue
                    // logger.info("添加服务器设置键值对: \(key) = \(self.formatValueForLog(value))")
                }
            } else if appearanceKeys.contains(key) {
                // logger.debug("发现外观设置键: \(key)")
                if syncAppearance {
                    let jsonSafeValue = convertValueToJSONSafe(value)
                    filteredData[key] = jsonSafeValue
                    // 特别记录 wifi_bindings 的转换后内容
                    // if key == "wifi_bindings" {
                    //     logger.info("wifi_bindings 转换后的数据: \(String(describing: jsonSafeValue))")
                    // }
                    // logger.info("添加外观设置键值对: \(key) = \(self.formatValueForLog(value))")
                }
            }
        }
        
        // logger.info("处理完成，筛选出 \(filteredData.count) 个键值对")
        return filteredData
    }
    
    func setSyncOption(globalSettings: Bool? = nil, servers: Bool? = nil, appearance: Bool? = nil) {
        if let value = globalSettings {
            syncGlobalSettings = value
            defaults.set(value, forKey: "syncGlobalSettings")
        }
        if let value = servers {
            syncServers = value
            defaults.set(value, forKey: "syncServers")
        }
        if let value = appearance {
            syncAppearance = value
            defaults.set(value, forKey: "syncAppearance")
        }
    }
    
    // private func checkRecordType() async throws {
    //     let database = container.privateCloudDatabase
    //     do {
    //         // 尝试查询记录类型
    //         let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
    //         _ = try await database.records(matching: query, resultsLimit: 1)
    //     } catch let error as CKError {
    //         if error.code == .unknownItem || error.code == .serverRecordChanged {
    //             // 记录类型不存在，尝试创建一个空记录来初始化记录类型
    //             logger.warning("记录类型不存在，尝试创建...")
                
    //             // 创建一个空记录，包含所有必要的字段
    //             let record = CKRecord(recordType: recordType)
    //             record["timestamp"] = Date()
    //             record["allData"] = "{}".data(using: .utf8)
                
    //             // 在保存之前先检查环境
    //             let environment = ProcessInfo.processInfo.environment["CLOUDKIT_ENVIRONMENT"]
    //             logger.debug("当前 CloudKit 环境: \(environment ?? "Production")")
                
    //             do {
    //                 _ = try await database.save(record)
    //                 logger.info("成功创建记录类型")
    //             } catch let saveError as CKError {
    //                 // 如果是权限错误，提供更详细的错误信息
    //                 if saveError.code == .serverRejectedRequest {
    //                     logger.error("创建记录类型失败，可能需要在 CloudKit Dashboard 中手动创建")
    //                     throw NSError(
    //                         domain: "CloudKitManager",
    //                         code: saveError.errorCode,
    //                         userInfo: [
    //                             NSLocalizedDescriptionKey: """
    //                             需要在 CloudKit Dashboard 中为 Production 环境创建记录类型。
    //                             请前往 CloudKit Dashboard:
    //                             1. 选择 Production 环境
    //                             2. 创建名为 "AppData" 的记录类型
    //                             3. 添加 "timestamp" (DateTime) 和 "allData" (Bytes) 字段
    //                             """
    //                         ]
    //                     )
    //                 } else {
    //                     throw saveError
    //                 }
    //             }
    //         } else {
    //             throw error
    //         }
    //     }
    // }
    
    func syncToCloud() async throws {
        // 先检查 iCloud 状态
        await checkICloudStatus()
        guard iCloudStatus == "可用" else {
            logger.error("iCloud 不可用，无法同步")
            throw NSError(domain: "CloudKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud 不可用：\(iCloudStatus)"])
        }
        
        await MainActor.run {
            isSyncing = true
            isUploadingSyncing = true
        }
        
        defer {
            Task { @MainActor in
                isSyncing = false
                isUploadingSyncing = false
            }
        }
        
        let database = container.privateCloudDatabase
        
        do {
            // 先删除旧记录
            logger.info("开始删除旧记录")
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            let (results, _) = try await database.records(matching: query)
            logger.info("找到 \(results.count) 条旧记录")
            for recordID in results.map({ $0.0 }) {
                try await database.deleteRecord(withID: recordID)
            }
            
            // 获取所有数据
            let allData = getAllUserDefaults()
            logger.debug("获取到所有数据: \(allData.count) 个键值对")
            logger.debug("数据内容: \(String(describing: allData))")
            
            // 创建记录
            let record = CKRecord(recordType: recordType)
            
            if let dataEncoded = try? JSONSerialization.data(withJSONObject: allData) {
                record["allData"] = dataEncoded
            } else {
                logger.error("数据编码失败")
                throw NSError(domain: "CloudKitManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "数据编码失败"])
            }
            
            record["timestamp"] = Date()
            
            // 保存到 iCloud
            logger.info("开始保存到 iCloud")
            let savedRecord = try await database.save(record)
            logger.info("成功保存到 iCloud，记录 ID: \(savedRecord.recordID.recordName)")
            
            // 更新最后同步时间
            let syncTime = Date()
            await MainActor.run {
                self.lastSyncTime = syncTime
                defaults.set(syncTime, forKey: "lastCloudKitSyncTime")
            }
            logger.info("同步完成")
            
        } catch {
            logger.error("同步失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    func syncFromCloud() async throws {
        // 先检查 iCloud 状态
        await checkICloudStatus()
        guard iCloudStatus == "可用" else {
            logger.error("iCloud 不可用，无法同步")
            throw NSError(domain: "CloudKitManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "iCloud 不可用：\(iCloudStatus)"])
        }
        
        await MainActor.run {
            isSyncing = true
            isDownloadingSyncing = true
        }
        
        defer {
            Task { @MainActor in
                isSyncing = false
                isDownloadingSyncing = false
            }
        }
        
        let database = container.privateCloudDatabase
        
        do {
            // 查询最新的数据
            logger.info("开始从 iCloud 查询数据")
            let query = CKQuery(recordType: recordType, predicate: NSPredicate(value: true))
            query.sortDescriptors = [NSSortDescriptor(key: "timestamp", ascending: false)]
            
            let (results, _) = try await database.records(matching: query, resultsLimit: 1)
            guard let recordID = results.first?.0 else {
                logger.warning("未找到任何记录")
                throw NSError(domain: "CloudKitManager", code: 5, userInfo: [NSLocalizedDescriptionKey: "未找到任何记录"])
            }
            
            logger.info("找到记录，ID: \(recordID.recordName)")
            let record = try await database.record(for: recordID)
            
            // 恢复数据
            guard let allData = record["allData"] as? Data else {
                logger.error("记录中缺少必要的数据")
                throw NSError(domain: "CloudKitManager", code: 6, userInfo: [NSLocalizedDescriptionKey: "记录数据不完整"])
            }
            
            try await MainActor.run {
                if let dataDict = try JSONSerialization.jsonObject(with: allData) as? [String: Any] {
                    var restoredCount = 0
                    logger.info("开始恢复数据，共有 \(dataDict.count) 个键值对")
                    
                    for (key, value) in dataDict {
                        // 确保不恢复被排除的键
                        if excludedKeys.contains(key) {
                            logger.debug("跳过被排除的键: \(key)")
                            continue
                        }
                        
                        // 根据同步选项恢复数据
                        if globalSettingsKeys.contains(key) {
                            if syncGlobalSettings {
                                let convertedValue = convertJSONSafeToValue(value)
                                defaults.set(convertedValue, forKey: key)
                                restoredCount += 1
                                logger.debug("恢复全局设置: \(key) = \(self.formatValueForLog(convertedValue))")
                            }
                        } else if serverKeys.contains(key) {
                            if syncServers {
                                let convertedValue = convertJSONSafeToValue(value)
                                defaults.set(convertedValue, forKey: key)
                                restoredCount += 1
                                logger.debug("恢复服务器设置: \(key) = \(self.formatValueForLog(convertedValue))")
                            }
                        } else if appearanceKeys.contains(key) {
                            if syncAppearance {
                                let convertedValue = convertJSONSafeToValue(value)
                                defaults.set(convertedValue, forKey: key)
                                restoredCount += 1
                                logger.debug("恢复外观设置: \(key) = \(self.formatValueForLog(convertedValue))")
                            }
                        }
                    }
                    logger.info("总共恢复了 \(restoredCount) 个设置")
                }
            }
            
            // 更新最后同步时间
            let syncTime = Date()
            await MainActor.run {
                self.lastSyncTime = syncTime
                defaults.set(syncTime, forKey: "lastCloudKitSyncTime")
                // 发送通知以更新 UI
                NotificationCenter.default.post(name: NSNotification.Name("SettingsUpdated"), object: nil)
                // 专门发送控制器列表更新通知
                NotificationCenter.default.post(name: NSNotification.Name("ControllersUpdated"), object: nil)
                // 专门发送 WiFi 绑定更新通知
                NotificationCenter.default.post(name: NSNotification.Name("WiFiBindingsUpdated"), object: nil)
            }
            logger.info("同步完成")
            
        } catch {
            logger.error("同步失败: \(error.localizedDescription)")
            throw error
        }
    }
} 
