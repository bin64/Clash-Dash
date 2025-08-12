import SwiftUI
import UIKit

struct YAMLTextView: UIViewRepresentable {
    @Binding var text: String
    let font: UIFont
    
    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.backgroundColor = .clear
        textView.autocapitalizationType = .none
        textView.autocorrectionType = .no
        textView.smartDashesType = .no
        textView.smartQuotesType = .no
        textView.smartInsertDeleteType = .no
        // 显式启用中文输入法支持
        textView.inputView = nil
        textView.inputAccessoryView = createKeyboardToolbar(coordinator: context.coordinator)
        textView.keyboardType = .default
        textView.layoutManager.allowsNonContiguousLayout = false
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        
        // 初始设置文本和高亮
        textView.text = text
        highlightSyntax(textView)
        return textView
    }
    
    func updateUIView(_ uiView: UITextView, context: Context) {
        // 只在非组合文本状态下更新文本和高亮
        if uiView.text != text && !context.coordinator.isUpdatingText && !context.coordinator.isComposingText {
            let selectedRange = uiView.selectedRange
            uiView.text = text
            highlightSyntax(uiView)
            uiView.selectedRange = selectedRange
        }
    }
    
    private func highlightSyntax(_ textView: UITextView) {
        // 如果有标记文本（正在输入中文），不执行高亮
        if textView.markedTextRange != nil {
            return
        }
        
        let attributedText = NSMutableAttributedString(string: textView.text)
        let wholeRange = NSRange(location: 0, length: textView.text.utf16.count)
        let selectedRange = textView.selectedRange
        
        // 设置基本字体和颜色
        attributedText.addAttribute(.font, value: font, range: wholeRange)
        attributedText.addAttribute(.foregroundColor, value: UIColor.label, range: wholeRange)
        
        // 使用基于 Yams 的语法分析进行高亮
        let syntaxElements = YAMLHighlighter.analyzeSyntax(textView.text)
        YAMLHighlighter.applySyntaxHighlighting(
            to: attributedText,
            elements: syntaxElements,
            font: font
        )
        
        textView.attributedText = attributedText
        textView.selectedRange = selectedRange
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    private func createKeyboardToolbar(coordinator: Coordinator) -> UIToolbar {
        let toolbar = UIToolbar()
        toolbar.sizeToFit()
        
        let flexSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        let doneButton = UIBarButtonItem(title: "完成", style: .done, target: coordinator, action: #selector(Coordinator.dismissKeyboard))
        
        toolbar.items = [flexSpace, doneButton]
        return toolbar
    }
    
    class Coordinator: NSObject, UITextViewDelegate {
        var parent: YAMLTextView
        var isUpdatingText = false
        var isComposingText = false
        
        init(_ parent: YAMLTextView) {
            self.parent = parent
        }
        
        func textViewDidChange(_ textView: UITextView) {
            // 检查是否在中文输入过程中
            isComposingText = textView.markedTextRange != nil
            
            // 只有在非中文输入过程中才更新文本和高亮
            if !isComposingText {
                isUpdatingText = true
                parent.text = textView.text
                parent.highlightSyntax(textView)
                isUpdatingText = false
            } else {
                // 在中文输入过程中，只更新文本，不执行高亮
                isUpdatingText = true
                parent.text = textView.text
                isUpdatingText = false
            }
        }
        
        // 处理输入法组合文本
        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            // 当用户点击输入法候选词时，text会包含完整的候选词
            return true
        }
        
        // 输入法编辑中时调用
        func textViewDidBeginEditing(_ textView: UITextView) {
            // 确保输入视图可用
            if textView.inputView != nil {
                textView.inputView = nil
                textView.reloadInputViews()
            }
        }
        
        // 处理中文输入法的组合状态
        func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange, interaction: UITextItemInteraction) -> Bool {
            return true
        }
        
        // 标记中文输入法正在组合文本
        func textViewDidChangeSelection(_ textView: UITextView) {
            let markedTextRange = textView.markedTextRange
            isComposingText = markedTextRange != nil
        }
        
        @objc func dismissKeyboard() {
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
} 