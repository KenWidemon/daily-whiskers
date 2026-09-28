import SwiftUI
import UIKit

/// A stable native field keeps first responder, selection, and AutoFill intact
/// when password visibility changes. The trailing control lives in SwiftUI.
struct AuthTextField: UIViewRepresentable {
    let label: String
    @Binding var text: String
    @Binding var isFocused: Bool
    var isSecure = false
    var isEnabled = true
    var contentType: UITextContentType = .newPassword
    var returnKey: UIReturnKeyType = .next
    var passwordRules: String?
    var onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.font = .preferredFont(forTextStyle: .body)
        field.textColor = .label
        field.attributedPlaceholder = NSAttributedString(string: label, attributes: [.foregroundColor: UIColor(white: 0.38, alpha: 1)])
        field.accessibilityLabel = label
        field.accessibilityIdentifier = "registration-" + (contentType == .emailAddress ? "email" : label == "Password" ? "password" : "confirmation")
        field.textContentType = contentType
        field.passwordRules = passwordRules.map { UITextInputPasswordRules(descriptor: $0) }
        field.keyboardType = contentType == .emailAddress ? .emailAddress : .default
        field.returnKeyType = returnKey
        field.isEnabled = isEnabled
        if !(field.text ?? "").utf8.elementsEqual(text.utf8) { field.text = text }
        if field.isSecureTextEntry != isSecure {
            let selection = field.selectedTextRange.map {
                (field.offset(from: field.beginningOfDocument, to: $0.start),
                 field.offset(from: field.beginningOfDocument, to: $0.end))
            }
            field.isSecureTextEntry = isSecure
            if field.isFirstResponder {
                // Reset UIKit's secure-entry replacement state through its input
                // API; assigning `text` alone can discard input on the next key.
                field.text = ""
                field.insertText(text)
            }
            if let (start, end) = selection,
               let startPosition = field.position(from: field.beginningOfDocument, offset: start),
               let endPosition = field.position(from: field.beginningOfDocument, offset: end) {
                field.selectedTextRange = field.textRange(from: startPosition, to: endPosition)
            }
        }
        // Do not read a revealed password aloud when VoiceOver focuses the field.
        field.accessibilityValue = contentType == .newPassword ? (text.isEmpty ? "Empty" : "Password entered") : nil
        if isFocused && !field.isFirstResponder && isEnabled {
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard coordinator?.parent.isFocused == true else { return }
                field?.becomeFirstResponder()
            }
        } else if !isFocused && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 200, height: max(30, uiView.intrinsicContentSize.height))
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: AuthTextField
        init(_ parent: AuthTextField) { self.parent = parent }
        @objc func changed(_ field: UITextField) {
            let text = field.text ?? ""
            if !parent.text.utf8.elementsEqual(text.utf8) { parent.text = text }
        }
        func textFieldDidBeginEditing(_ textField: UITextField) {
            if textField.isSecureTextEntry, let text = textField.text, !text.isEmpty {
                // A secure field also prepares to replace its contents when it
                // regains focus. Reinsert to retain the user's editable draft.
                textField.text = ""
                textField.insertText(text)
            }
            if !parent.isFocused { parent.isFocused = true }
        }
        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.isFocused { parent.isFocused = false }
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 54)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.65))
                .shadow(color: .black.opacity(0.03), radius: 8, y: 3))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Color.black.opacity(0.06), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.025), radius: 8, y: 3)
    }
}
