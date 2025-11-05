import SwiftUI

struct ServerRowView: View {
    let server: ClashServer
    @StateObject private var settingsViewModel = SettingsViewModel()
    @Environment(\.colorScheme) var colorScheme
    
    private var versionDisplay: String {
        guard let version = server.version else { return "" }
        return version.count > 15 ? String(version.prefix(15)) + "..." : version
    }
    
    private var statusIcon: String {
        switch server.status {
        case .ok: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .unauthorized: return "lock.circle.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? 
            Color(.systemGray6) : 
            Color(.secondarySystemGroupedBackground)
    }
    
    var body: some View {
        HStack(spacing: 16) {
            // 状态指示器
            ZStack {
                Circle()
                    .fill(server.status.color.opacity(0.2))
                    .frame(width: 40, height: 40)
                
                Image(systemName: statusIcon)
                    .foregroundColor(server.status.color)
            }
            
            // 服务器信息
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(server.displayName)
                        .font(.headline)
                        .lineLimit(1)
                    
                    if server.isQuickLaunch {
                        Image(systemName: "bolt.circle.fill")
                            .foregroundColor(.yellow)
                            .font(.subheadline)
                    }
                }
                
                if server.status == .ok {
                    HStack(spacing: 12) {
                        // 服务器来源标签
                        Label {
                            Text({
                                switch server.source {
                                case .clashController:
                                    return "Clash 控制器"
                                case .openWRT:
                                    return server.luciPackage == .openClash ? "OpenClash" : "Nikki"
                                case .surge:
                                    return "Surge"
                                }
                            }())
                                .foregroundColor(.secondary)
                        } icon: {
                            Image(systemName: {
                                switch server.source {
                                case .clashController:
                                    return "server.rack"
                                case .openWRT:
                                    return server.luciPackage == .openClash ? "o.square" : "n.square"
                                case .surge:
                                    return "waveform.path.ecg"
                                }
                            }())
                                .foregroundColor(.secondary)
                        }
                        .font(.caption)
                        
                        Text("•")
                            .foregroundColor(.secondary)
                            .font(.caption)
                        
                        // 代理模式信息或版本信息
                        if server.source == .surge {
                            // Surge 显示版本信息
                            let versionText = {
                                var text = ""
                                if let version = server.surgeVersion {
                                    text = version
                                }
                                if let build = server.surgeBuild {
                                    if !text.isEmpty {
                                        text += " (\(build))"
                                    } else {
                                        text = build
                                    }
                                }
                                return text.isEmpty ? "版本未知" : text
                            }()

                            Label(title: {
                                Text(versionText)
                                    .foregroundColor(.secondary)
                            }, icon: {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.secondary)
                            })
                            .font(.caption)
                        } else {
                            // 其他控制器显示代理模式信息
                            Label(title: {
                                Text(ModeUtils.getModeText(settingsViewModel.mode))
                                    .foregroundColor(.secondary)
                            }, icon: {
                                Image(systemName: ModeUtils.getModeIcon(settingsViewModel.mode))
                                    .foregroundColor(.secondary)
                            })
                            .font(.caption)
                        }
                        
                        Spacer()
                    }
                } else if let errorMessage = server.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundColor(server.status.color)
                        .lineLimit(1)
                }
            }
            
            Spacer()
            
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .frame(height: 80)
        .background(cardBackgroundColor)
        .cornerRadius(16)
        .onAppear {
            // 初始获取代理模式
            settingsViewModel.getCurrentMode(server: server) { currentMode in
                settingsViewModel.mode = currentMode
            }
            
            // 添加通知监听
            NotificationCenter.default.addObserver(
                forName: NSNotification.Name("RefreshServerMode"),
                object: nil,
                queue: .main
            ) { _ in
                settingsViewModel.getCurrentMode(server: server) { currentMode in
                    settingsViewModel.mode = currentMode
                }
            }
        }
        .onDisappear {
            // 移除通知监听
            NotificationCenter.default.removeObserver(
                self,
                name: NSNotification.Name("RefreshServerMode"),
                object: nil
            )
        }
    }
} 