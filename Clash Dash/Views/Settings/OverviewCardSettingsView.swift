import SwiftUI

struct OverviewCardSettingsView: View {
    @StateObject private var settings = OverviewCardSettings()
    @AppStorage("subscriptionCardStyle") private var subscriptionCardStyle = SubscriptionCardStyle.classic
    @AppStorage("modeSwitchCardStyle") private var modeSwitchCardStyle = ModeSwitchCardStyle.classic
    @AppStorage("showWaveEffect") private var showWaveEffect = false
    @AppStorage("showWaterDropEffect") private var showWaterDropEffect = true
    @AppStorage("showNumberAnimation") private var showNumberAnimation = true
    @AppStorage("showSpeedNumberAnimation") private var showSpeedNumberAnimation = false
    @AppStorage("speedChartStyle") private var speedChartStyle = SpeedChartStyle.line
    @AppStorage("autoRefreshSubscriptionCard") private var autoRefreshSubscriptionCard = false
    
    var body: some View {
        List {
            Section {
                ForEach(settings.cardOrder) { card in
                    HStack {
                        // Image(systemName: "line.3.horizontal")
                        //     .foregroundColor(.gray)
                        //     .font(.system(size: 14))
                        
                        Image(systemName: card.icon)
                            .foregroundColor(.accentColor)
                            .frame(width: 24)
                        
                        Text(card.description)
                        
                        Spacer()
                        
                        Toggle("", isOn: Binding(
                            get: { settings.cardVisibility[card] ?? true },
                            set: { _ in settings.toggleVisibility(for: card) }
                        ))
                    }
                }
                .onMove { source, destination in
                    settings.moveCard(from: source, to: destination)
                }
            } header: {
                SectionHeader(title: "卡片设置", systemImage: "rectangle.on.rectangle")
            } footer: {
                Text("拖动 ≡ 图标可以调整顺序，使用开关可以控制卡片的显示或隐藏")
            }
            
            Section {
                Picker("订阅信息卡片样式", selection: $subscriptionCardStyle) {
                    ForEach(SubscriptionCardStyle.allCases, id: \.self) { style in
                        Text(style.description).tag(style)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("自动刷新订阅信息", isOn: $autoRefreshSubscriptionCard)
                    Text("每次进入概览页面时自动刷新订阅信息卡片")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("订阅信息会优先从 OpenClash 或 Nikki 中获取，如果获取失败则会从 Clash 配置中获取（使用 proxy-providers 才能显示订阅信息）")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Picker("代理切换卡片样式", selection: $modeSwitchCardStyle) {
                    ForEach(ModeSwitchCardStyle.allCases, id: \.self) { style in
                        Text(style.description).tag(style)
                    }
                }
                
                Picker("速率图表样式", selection: $speedChartStyle) {
                    ForEach(SpeedChartStyle.allCases, id: \.self) { style in
                        Text(style.description).tag(style)
                    }
                }
                
                Toggle("速度卡片波浪效果", isOn: $showWaveEffect)
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("流量卡片水滴效果", isOn: $showWaterDropEffect)
                    Text("一滴水滴约为 10MB 的流量")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("数字变化动画效果", isOn: $showNumberAnimation)
                    Text("数据变化时显示平滑过渡动画")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("实时速度数字动画", isOn: $showSpeedNumberAnimation)
                    Text("上传下载实时速度数字变化时应用动画效果")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } header: {
                SectionHeader(title: "卡片样式", systemImage: "greetingcard")
            }
        }
        .navigationTitle("概览页面设置")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
    }
} 