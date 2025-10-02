import SwiftUI
import Foundation

struct ModernConnectionRow: View {
    let connection: ClashConnection
    let viewModel: ConnectionsViewModel
    @ObservedObject var tagViewModel: ClientTagViewModel
    let onClose: () -> Void
    @Environment(\.colorScheme) var colorScheme
    @Binding var selectedConnection: ClashConnection?

    @State private var snapEffect: Bool = false
    
    private struct Theme {
        let background: Color
        let cardBackground: Color
        let text: Color
        let subtext: Color
        let download: Color
        let upload: Color
        let port: Color
        let chain: Color
        let chainArrow: Color
        let duration: Color
        
        static func forScheme(_ scheme: ColorScheme) -> Theme {
            switch scheme {
            case .dark:
                return Theme(
                    background: Color.black.opacity(0.2),
                    cardBackground: Color(.systemGray6).opacity(0.8),
                    text: .white,
                    subtext: Color(.systemGray2),
                    download: .blue,
                    upload: .green,
                    port: Color(.systemGray).opacity(0.8),
                    chain: Color(.systemGray).opacity(0.9),
                    chainArrow: Color(.systemGray4),
                    duration: Color(.systemGray2)
                )
            default:
                return Theme(
                    background: Color(.systemGray6).opacity(0.5),
                    cardBackground: .white,
                    text: Color(.darkText),
                    subtext: Color(.systemGray),
                    download: .blue,
                    upload: .green,
                    port: Color(.systemGray3),
                    chain: Color(.systemGray2),
                    chainArrow: Color(.systemGray4),
                    duration: Color(.systemGray2)
                )
            }
        }
    }
    
    private var theme: Theme {
        Theme.forScheme(colorScheme)
    }
    
    private func formatBytes(_ bytes: Int) -> String {
        let units = ["B", "K", "M", "G"]
        var size = Double(bytes)
        var unitIndex = 0
        
        while size >= 1000 && unitIndex < units.count - 1 {
            size /= 1024
            unitIndex += 1
        }
        
        if size < 0.1 { return "0\(units[unitIndex])" }
        if size >= 100 { return String(format: "%.0f%@", min(size, 999), units[unitIndex]) }
        if size >= 10 { return String(format: "%.1f%@", size, units[unitIndex]) }
        return String(format: "%.2f%@", size, units[unitIndex])
    }
    
    // 获取客户端标签
    private func getClientTag(for ip: String) -> String? {
        return tagViewModel.tags.first { $0.ip == ip }?.name
    }
    
    private func TrafficLabel(_ bytes: Int, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(color)
            Text(formatBytes(bytes))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(theme.subtext)
        }
    }
    
    private func ProxyChainView(_ chains: [String]) -> some View {
        Group {
            if !chains.isEmpty {
                HStack(spacing: 4) {
                    // 显示源IP或标签名
                    let sourceTag = getClientTag(for: connection.metadata.sourceIP)
                    Text(sourceTag ?? connection.metadata.sourceIP)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(theme.chain)
                    
                    // 箭头
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor(theme.chainArrow)
                    
                    // 显示最后一个代理节点
                    if let lastProxy = chains.first {
                        Text(lastProxy)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(theme.chain)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
    }
    
    var body: some View {
        Button {
            HapticManager.shared.impact(.light)
            selectedConnection = connection
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                // 第一行：主机信息和关闭按钮/连接时长
                HStack {
                    // 主机和端口
                    HStack(spacing: 0) {
                        Text(connection.metadata.host.isEmpty ? (connection.metadata.destinationIP ?? "") : connection.metadata.host)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(theme.text)
                        Text(":\(connection.metadata.destinationPort)")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(theme.port)
                    }
                    .lineLimit(1)
                    
                    Spacer()
                    
                    if connection.isAlive {
                        Button {
                            HapticManager.shared.impact(.light)
                            snapEffect = true
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(theme.subtext.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(connection.formattedDuration)
                            .font(.system(size: 12))
                            .foregroundColor(theme.duration)
                    }
                }
                
                // 第二行：代理链和流量信息
                HStack(alignment: .center, spacing: 8) {
                    // 代理链
                    ScrollView(.horizontal, showsIndicators: false) {
                        ProxyChainView(connection.chains)
                            .id(connection.id) // 强制在连接ID变化时重新渲染
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    // 流量信息
                    HStack(spacing: 12) {
                        TrafficLabel(connection.download, icon: "arrow.down", color: theme.download)
                        TrafficLabel(connection.upload, icon: "arrow.up", color: theme.upload)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(theme.cardBackground)
            )
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .disintegrationEffect(isDeleted: snapEffect) {
                // 延迟一点时间再执行关闭，确保动画完全完成
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    onClose()
                }
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview {
    ModernConnectionRow(
        connection: .preview(),
        viewModel: ConnectionsViewModel(),
        tagViewModel: ClientTagViewModel(),
        onClose: {},
        selectedConnection: .constant(nil)
    )
} 