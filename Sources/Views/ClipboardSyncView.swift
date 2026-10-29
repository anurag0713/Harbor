import SwiftUI

public struct ClipboardSyncView: View {
    @ObservedObject var clipboard = ClipboardService.shared
    @ObservedObject var discovery = SimulatorDiscovery.shared

    @State private var feedbackText: String?
    @State private var feedbackIsError: Bool = false

    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Clipboard Sync", systemImage: "doc.on.clipboard")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("⌥⇧V")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15))
                    .cornerRadius(4)
                    .foregroundColor(.secondary)
            }

            // Preview box
            HStack(spacing: 6) {
                Image(systemName: "text.quote")
                    .foregroundColor(.secondary)
                    .font(.system(size: 11))
                Text(clipboard.currentHostPreview)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(6)

            // Buttons
            HStack(spacing: 8) {
                Button(action: pushClipboard) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.up.forward.app")
                        Text("Mac → Sim")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Button(action: pullClipboard) {
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.backward.and.arrow.up.forward")
                        Text("Sim → Mac")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
            }

            Text("Copies and syncs clipboard text between your Mac and the simulator.")
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let feedback = feedbackText {
                HStack(spacing: 4) {
                    Image(systemName: feedbackIsError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundColor(feedbackIsError ? .red : .green)
                    Text(feedback)
                        .foregroundColor(feedbackIsError ? .red : .green)
                        .font(.system(size: 11))
                }
                .transition(.opacity)
            }
        }
        .onAppear {
            clipboard.updateHostPreview()
        }
    }

    private func pushClipboard() {
        Task {
            let res = await clipboard.pushToSimulator(targetDevice: discovery.targetDeviceIdentifier)
            await MainActor.run {
                showFeedback(message: res.message, isError: !res.isSuccess)
            }
        }
    }

    private func pullClipboard() {
        Task {
            let res = await clipboard.pullFromSimulator(targetDevice: discovery.targetDeviceIdentifier)
            await MainActor.run {
                showFeedback(message: res.message, isError: !res.isSuccess)
            }
        }
    }

    private func showFeedback(message: String, isError: Bool) {
        feedbackText = message
        feedbackIsError = isError
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                self.feedbackText = nil
            }
        }
    }
}
