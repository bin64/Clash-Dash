import SwiftUI

struct OverviewCardSettingsView: View {
    @StateObject private var settings = OverviewCardSettings()
    
    var body: some View {
        List {
            Section {
                ForEach(settings.cardOrder) { card in
                    HStack {
                        Image(systemName: "line.3.horizontal")
                            .foregroundColor(.gray)
                            .font(.system(size: 14))
                        
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
        }
        .navigationTitle("概览页面设置")
        .navigationBarTitleDisplayMode(.inline)
        .environment(\.editMode, .constant(.active))
    }
} 