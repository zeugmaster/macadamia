import SwiftUI
import UIKit

// TODO: This needs to adjust dynamically to system font size and set its own idealHeight
// UIKit component
class TokenTextField: UIView {
    private var textView: UITextView = {
        let textView = UITextView()
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.font = UIFont.monospacedSystemFont(ofSize: 18, weight: .regular)
        textView.isScrollEnabled = false // Disable scrolling to ensure all content is visible at once
        textView.textContainer.lineBreakMode = .byTruncatingTail // Ensure ellipsis at the end if text exceeds space
        textView.layer.borderWidth = 0
        textView.layer.borderColor = UIColor.lightGray.cgColor
        textView.layer.cornerRadius = 5.0
        textView.textColor = .lightGray
        textView.layer.backgroundColor = UIColor.clear.cgColor
        textView.isEditable = false
        textView.isSelectable = false
        return textView
    }()

    init() {
        super.init(frame: .zero)
        setupViews()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupViews() {
        addSubview(textView)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: topAnchor),
            textView.bottomAnchor.constraint(equalTo: bottomAnchor),
            textView.leadingAnchor.constraint(equalTo: leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    var text: String? {
        get { textView.text }
        set { textView.text = newValue }
    }
}

struct TokenText: UIViewRepresentable {
    var text: String

    func makeUIView(context _: Context) -> TokenTextField {
        TokenTextField()
    }

    func updateUIView(_ uiView: TokenTextField, context _: Context) {
        uiView.text = text
    }
}

#Preview {
    TokenText(text: "cashuAeyJ0b2tlbiI6W3sicHJvb2ZzIjpbeyJpZCI6IjAwYThjZDljNjViNDNlM2YiLCJhbW91bnQiOjEsIkMiOiIwMjA2MjkzYTFjN2M3MmNiMDgyMjE0MjEwOGUwMDVjNDdlYzJhMmU2MTJjMjgzZTIyNjQ1NTk3NzdmMjFlOGJmZDgiLCJzZWNyZXQiOiI4ZTg4MGEwNjk2ZDllNDdiMmJkMjMzOWMwZWI0MGY0NDFkMWI5YWY0ZDgzYzlhNDY4M")
        .frame(maxHeight: 100)
}
