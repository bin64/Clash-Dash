import SwiftUI

struct DirectConnectionInfoView: View {
    @Binding var isPresented: Bool
    let proxyAddress: String
    let httpPort: String
    let mixedPort: String
    let usedPort: String // 最终尝试连接的端口
    
    var body: some View {
        // 移除 NavigationView
        VStack(alignment: .leading, spacing: 0) { // 设置 spacing 为 0，手动控制间距

            // 自定义标题栏
            HStack {
                Spacer()
                Text("直接连接说明")
                    .font(.headline)
                    .padding(.vertical)
                Spacer()
            }
            // 添加顶部分隔线
            Divider()

            // 主要内容区域，使用 ScrollView 防止内容过多时溢出
            ScrollView {
                VStack(alignment: .leading, spacing: 16) { // 内容 VStack
                    // 显示代理服务器和端口信息
                    VStack(alignment: .leading, spacing: 10) {
                        Text("尝试连接的代理")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.bottom, 2)
                        
                        HStack {
                            Image(systemName: "network")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .frame(width: 20)
                            
                            Text("地址:")
                                .font(.system(size: 14))
                                .foregroundColor(.secondary)
                            
                            Text(proxyAddress.isEmpty ? "未设置" : proxyAddress)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                            
                            Spacer()
                        }
                        
                        Divider().padding(.vertical, 2)
                        
                        HStack(alignment: .top) {
                            Image(systemName: "number.circle")
                                .font(.subheadline)
                                .foregroundColor(.blue)
                                .frame(width: 20, alignment: .top)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                PortInfoRow(label: "HTTP 端口", value: httpPort)
                                PortInfoRow(label: "Mixed 端口", value: mixedPort)

                                if !usedPort.isEmpty && usedPort != "0" {
                                    HStack {
                                        Text("尝试端口:")
                                            .font(.system(size: 14))
                                            .foregroundColor(.secondary)
                                            .frame(width: 80, alignment: .leading)
                                        Text(usedPort)
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.orange)
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.orange)
                                            .font(.caption)
                                        Spacer()
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.blue.opacity(0.2), lineWidth: 1)
                            )
                    )
                    .padding(.bottom, 8)
                    
                    Divider()

                    // 原因和解决方法部分
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(icon: "exclamationmark.triangle.fill", color: .orange, text: "无法使用Clash代理")
                        
                        Text("当前无法获取或使用Clash提供的代理，可能的原因：")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        InfoRow(icon: "wifi.slash", color: .red, text: "iOS设备与Clash设备不在同一网络")
                        InfoRow(icon: "lock.slash", color: .red, text: "Clash的HTTP或Mixed端口未开放或错误")
                        InfoRow(icon: "xmark.shield", color: .red, text: "防火墙阻止了端口访问")
                        
                        Divider()
                        
                        Text("解决方法：")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        InfoRow(icon: "checkmark.circle", color: .green, text: "确保设备在同一网络")
                        InfoRow(icon: "gearshape", color: .blue, text: "检查Clash配置中的端口设置")
                        InfoRow(icon: "arrow.clockwise", color: .blue, text: "点击刷新按钮重新测试")
                    }
                }
                .padding() // 为内容添加内边距
            } // ScrollView 结束

            // 底部按钮区域
            VStack(spacing: 0) {
                Divider() // 按钮上方的分隔线
                HStack {
                    Spacer()
                    Button(action: {
                        isPresented = false
                    }) {
                        Text("我知道了")
                            // 使用标准的蓝色按钮文本
                            .font(.system(size: 17, weight: .semibold)) // 标准按钮字体
                            .foregroundColor(.accentColor) // 使用主题强调色
                            .padding(.vertical, 12) // 增加垂直内边距
                            .frame(maxWidth: .infinity) // 让可点击区域变大
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle()) // 保持无背景样式
                    Spacer()
                }
                .padding(.vertical, 5) // 调整按钮区域的垂直内边距
                // 移除背景色，让其与内容区域背景一致
                // .background(Color(UIColor.systemGray6))
            } // 底部按钮 VStack 结束
        } // 最外层 VStack 结束
    }
}

// 新增：用于显示端口信息的辅助视图
struct PortInfoRow: View {
    let label: String
    let value: String
    var isActive: Bool? = nil // Make isActive optional

    var body: some View {
        HStack {
            Text("\(label):")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)

            Text(value.isEmpty || value == "0" ? "未设置" : value)
                .font(.system(size: 14, weight: .medium))
                // Only apply green color if isActive is explicitly true
                .foregroundColor(isActive == true ? .green : .primary)

            // Only show checkmark if isActive is explicitly true
            if isActive == true {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }

            Spacer()
        }
    }
}

// InfoRow组件保持不变
struct InfoRow: View {
    let icon: String
    let color: Color
    let text: String
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 20)
            
            Text(text)
                .font(.system(size: 14))
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// 更新预览以包含新参数
#Preview {
    DirectConnectionInfoView(
        isPresented: .constant(true),
        proxyAddress: "192.168.1.1",
        httpPort: "7890",
        mixedPort: "0", // Example: Mixed port not set
        usedPort: "7890" // Example: HTTP port was attempted
    )
} 