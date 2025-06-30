import SwiftUI

struct ProxyNodeRow: View {
    let nodeName: String
    let isSelected: Bool
    let delay: Int
    var isTesting: Bool = false
    
    var body: some View {
        HStack(spacing: 12) {
            // 选中标记（占位）
            Image(systemName: "checkmark")
                .foregroundColor(isSelected ? .green : .clear)
                .font(.system(size: 14, weight: .bold))
            
            // 节点名称
            Text(nodeName)
                .font(.system(.body))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            
            Spacer()
            
            // 延迟信息
            if isTesting {
                DelayTestingView()
                    .foregroundStyle(.blue)
                    .scaleEffect(0.8)
            } else if delay > 0 {
                Text("\(delay)")
                    .font(.system(.body, design: .rounded))
                    .foregroundStyle(DelayColor.color(for: delay))
                
                Text("ms")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(DelayColor.color(for: delay).opacity(0.8))
            } else if delay == 0 {
                Image(systemName: "xmark")
                    .foregroundColor(.red)
            } else {
                Image(systemName: "questionmark")
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
} 