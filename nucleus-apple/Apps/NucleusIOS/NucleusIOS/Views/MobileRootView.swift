import NucleusCore
import NucleusUI
import SwiftUI

struct MobileRootView: View {
    @EnvironmentObject private var viewModel: MobileAppViewModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        Group {
            if viewModel.isBootstrapping {
                ProgressView(viewModel.statusMessage)
            } else if horizontalSizeClass == .regular {
                TabletRootView()
            } else {
                PhoneRootView()
            }
        }
        .tint(NucleusMobileTheme.accent)
        .sheet(isPresented: $viewModel.showAddAccount) {
            AddAccountSheet { email, name in
                viewModel.addAccount(email: email, displayName: name)
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
