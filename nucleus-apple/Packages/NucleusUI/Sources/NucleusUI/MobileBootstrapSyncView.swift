import NucleusCore
import SwiftUI

public struct MobileBootstrapSyncView: View {
    private let stage: MobileBootstrapStage
    private let detailMessage: String

    public init(stage: MobileBootstrapStage, detailMessage: String) {
        self.stage = stage
        self.detailMessage = detailMessage
    }

    public var body: some View {
        VStack(spacing: 28) {
            NucleusMobileSplashBranding(showsFeatureList: false)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    ProgressView(value: stage.progress)
                        .tint(NucleusMobileTheme.accent)

                    Text("\(Int(stage.progress * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(stage.title)
                        .font(.headline)

                    Text(detailMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Sync steps")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    ForEach(MobileBootstrapStage.allCases) { step in
                        stepRow(step)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .frame(maxWidth: 360)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .accessibilityIdentifier("mobile.bootstrap.sync")
    }

    @ViewBuilder
    private func stepRow(_ step: MobileBootstrapStage) -> some View {
        let status = step.status(for: stage)

        HStack(alignment: .center, spacing: 10) {
            MobileSyncStepIndicator(status: status)

            Text(step.title)
                .font(status == .active ? .subheadline.weight(.semibold) : .subheadline)
                .foregroundStyle(status == .pending ? .secondary : .primary)
        }
    }
}

private struct MobileSyncStepIndicator: View {
    let status: MobileBootstrapStepStatus

    var body: some View {
        ZStack {
            switch status {
            case .completed:
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.green)
            case .active:
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.85)
            case .pending:
                Image(systemName: "circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 22, height: 22, alignment: .center)
    }
}
