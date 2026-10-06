import SwiftUI

/// Brief confirmation ("Copied “é”") at the bottom of a window.
private struct ToastModifier: ViewModifier {
    let toast: Toast?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let toast {
                Text(toast.message)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .overlay { Capsule().strokeBorder(.separator) }
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(.bottom, 18)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .id(toast.id)
                    .allowsHitTesting(false)
            }
        }
        .animation(.snappy, value: toast)
    }
}

extension View {
    func toast(_ toast: Toast?) -> some View {
        modifier(ToastModifier(toast: toast))
    }
}
