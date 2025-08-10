import SwiftUI

// 不规则贴纸形状：使用多段三次贝塞尔曲线构成“手绘贴纸”效果
struct IrregularStickerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let w = rect.width
        let h = rect.height

        let tl = CGPoint(x: rect.minX + 0.18 * w, y: rect.minY + 0.08 * h)
        let tr = CGPoint(x: rect.minX + 0.85 * w, y: rect.minY + 0.12 * h)
        let br = CGPoint(x: rect.minX + 0.88 * w, y: rect.minY + 0.88 * h)
        let bl = CGPoint(x: rect.minX + 0.12 * w, y: rect.minY + 0.82 * h)

        path.move(to: tl)
        // 顶边（略向外鼓）
        path.addCurve(
            to: tr,
            control1: CGPoint(x: rect.minX + 0.40 * w, y: rect.minY - 0.02 * h),
            control2: CGPoint(x: rect.minX + 0.65 * w, y: rect.minY + 0.02 * h)
        )

        // 右边（整体外鼓）
        path.addCurve(
            to: br,
            control1: CGPoint(x: rect.minX + 0.96 * w, y: rect.minY + 0.22 * h),
            control2: CGPoint(x: rect.minX + 0.96 * w, y: rect.minY + 0.68 * h)
        )

        // 底边（轻微波浪）
        path.addCurve(
            to: bl,
            control1: CGPoint(x: rect.minX + 0.70 * w, y: rect.minY + 1.02 * h),
            control2: CGPoint(x: rect.minX + 0.35 * w, y: rect.minY + 0.94 * h)
        )

        // 左边（内外交替）
        path.addCurve(
            to: tl,
            control1: CGPoint(x: rect.minX - 0.02 * w, y: rect.minY + 0.70 * h),
            control2: CGPoint(x: rect.minX + 0.03 * w, y: rect.minY + 0.25 * h)
        )

        path.closeSubpath()
        return path
    }
}

/// 一个可复用的“文字 + 图标”贴纸样式视图
/// - 支持浅/深色，自适应动态字体与可访问性
/// - 可配置主色、图标、文案与可选的角度旋转与阴影
struct StickerTagView: View {
    let text: String
    let systemImage: String
    var tint: Color = .blue
    var rotation: Angle = .degrees(-4)
    enum IconPosition { case leading, trailing }
    var iconPosition: IconPosition = .trailing
    var contentPadding: EdgeInsets = EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14)
    var textFont: Font = .system(size: 18, weight: .semibold)
    var iconFont: Font = .system(size: 22, weight: .semibold)
    var cornerRadius: CGFloat = 18
    var shadowRadius: CGFloat = 12
    var shadowOpacity: Double = 0.06

    var body: some View {
        HStack(spacing: 10) {
            if iconPosition == .leading {
                Image(systemName: systemImage)
                    .font(.system(size: 22, weight: .semibold))
            }

            Text(text)
                .font(textFont)
                .fixedSize(horizontal: false, vertical: true)

            if iconPosition == .trailing {
                Image(systemName: systemImage)
                    .font(iconFont)
            }
        }
        .foregroundColor(tint)
        .padding(contentPadding)
        .background(
            IrregularStickerShape()
                .fill(Color(.systemBackground))
                .overlay(
                    IrregularStickerShape()
                        .stroke(tint.opacity(0.15), lineWidth: 1)
                )
        )
        .shadow(color: Color.black.opacity(shadowOpacity), radius: shadowRadius, x: 0, y: 8)
        .rotationEffect(rotation)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    VStack(spacing: 20) {
        StickerTagView(text: "预览", systemImage: "trophy.fill")
        StickerTagView(text: "立即启用", systemImage: "hand.tap.fill", tint: .green, rotation: .degrees(3), iconPosition: .leading)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
}


