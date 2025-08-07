import SwiftUI

/// 主内容区域视图 - 用于大屏设备显示详情内容
struct DetailContentView: View {
    @Binding var selectedServer: ClashServer?
    @Binding var selectedSidebarItem: SidebarItem?
    @ObservedObject var settingsViewModel: SettingsViewModel
    @EnvironmentObject private var bindingManager: WiFiBindingManager
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        NavigationStack {
            Group {
                if let server = selectedServer, 
                   let item = selectedSidebarItem,
                   case .server = item {
                    // 显示服务器详情
                    ServerDetailView(server: server)
                        .navigationBarTitleDisplayMode(.inline)
                        .id(server.id) // 强制重新创建视图
                } else if let item = selectedSidebarItem {
                    // 显示设置页面
                    switch item {
                    case .globalSettings:
                        GlobalSettingsView()
                            .navigationTitle("全局配置")
                            .navigationBarTitleDisplayMode(.large)
                            
                    case .appearanceSettings:
                        AppearanceSettingsView()
                            .navigationTitle("外观设置")
                            .navigationBarTitleDisplayMode(.large)
                            
                    case .logs:
                        LogsView()
                            .navigationTitle("运行日志")
                            .navigationBarTitleDisplayMode(.large)
                            
                    case .help:
                        helpView
                            .navigationTitle("如何使用")
                            .navigationBarTitleDisplayMode(.large)
                            
                    default:
                        welcomeView
                    }
                } else {
                    // 默认欢迎页面
                    welcomeView
                }
            }
        }
    }
    
    /// 欢迎页面
    private var welcomeView: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // App图标和标题
            VStack(spacing: 16) {
                Image(colorScheme == .dark ? "dark_logo" : "light_logo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 120, height: 120)
                
                VStack(spacing: 8) {
                    Text("欢迎使用 Clash Dash")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("在左侧选择一个控制器或设置项目开始使用")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // 功能介绍卡片
            VStack(spacing: 16) {
                FeatureCard(
                    icon: "server.rack",
                    title: "控制器管理",
                    description: "添加和管理多个 Clash 控制器",
                    color: .blue
                )
                
                FeatureCard(
                    icon: "gearshape.2",
                    title: "全局配置",
                    description: "配置应用程序的全局设置",
                    color: .green
                )
                
                FeatureCard(
                    icon: "paintbrush",
                    title: "外观定制",
                    description: "个性化应用程序的外观和主题",
                    color: .purple
                )
            }
            .frame(maxWidth: 400)
            
            // 版本信息
            VStack(spacing: 8) {
                Text("版本信息")
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text("Ver: \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0") Build \(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0")")
                    .foregroundColor(.secondary)
                    .font(.footnote)
                    .monospacedDigit()
            }
            
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Clash Dash")
        .navigationBarTitleDisplayMode(.large)
    }
    
    /// 帮助页面
    private var helpView: some View {
        VStack {
            HelpView()
        }
        .background(Color(.systemGroupedBackground))
    }
    

}

/// 功能介绍卡片
struct FeatureCard: View {
    let icon: String
    let title: String
    let description: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 40, height: 40)
                .background(color.opacity(0.1))
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .fontWeight(.medium)
                
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
}

#Preview {
    DetailContentView(
        selectedServer: .constant(nil),
        selectedSidebarItem: .constant(nil),
        settingsViewModel: SettingsViewModel()
    )
    .environmentObject(WiFiBindingManager())
} 