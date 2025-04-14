import SwiftUI

struct ProxyConnectionInfoView: View {
    @Binding var isPresented: Bool
    let proxyAddress: String
    let usedPort: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 标题栏
            HStack {
                Spacer()
                Text("代理连接说明")
                    .font(.headline)
                    .padding(.vertical)
                Spacer()
            }
            Divider()

            // 内容区域
            ScrollView {
                VStack(alignment: .leading, spacing: 24) { // 增加主VStack间距

                    // 1. 代理状态说明
                    HStack(alignment: .center, spacing: 15) { // 调整间距和对齐
                        Image(systemName: "shield.lefthalf.filled.badge.checkmark") // 使用带checkmark的图标
                            .font(.system(size: 32)) // 增大图标
                            .foregroundColor(.blue)
                            .symbolRenderingMode(.hierarchical) // 多层渲染

                        VStack(alignment: .leading, spacing: 4) { // 调整文本间距
                            Text("通过代理服务器连接")
                                .font(.title3.weight(.semibold)) // 使用更醒目的标题
                            Text("本次网站访问检测已通过 Clash 提供的代理端口进行。")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .lineLimit(2) // 限制行数
                                .fixedSize(horizontal: false, vertical: true) // 允许多行
                        }
                    }

                    Divider()

                    // 2. 当前使用的代理信息
                    VStack(alignment: .leading, spacing: 12) { // 增加间距
                        Text("当前生效的代理配置")
                            .font(.headline) // Section标题
                            .foregroundColor(.secondary)

                        ProxyInfoDetailRow(icon: "network", label: "代理地址", value: proxyAddress.isEmpty ? "未设置" : proxyAddress)
                        ProxyInfoDetailRow(icon: "number.circle", label: "连接端口", value: usedPort.isEmpty || usedPort == "0" ? "未知" : usedPort, showCheckmark: true) // 传入checkmark状态
                    }

                    Divider()

                    // 3. 补充说明
                    VStack(alignment: .leading, spacing: 12) {
                        Text("补充说明")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        InfoRow(icon: "network.badge.shield.half.filled", color: .green, text: "网络请求会使用 Clash 提供的代理端口进行连接，并使用 Clash 的代理规则进行匹配。")
                        InfoRow(icon: "arrow.up.and.down.and.sparkles", color: .blue, text: "代理端口 \(usedPort) 测试通过。")
                        InfoRow(icon: "questionmark.circle", color: .gray, text: "如检测失败，请查看 App 的运行日志。")
                    }
                }
                .padding() // 为整体内容添加内边距
            } // ScrollView End

            // 底部按钮
            VStack(spacing: 0) {
                Divider()
                HStack {
                    Spacer()
                    Button {
                        isPresented = false
                    } label: {
                        Text("我知道了")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundColor(.accentColor)
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(PlainButtonStyle())
                    Spacer()
                }
                .padding(.vertical, 5)
            } // Bottom Button End
        } // Main VStack End
    }
}

// 新增：用于显示代理详细信息的辅助视图 (替代之前的HStack组合)
struct ProxyInfoDetailRow: View {
    let icon: String
    let label: String
    let value: String
    var showCheckmark: Bool = false // 控制是否显示checkmark

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundColor(.blue)
                .frame(width: 25, alignment: .center) // 调整宽度和对齐

            Text("\(label):")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .leading) // 固定标签宽度

            Text(value)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.primary)

            if showCheckmark {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
            }
            Spacer() // 推到左侧
        }
        .padding(.vertical, 4) // 微调垂直内边距
    }
}

#Preview {
    ProxyConnectionInfoView(
        isPresented: .constant(true),
        proxyAddress: "192.168.1.100",
        usedPort: "7890"
    )
} 