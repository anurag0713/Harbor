import SwiftUI

public struct KeyboardResetView: View {
    @ObservedObject var discovery = SimulatorDiscovery.shared
    @State private var isResetting: Bool = false
    @State private var statusFeedback: (message: String, isSuccess: Bool)?

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Simulator Keyboard Fix")
                        .font(.system(size: 13, weight: .semibold))
                }

                Spacer()

                Button(action: {
                    triggerReset()
                }) {
                    HStack(spacing: 4) {
                        if isResetting {
                            ProgressView()
                                .controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        Text("Reset Keys")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.primary.opacity(0.08))
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .disabled(isResetting)
            }

            Text("Fixes stuck Shift/modifier keys when running multiple simulators in Device Hub.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let feedback = statusFeedback {
                HStack(spacing: 4) {
                    Image(systemName: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(feedback.isSuccess ? .green : .red)
                    Text(feedback.message)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(feedback.isSuccess ? .green : .red)
                }
                .transition(.opacity)
            }
        }
    }

    private func triggerReset() {
        isResetting = true
        Task {
            let res = await SimulatorService.shared.resetKeyboardFocus(deviceUDID: discovery.targetDeviceIdentifier)
            await MainActor.run {
                isResetting = false
                statusFeedback = (message: res.message, isSuccess: res.isSuccess)
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                    withAnimation {
                        statusFeedback = nil
                    }
                }
            }
        }
    }
}
