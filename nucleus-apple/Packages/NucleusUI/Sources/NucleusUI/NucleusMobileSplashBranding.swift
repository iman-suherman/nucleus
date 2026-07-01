import NucleusCore
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

public struct NucleusMobileSplashBranding: View {
    private let showsFeatureList: Bool

    public init(showsFeatureList: Bool = true) {
        self.showsFeatureList = showsFeatureList
    }

    public var body: some View {
        VStack(spacing: 18) {
            appLogo
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 8, y: 3)

            VStack(spacing: 6) {
                Text(NucleusAppBranding.displayName)
                    .font(.largeTitle.bold())

                Text(NucleusAppBranding.tagline)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                Text("Version \(NucleusAppVersion.current)")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .multilineTextAlignment(.center)

            if showsFeatureList {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(NucleusAppBranding.mobileFeatures) { feature in
                        featureRow(feature)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
        }
    }

    @ViewBuilder
    private var appLogo: some View {
#if canImport(UIKit)
        if UIImage(named: "AppLogo") != nil {
            Image("AppLogo")
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            fallbackAppLogo
        }
#else
        fallbackAppLogo
#endif
    }

    private var fallbackAppLogo: some View {
        Image(systemName: "atom")
            .font(.system(size: 30, weight: .medium))
            .foregroundStyle(NucleusMobileTheme.accent)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(NucleusMobileTheme.accent.opacity(0.12))
    }

    private func featureRow(_ feature: NucleusAppBranding.Feature) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feature.icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(NucleusMobileTheme.accent)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.subheadline.weight(.semibold))
                Text(feature.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
