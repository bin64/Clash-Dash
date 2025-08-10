import SwiftUI

struct ModeSelectionMenu: View {
    @ObservedObject var settingsViewModel: SettingsViewModel
    let server: ClashServer
    var onModeChange: (String) -> Void
    
    // 添加触觉反馈生成器
    
    
    var body: some View {
        Menu {
            Button {
                HapticManager.shared.impact(.light)
                settingsViewModel.updateConfig("mode", value: "rule", server: server) { 
                    settingsViewModel.mode = "rule"
                    onModeChange("rule")
                    // 刷新模式信息
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 等待1秒
                        await MainActor.run {
                            settingsViewModel.getCurrentMode(server: server) { currentMode in
                                settingsViewModel.mode = currentMode.lowercased()
                                // 发送通知以刷新服务器卡片
                                NotificationCenter.default.post(name: NSNotification.Name("RefreshServerMode"), object: nil)
                            }
                        }
                    }
                }
            } label: {
                Label("规则模式", systemImage: settingsViewModel.mode == "rule" ? "checkmark" : "circle")
            }
            
            Button {
                HapticManager.shared.impact(.light)
                settingsViewModel.updateConfig("mode", value: "direct", server: server) { 
                    settingsViewModel.mode = "direct"
                    onModeChange("direct")
                    // 刷新模式信息
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 等待1秒
                        await MainActor.run {
                            settingsViewModel.getCurrentMode(server: server) { currentMode in
                                settingsViewModel.mode = currentMode.lowercased()
                                // 发送通知以刷新服务器卡片
                                NotificationCenter.default.post(name: NSNotification.Name("RefreshServerMode"), object: nil)
                            }
                        }
                    }
                }
            } label: {
                Label("直连模式", systemImage: settingsViewModel.mode == "direct" ? "checkmark" : "circle")
            }
            
            Button {
                HapticManager.shared.impact(.light)
                settingsViewModel.updateConfig("mode", value: "global", server: server) { 
                    settingsViewModel.mode = "global"
                    onModeChange("global")
                    // 刷新模式信息
                    Task {
                        try? await Task.sleep(nanoseconds: 1_000_000_000) // 等待1秒
                        await MainActor.run {
                            settingsViewModel.getCurrentMode(server: server) { currentMode in
                                settingsViewModel.mode = currentMode.lowercased()
                                // 发送通知以刷新服务器卡片
                                NotificationCenter.default.post(name: NSNotification.Name("RefreshServerMode"), object: nil)
                            }
                        }
                    }
                }
            } label: {
                Label("全局模式", systemImage: settingsViewModel.mode == "global" ? "checkmark" : "circle")
            }
        } label: {
            Label(ModeUtils.getModeText(settingsViewModel.mode.lowercased()), 
                  systemImage: ModeUtils.getModeIcon(settingsViewModel.mode.lowercased()))
                .onTapGesture {
                    // 触发轻触反馈以响应打开菜单的点按
                    HapticManager.shared.impact(.light)
                }
        }
        .onAppear {
            settingsViewModel.getCurrentMode(server: server) { currentMode in
                settingsViewModel.mode = currentMode.lowercased()
            }
        }
    }
} 