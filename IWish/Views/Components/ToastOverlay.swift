import SwiftUI

// MARK: - Toast Model

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let style: Style
    let message: String
    let duration: TimeInterval

    enum Style {
        case success
        case error
        case warning
        case info

        var icon: String {
            switch self {
            case .success: return "checkmark.circle.fill"
            case .error:   return "xmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info:    return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .success: return .green
            case .error:   return .red
            case .warning: return .orange
            case .info:    return .blue
            }
        }
    }

    static func == (lhs: Toast, rhs: Toast) -> Bool { lhs.id == rhs.id }
}

// MARK: - Toast Manager

@Observable
final class ToastManager {
    static let shared = ToastManager()

    private(set) var current: Toast?
    private var queue: [Toast] = []
    private var dismissTask: Task<Void, Never>?

    func show(_ message: String, style: Toast.Style = .info, duration: TimeInterval = 2.5) {
        let toast = Toast(style: style, message: message, duration: duration)

        if current != nil {
            // Replace current toast immediately — new one takes priority
            dismissTask?.cancel()
            withAnimation(.spring(duration: 0.2)) {
                current = nil
            }
            // Small delay for exit animation before showing new
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.15))
                present(toast)
            }
        } else if !queue.isEmpty {
            queue.append(toast)
        } else {
            present(toast)
        }
    }

    func success(_ message: String) { show(message, style: .success) }
    func error(_ message: String) { show(message, style: .error, duration: 3.5) }
    func warning(_ message: String) { show(message, style: .warning, duration: 3.0) }
    func info(_ message: String) { show(message, style: .info) }

    func dismiss() {
        dismissTask?.cancel()
        withAnimation(.spring(duration: 0.25)) {
            current = nil
        }
        scheduleNext()
    }

    private func present(_ toast: Toast) {
        withAnimation(.spring(duration: 0.35, bounce: 0.2)) {
            current = toast
        }
        dismissTask?.cancel()
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(toast.duration))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    private func scheduleNext() {
        guard !queue.isEmpty else { return }
        let next = queue.removeFirst()
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(0.2))
            self?.present(next)
        }
    }
}

// MARK: - Toast View

private struct ToastBanner: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: toast.style.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(toast.style.tint)

            Text(toast.message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 8, y: 4)
        }
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .onTapGesture { onDismiss() }
        .gesture(
            DragGesture(minimumDistance: 10)
                .onEnded { value in
                    if value.translation.height < -20 {
                        onDismiss()
                    }
                }
        )
    }
}

// MARK: - Toast Overlay Modifier

struct ToastOverlayModifier: ViewModifier {
    let manager: ToastManager

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                ZStack(alignment: .top) {
                    if let toast = manager.current {
                        ToastBanner(toast: toast) {
                            manager.dismiss()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .zIndex(1)
                        .padding(.top, 8)
                    }
                }
                .animation(.spring(duration: 0.35, bounce: 0.2), value: manager.current?.id)
            }
    }
}

extension View {
    func toastOverlay(_ manager: ToastManager = .shared) -> some View {
        modifier(ToastOverlayModifier(manager: manager))
    }
}

// MARK: - Environment Key

private struct ToastManagerKey: EnvironmentKey {
    static let defaultValue: ToastManager = .shared
}

extension EnvironmentValues {
    var toast: ToastManager {
        get { self[ToastManagerKey.self] }
        set { self[ToastManagerKey.self] = newValue }
    }
}
