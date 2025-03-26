import SwiftUI

struct ConnectivityCard: View {
    @ObservedObject var viewModel: ConnectivityViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    private var cardBackgroundColor: Color {
        colorScheme == .dark ? Color(.systemGray6) : Color(.systemBackground)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("网站访问检测", systemImage: "globe.asia.australia.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.accentColor)
                
                Spacer()
                
                Button(action: {
                    viewModel.testAllConnectivity()
                    HapticManager.shared.impact(.medium)
                }) {
                    HStack(spacing: 4) {
                        if viewModel.isTestingAll {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("全部检测")
                            .font(.system(size: 12))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.1))
                    .cornerRadius(8)
                }
                .disabled(viewModel.isTestingAll)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(viewModel.websites.enumerated()), id: \.element.id) { index, website in
                    ConnectivityItem(
                        website: website,
                        onTap: {
                            viewModel.testConnectivity(for: index)
                            HapticManager.shared.impact(.light)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .background(cardBackgroundColor)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

struct ConnectivityItem: View {
    let website: WebsiteStatus
    let onTap: () -> Void
    
    @State private var showError = false
    
    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: website.icon)
                            .font(.system(size: 16))
                            .foregroundColor(.accentColor)
                        
                        Text(website.name)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    
                    if showError, let error = website.error {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .lineLimit(1)
                            .transition(.opacity)
                    }
                }
                
                Spacer()
                
                if website.isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Image(systemName: website.isConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(website.isConnected ? .green : .red)
                        .font(.system(size: 18))
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.accentColor.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(
                                website.isConnected ? Color.green.opacity(0.3) : 
                                (website.error != nil ? Color.red.opacity(0.3) : Color.gray.opacity(0.2)),
                                lineWidth: 1
                            )
                    )
            )
            .contentShape(Rectangle())
            .onTapGesture {
                if website.error != nil {
                    withAnimation {
                        showError.toggle()
                    }
                }
                onTap()
            }
            .onChange(of: website.error) { error in
                if error != nil {
                    withAnimation {
                        showError = true
                    }
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                        withAnimation {
                            showError = false
                        }
                    }
                } else {
                    withAnimation {
                        showError = false
                    }
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

#Preview {
    let viewModel = ConnectivityViewModel()
    // 模拟一些测试数据
    viewModel.websites[0].isConnected = true
    viewModel.websites[1].isChecking = true
    viewModel.websites[2].error = "连接超时"
    
    return VStack {
        ConnectivityCard(viewModel: viewModel)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
} 