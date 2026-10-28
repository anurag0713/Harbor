import SwiftUI
import UniformTypeIdentifiers

public struct DropZoneView: View {
    @ObservedObject var discovery: SimulatorDiscovery
    @State private var isTargeted: Bool = false
    @State private var status: TransferStatus = .idle
    @State private var bundleIdInput: String = ""
    @State private var showBundleIdSheet: Bool = false

    public init(discovery: SimulatorDiscovery = .shared) {
        self.discovery = discovery
    }

    public var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                        style: StrokeStyle(lineWidth: isTargeted ? 2.5 : 1.5, dash: isTargeted ? [8] : [5])
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(isTargeted ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.03))
                    )

                VStack(spacing: 8) {
                    switch status {
                    case .idle:
                        Image(systemName: isTargeted ? "arrow.down.circle.fill" : "shippingbox")
                            .font(.system(size: 28))
                            .foregroundColor(isTargeted ? .accentColor : .secondary)

                        Text(isTargeted ? "Release to import" : "Drop Photos, Videos, or Files")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)

                        Text("Auto-routed into Simulator Photos & Data")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)

                    case .inProgress(let msg):
                        ProgressView()
                            .scaleEffect(0.85)
                        Text(msg)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                    case .success(let msg):
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 26))
                            .foregroundColor(.green)
                        Text(msg)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.green)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)

                    case .failure(let err):
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.red)
                        Text(err)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 8)
                    }
                }
                .padding(14)
            }
            .frame(height: 115)
            .animation(.easeInOut(duration: 0.2), value: isTargeted)
            .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
                handleDrop(providers: providers)
                return true
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }

        status = .inProgress("Reading dropped items...")

        var collectedURLs: [URL] = []
        let group = DispatchGroup()

        for provider in providers {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    collectedURLs.append(url)
                }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            guard !collectedURLs.isEmpty else {
                self.status = .failure("No valid file URLs detected")
                self.resetStatusAfterDelay()
                return
            }

            self.status = .inProgress("Transferring to \(discovery.selectedDevice?.name ?? "Simulator")...")

            Task {
                let targetUDID = discovery.targetDeviceIdentifier
                let result = await FileRouter.shared.routeAndTransfer(
                    urls: collectedURLs,
                    targetDevice: targetUDID,
                    targetBundleId: bundleIdInput.isEmpty ? nil : bundleIdInput
                )

                await MainActor.run {
                    if result.isSuccess {
                        self.status = .success(result.message)
                    } else {
                        self.status = .failure(result.message)
                    }
                    self.resetStatusAfterDelay()
                }
            }
        }
    }

    private func resetStatusAfterDelay() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            if case .inProgress = self.status { return }
            withAnimation {
                self.status = .idle
            }
        }
    }
}
