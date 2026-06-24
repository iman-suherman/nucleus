import AppKit
import Charts
import Combine
import DatabaseKit
import NucleusKit
import SwiftUI
import SyncKit

struct DashboardWorkspaceView: View {
    @EnvironmentObject private var viewModel: AppViewModel
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var syncService = CloudKitSyncService.shared
    @ObservedObject private var cloudSyncService = NucleusCloudSyncService.shared
    @ObservedObject private var weatherService = DashboardWeatherService.shared
    @ObservedObject private var weatherSpeechService = DashboardWeatherSpeechService.shared
    @ObservedObject private var processMetricsService = DashboardProcessMetricsService.shared
    @ObservedObject private var holidayService = DashboardPublicHolidayService.shared
    @ObservedObject private var newsFeedService = DashboardNewsFeedService.shared
    @ObservedObject private var newsSpeechService = DashboardNewsSpeechService.shared

    @State private var holidayExplanations: [String: String] = [:]
    @State private var holidayIcons: [String: String] = [:]
    @State private var holidayMetadataTask: Task<Void, Never>?
    @State private var companionCountryIndex = 0
    @State private var contextPanelsContentHeight: CGFloat = 0
    @State private var dashboardContentWidth: CGFloat = 1200

    @State private var isConnectingNucleusCloud = false
    @State private var nucleusCloudMessage: String?
    @State private var showsWeatherLocationChangePopover = false

    private var dashboardPreferences: DashboardPreferences {
        settings.dashboardPreferences
    }

    private var snapshot: DashboardSnapshot {
        viewModel.dashboardSnapshot()
    }

    private var billPaymentSummary: DashboardBillPaymentSummary {
        DashboardInsightsEngine.billPaymentSummary(
            bills: viewModel.activeBills,
            payments: viewModel.billPayments
        )
    }

    private var usesCompactDashboardLayout: Bool {
        dashboardContentWidth < 760
    }

    private var dashboardPadding: CGFloat {
        usesCompactDashboardLayout ? 16 : 28
    }

    private var dashboardSectionSpacing: CGFloat {
        usesCompactDashboardLayout ? 16 : 28
    }

    private var dashboardRowSpacing: CGFloat {
        usesCompactDashboardLayout ? 12 : 16
    }

    var body: some View {
        ZStack {
            dashboardContent

            if let prompt = viewModel.dashboardIncomingMailPrompt {
                DashboardIncomingMailOverlay(
                    prompt: prompt,
                    onOpenInbox: viewModel.openDashboardIncomingMail,
                    onDismiss: viewModel.dismissDashboardIncomingMail
                )
            }

            if dashboardPreferences.newsFeedEnabled,
               let alert = newsFeedService.breakingNewsAlert {
                DashboardBreakingNewsOverlay(
                    alert: alert,
                    speechService: newsSpeechService,
                    onOpenLink: {
                        newsSpeechService.stop()
                        newsFeedService.openBreakingNewsAlertLink()
                    },
                    onDismiss: {
                        newsSpeechService.stop()
                        newsFeedService.dismissBreakingNewsAlert()
                    }
                )
            }
        }
        .animation(.easeInOut(duration: 0.2), value: viewModel.dashboardIncomingMailPrompt?.id)
        .animation(.easeInOut(duration: 0.2), value: newsFeedService.breakingNewsAlert?.id)
    }

    private var dashboardContent: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: dashboardSectionSpacing) {
                    header
                    metricsAndBillsRow
                    if dashboardPreferences.productivityChartEnabled {
                        productivityCollapsibleSection
                    }
                    if showsDashboardAnalysisStatus {
                        analysisStatusBar
                    }
                }
                .padding(dashboardPadding)
                .frame(width: geometry.size.width, alignment: .leading)
            }
            .onAppear {
                dashboardContentWidth = geometry.size.width
            }
            .onChange(of: geometry.size.width) { _, width in
                dashboardContentWidth = width
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            applyDashboardServiceState()
            DashboardAnalysisService.shared.runAnalysisIfNeeded(force: false)
            viewModel.refreshDashboardIncomingMailAlertIfNeeded()
            newsFeedService.refreshBreakingNewsAlertIfNeeded()
            viewModel.refreshDashboardQuoteForCurrentContext()
            viewModel.refreshDashboardQuoteEmojis()
            viewModel.refreshClipboardDayAnalysisIfNeeded()
            Task { await syncService.refreshAccountStatus() }
        }
        .onDisappear {
            processMetricsService.stopSampling()
            newsFeedService.stopAutoRefresh()
            weatherSpeechService.stop()
            newsSpeechService.stop()
            holidayMetadataTask?.cancel()
        }
        .onChange(of: settings.dashboardPreferences) { _, _ in
            applyDashboardServiceState()
        }
        .onChange(of: settings.publicHolidayCountryCodes) { _, _ in
            companionCountryIndex = 0
            refreshPublicHolidays(force: true)
            newsFeedService.refresh(countryCodes: preferredNewsCountryCodes(), force: true)
        }
        .onChange(of: weatherService.locationSnapshot) { _, _ in
            refreshPublicHolidays(force: false)
            newsFeedService.refresh(countryCodes: preferredNewsCountryCodes(), force: false)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            weatherService.refreshIfNeeded()
            newsFeedService.refresh(countryCodes: preferredNewsCountryCodes(), force: false)
            DashboardAnalysisService.shared.runAnalysisIfNeeded(force: false)
        }
        .onChange(of: holidayService.countryGroups.map(\.countryCode)) { _, _ in
            viewModel.refreshDashboardQuoteForCurrentContext()
            viewModel.refreshDashboardQuoteEmojis()
            refreshHolidayMetadata()
            newsFeedService.refresh(countryCodes: preferredNewsCountryCodes(), force: false)
        }
        .alert("Show today's weather?", isPresented: $weatherService.showLocationPermissionPrompt) {
            Button("Allow Location Access") {
                weatherService.confirmLocationPermissionRequest()
            }
            Button("Not Now", role: .cancel) {
                weatherService.declineLocationPermission()
            }
        } message: {
            Text("Nucleus uses your location to show today's forecast on the Dashboard. You can enable this later in System Settings.")
        }
    }

    private func applyDashboardServiceState() {
        let countryCodes = preferredNewsCountryCodes()

        if dashboardPreferences.weatherEnabled {
            weatherService.beginWeatherAccessFlow()
        }

        if dashboardPreferences.resourceUsageEnabled {
            processMetricsService.startSamplingIfNeeded()
        } else {
            processMetricsService.stopSampling()
        }

        if dashboardPreferences.publicHolidayEnabled {
            refreshPublicHolidays(force: false)
        } else {
            holidayService.clear()
        }

        if dashboardPreferences.newsFeedEnabled {
            newsFeedService.startAutoRefresh(countryCodes: countryCodes)
        } else {
            newsFeedService.stopAutoRefresh()
        }
    }

    private func preferredNewsCountryCodes() -> [String] {
        var codes: [String] = []
        var seen = Set<String>()

        func append(_ code: String?) {
            guard let code else { return }
            let normalized = code.uppercased()
            guard normalized.count == 2, seen.insert(normalized).inserted else { return }
            codes.append(normalized)
        }

        append(weatherService.locationSnapshot?.countryCode)
        for code in settings.publicHolidayCountryCodes {
            append(code)
        }

        if codes.isEmpty {
            append(holidayService.nextHoliday?.countryCode)
            append(Locale.current.region?.identifier)
        }

        return codes
    }

    private func refreshPublicHolidays(force: Bool) {
        guard dashboardPreferences.publicHolidayEnabled else {
            holidayService.clear()
            return
        }

        let snapshot = weatherService.locationSnapshot
        holidayService.refresh(
            selectedCountryCodes: settings.publicHolidayCountryCodes,
            locationCountryCode: snapshot?.countryCode ?? Locale.current.region?.identifier,
            locationSubdivisionCode: snapshot?.subdivisionCode,
            locationLabel: snapshot?.locationLabel,
            force: force
        )
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: usesCompactDashboardLayout ? 12 : 16) {
            greetingWithQuote
            if showsInsightsRow {
                insightsSideBySideRow
            }
            if showsActionPanelsRow {
                dashboardActionPanelsRow
            }
            if showsWeatherResourceRow {
                weatherResourceAndSidebarRow
                    .onPreferenceChange(ContextPanelsContentHeightKey.self) { height in
                        contextPanelsContentHeight = height
                    }
            }
            if dashboardPreferences.publicHolidayEnabled {
                publicHolidayRow
            }
        }
    }

    private var showsInsightsRow: Bool {
        dashboardPreferences.intelligentInsightEnabled || dashboardPreferences.clipboardDayEnabled
    }

    @ViewBuilder
    private var insightsSideBySideRow: some View {
        dashboardColumns(spacing: dashboardRowSpacing) {
            if dashboardPreferences.intelligentInsightEnabled {
                flexDashboardColumn {
                    intelligentInsightBox
                }
            }
            if dashboardPreferences.clipboardDayEnabled {
                flexDashboardColumn {
                    clipboardInsightBox
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var showsActionPanelsRow: Bool {
        dashboardPreferences.nucleusAIEnabled || dashboardPreferences.appleMusicEnabled
    }

    @ViewBuilder
    private var dashboardActionPanelsRow: some View {
        dashboardColumns(spacing: dashboardRowSpacing) {
            if dashboardPreferences.nucleusAIEnabled {
                flexDashboardColumn {
                    DashboardNucleusAIPanel(isExpanded: nucleusAIExpanded)
                }
            }
            if dashboardPreferences.appleMusicEnabled {
                flexDashboardColumn {
                    DashboardMusicPanel(isExpanded: appleMusicExpanded)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var showsWeatherResourceRow: Bool {
        dashboardPreferences.weatherEnabled
            || dashboardPreferences.resourceUsageEnabled
            || dashboardPreferences.cloudSyncPanelEnabled
            || dashboardPreferences.newsFeedEnabled
    }

    private var showsLeftContextPanels: Bool {
        dashboardPreferences.weatherEnabled
            || dashboardPreferences.resourceUsageEnabled
            || dashboardPreferences.cloudSyncPanelEnabled
    }

    private var greetingWithQuote: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            VStack(alignment: .leading, spacing: 6) {
                Text(greetingLine(asOf: context.date))
                    .font(usesCompactDashboardLayout ? .title.bold() : .largeTitle.bold())
                    .fixedSize(horizontal: false, vertical: true)

                if dashboardPreferences.quoteEnabled, let quoteLine {
                    Text(quoteLine)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .truncationMode(.tail)
                }
            }
            .onChange(of: DashboardTimePeriod.current(now: context.date)) { _, _ in
                viewModel.refreshDashboardQuoteForCurrentContext()
                viewModel.refreshDashboardQuoteEmojis()
            }
        }
    }

    private var intelligentInsightExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.intelligentInsightExpanded)
    }

    private var clipboardDayExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.clipboardDayExpanded)
    }

    private var contextPanelsExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.contextPanelsExpanded)
    }

    private var newsFeedExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.newsFeedExpanded)
    }

    private var summaryExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.summaryExpanded)
    }

    private var paymentPreparationExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.paymentPreparationExpanded)
    }

    private var productivityExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.productivityExpanded)
    }

    private var publicHolidayExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.publicHolidayExpanded)
    }

    private var nucleusAIExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.nucleusAIExpanded)
    }

    private var appleMusicExpanded: Binding<Bool> {
        dashboardPreferenceBinding(\.appleMusicExpanded)
    }

    private func dashboardPreferenceBinding(_ keyPath: WritableKeyPath<DashboardPreferences, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings.dashboardPreferences[keyPath: keyPath] },
            set: { newValue in
                var preferences = settings.dashboardPreferences
                preferences[keyPath: keyPath] = newValue
                settings.dashboardPreferences = preferences
            }
        )
    }

    private func greetingLine(asOf date: Date) -> String {
        let celebrateHoliday = dashboardPreferences.publicHolidayEnabled && holidayService.isPublicHoliday(on: date)
        return DashboardGreeting.lineWithDate(
            firstName: DashboardGreeting.firstName,
            now: date,
            isPublicHoliday: celebrateHoliday,
            publicHolidayName: celebrateHoliday ? holidayService.todayPublicHolidayName(on: date) : nil
        )
    }

    private var quoteLine: String? {
        let quote = sanitizedDashboardQuote
        guard !quote.isEmpty else { return nil }
        return DashboardQuotes.displayBody(from: quote, emojis: viewModel.dashboardQuoteEmojis)
    }

    private var sanitizedDashboardQuote: String {
        viewModel.dashboardQuote
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
    }

    private var intelligentInsightBox: some View {
        let paragraphs = DashboardInsightFormatting.insightParagraphs(
            from: snapshot,
            asOf: Date(),
            includeDatePreface: false
        )

        return collapsibleDashboardSection(
            isExpanded: intelligentInsightExpanded,
            title: "Intelligent insight",
            systemImage: "sparkles",
            titleUsesGradient: true
        ) {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                    Text(paragraph.trimmingCharacters(in: .whitespacesAndNewlines))
                        .font(index == 0 ? .subheadline.weight(.semibold) : .caption)
                        .foregroundStyle(index == 0 ? Color.primary : Color.secondary)
                        .lineLimit(index == 0 ? 6 : 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 168, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.12),
                    Color.purple.opacity(0.10),
                    Color.pink.opacity(0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(
                    LinearGradient(
                        colors: [.orange.opacity(0.45), .pink.opacity(0.35), .purple.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5
                )
        }
    }

    @ViewBuilder
    private var clipboardInsightBox: some View {
        if let analysis = viewModel.clipboardDayAnalysis {
            collapsibleDashboardSection(
                isExpanded: clipboardDayExpanded,
                title: clipboardInsightTitle(analysis: analysis),
                systemImage: "doc.on.clipboard",
                titleColor: .primary
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    if !DashboardClipboardDayAnalysisEngine.nonEmptyDisplayLines(analysis.behaviorInsights).isEmpty {
                        compactClipboardBulletSection(
                            title: "Productivity insights",
                            items: analysis.behaviorInsights,
                            accent: .teal,
                            limit: 2,
                            maxLength: 120
                        )
                    }

                    if !DashboardClipboardDayAnalysisEngine.nonEmptyDisplayLines(analysis.improvementSuggestions).isEmpty {
                        compactClipboardBulletSection(
                            title: "Suggestions to improve",
                            items: analysis.improvementSuggestions,
                            accent: .orange,
                            limit: 2,
                            maxLength: 120
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 168, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.teal.opacity(0.25), lineWidth: 1)
            }
        } else {
            collapsibleDashboardSection(
                isExpanded: clipboardDayExpanded,
                title: "Clipboard insight",
                systemImage: "doc.on.clipboard",
                titleColor: .primary
            ) {
                Text("Copy something today to generate productivity insights.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: 168, maxHeight: .infinity, alignment: .topLeading)
            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.teal.opacity(0.25), lineWidth: 1)
            }
        }
    }

    private func clipboardInsightTitle(analysis: DashboardClipboardDayAnalysis) -> String {
        "Clipboard insight · \(analysis.todayCaptureCount) capture\(analysis.todayCaptureCount == 1 ? "" : "s")"
    }

    private func compactDashboardCopy(_ text: String, maxLength: Int) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > maxLength else { return cleaned }
        return String(cleaned.prefix(maxLength - 1)) + "…"
    }

    @ViewBuilder
    private func compactClipboardBulletSection(
        title: String,
        items: [String],
        accent: Color,
        limit: Int,
        maxLength: Int
    ) -> some View {
        let visibleItems = Array(
            DashboardClipboardDayAnalysisEngine.nonEmptyDisplayLines(items).prefix(limit)
        )
        if !visibleItems.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(Array(visibleItems.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(accent.opacity(0.85))
                            .frame(width: 5, height: 5)
                            .padding(.top, 5)

                        Text(compactDashboardCopy(item, maxLength: maxLength))
                            .font(.caption)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var showsDashboardAnalysisStatus: Bool {
        dashboardPreferences.clipboardDayEnabled || dashboardPreferences.productivityChartEnabled
    }

    private func collapsibleDashboardSection<Content: View, Trailing: View>(
        isExpanded: Binding<Bool>,
        title: String,
        systemImage: String,
        titleColor: Color = .primary,
        titleUsesGradient: Bool = false,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded.wrappedValue.toggle()
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Image(systemName: isExpanded.wrappedValue ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 12)

                        if titleUsesGradient {
                            Label {
                                Text(title)
                                    .font(.headline)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.orange, .pink, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: systemImage)
                                    .symbolRenderingMode(.multicolor)
                            }
                        } else {
                            Label {
                                Text(title)
                                    .font(.headline)
                                    .foregroundStyle(titleColor)
                                    .multilineTextAlignment(.leading)
                                    .fixedSize(horizontal: false, vertical: true)
                            } icon: {
                                Image(systemName: systemImage)
                                    .foregroundStyle(.teal)
                            }
                        }

                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                trailing()
                    .layoutPriority(1)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)

            if isExpanded.wrappedValue {
                content()
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var weatherResourceAndSidebarRow: some View {
        dashboardColumns(spacing: dashboardRowSpacing) {
            if showsLeftContextPanels {
                flexDashboardColumn {
                    collapsibleDashboardSection(
                        isExpanded: contextPanelsExpanded,
                        title: contextPanelsTitle,
                        systemImage: "cloud.sun.fill",
                        trailing: {
                            if dashboardPreferences.weatherEnabled {
                                weatherHeaderActions
                            }
                        }
                    ) {
                        contextPanelsContent
                    }
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
                    }
                }
            }

            if dashboardPreferences.newsFeedEnabled {
                flexDashboardColumn {
                    collapsibleDashboardSection(
                        isExpanded: newsFeedExpanded,
                        title: newsFeedTitle,
                        systemImage: "newspaper.fill"
                    ) {
                        newsFeedSection
                    }
                    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
                    }
                }
            }
        }
    }

    private var contextPanelsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if dashboardPreferences.weatherEnabled {
                weatherForecastSection
            }
            if dashboardPreferences.resourceUsageEnabled || dashboardPreferences.cloudSyncPanelEnabled {
                resourceAndCloudSyncRow
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: ContextPanelsContentHeightKey.self, value: proxy.size.height)
            }
        }
    }

    private var contextPanelsTitle: String {
        var parts: [String] = []
        if dashboardPreferences.weatherEnabled {
            if let city = weatherService.weather?.cityName {
                parts.append("Weather · \(city)")
            } else {
                parts.append("Weather")
            }
        }
        if dashboardPreferences.resourceUsageEnabled || dashboardPreferences.cloudSyncPanelEnabled {
            if !dashboardPreferences.weatherEnabled {
                parts.append("Resource & sync")
            }
        }
        return parts.isEmpty ? "Live panels" : parts.joined(separator: " · ")
    }

    private var weatherHeaderActions: some View {
        HStack(spacing: 8) {
            speakWeatherButton
            weatherSyncButton
            changeWeatherLocationButton
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var speakWeatherButton: some View {
        Button {
            toggleWeatherSpeech()
        } label: {
            if weatherSpeechService.isSpeaking {
                Label("Stop", systemImage: "stop.fill")
            } else {
                Label("Speak", systemImage: "speaker.wave.2.fill")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(weatherService.weather == nil)
        .help("Speak today's weather forecast aloud")
    }

    private func toggleWeatherSpeech() {
        if weatherSpeechService.isSpeaking {
            weatherSpeechService.stop()
            return
        }
        guard let weather = weatherService.weather else { return }
        weatherSpeechService.speak(
            weather: weather,
            locationLabel: weatherService.locationSnapshot?.locationLabel
        )
    }

    private var weatherSyncButton: some View {
        Button {
            weatherService.retryWeatherFetch()
        } label: {
            if weatherService.isLoading {
                HStack(spacing: 6) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Syncing…")
                }
            } else {
                Label("Sync", systemImage: "arrow.clockwise")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(weatherService.isLoading)
        .help("Refresh today's weather forecast")
    }

    private var changeWeatherLocationButton: some View {
        Button {
            prepareWeatherLocationChangePopover()
            showsWeatherLocationChangePopover = true
        } label: {
            Label("Location", systemImage: "mappin.and.ellipse")
                .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .help("Look up weather for a different city or postcode")
        .popover(isPresented: $showsWeatherLocationChangePopover, arrowEdge: .bottom) {
            weatherLocationChangePopover
        }
    }

    private var weatherLocationChangePopover: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Change weather location")
                .font(.headline)

            Text("Enter a city name or postcode, or use your current device location.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextField("City or postcode", text: $weatherService.manualLocationDraft)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    applyWeatherLocationChange(useDeviceLocation: false)
                }

            HStack {
                Button("Cancel") {
                    showsWeatherLocationChangePopover = false
                }

                Spacer(minLength: 0)

                Button("Use my location") {
                    applyWeatherLocationChange(useDeviceLocation: true)
                }

                Button("Use") {
                    applyWeatherLocationChange(useDeviceLocation: false)
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 300)
    }

    private func prepareWeatherLocationChangePopover() {
        if weatherService.manualLocationDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            weatherService.manualLocationDraft = weatherService.weather?.cityName ?? ""
        }
    }

    private func applyWeatherLocationChange(useDeviceLocation: Bool) {
        showsWeatherLocationChangePopover = false
        if useDeviceLocation {
            weatherService.retryWeatherFetch()
        } else {
            weatherService.submitManualLocation()
        }
    }

    private var publicHolidayDisplayLayout: DashboardPublicHolidayDisplayLayout {
        DashboardPublicHolidayService.displayLayout(
            countryGroups: holidayService.countryGroups,
            selectedCountryCodes: settings.publicHolidayCountryCodes,
            locationCountryCode: weatherService.locationSnapshot?.countryCode
        )
    }

    private var publicHolidayRowTitle: String {
        publicHolidayDisplayLayout.sectionTitle
    }

    private var publicHolidayRow: some View {
        collapsibleDashboardSection(
            isExpanded: publicHolidayExpanded,
            title: publicHolidayRowTitle,
            systemImage: "calendar.badge.clock"
        ) {
            publicHolidaySection
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var newsFeedTitle: String {
        let codes = preferredNewsCountryCodes()
        let headlineCount = newsFeedService.headlines.count
        let countryNames = codes.map {
            DashboardPublicHolidayCountryCatalog.localizedCountryName(for: $0)
        }
        let countryLabel = newsFeedCountryLabel(for: countryNames)

        if countryLabel.isEmpty {
            if headlineCount == 0 {
                return "News feed"
            }
            return "News feed · \(headlineCount) headline\(headlineCount == 1 ? "" : "s")"
        }

        if headlineCount == 0 {
            return "News feed · \(countryLabel)"
        }
        return "News feed · \(countryLabel) · \(headlineCount) headline\(headlineCount == 1 ? "" : "s")"
    }

    private func newsFeedCountryLabel(for countryNames: [String]) -> String {
        switch countryNames.count {
        case 0:
            return ""
        case 1:
            return countryNames[0]
        case 2:
            return "\(countryNames[0]) and \(countryNames[1])"
        default:
            let head = countryNames.dropLast().joined(separator: ", ")
            return "\(head), and \(countryNames[countryNames.count - 1])"
        }
    }

    private var showsLeftDashboardPanels: Bool {
        dashboardPreferences.weatherEnabled
            || dashboardPreferences.resourceUsageEnabled
            || dashboardPreferences.cloudSyncPanelEnabled
            || dashboardPreferences.publicHolidayEnabled
    }

    private var resourceAndCloudSyncRow: some View {
        dashboardColumns(spacing: dashboardRowSpacing) {
            if dashboardPreferences.resourceUsageEnabled {
                flexDashboardColumn {
                    ResourceUsageSummaryCard(metrics: processMetricsService.metrics)
                }
            }

            if dashboardPreferences.cloudSyncPanelEnabled {
                flexDashboardColumn {
                    headerCloudSyncPanel
                }
            }
        }
    }

    private var newsFeedSection: some View {
        DashboardNewsTickerView(
            headlines: newsFeedService.headlines,
            enrichments: newsFeedService.enrichments,
            isLoading: newsFeedService.isLoading,
            statusMessage: newsFeedService.statusMessage,
            showsHeader: false,
            preferredContentHeight: matchesNewsFeedToContextPanelsHeight ? contextPanelsContentHeight : nil
        )
    }

    private var matchesNewsFeedToContextPanelsHeight: Bool {
        dashboardPreferences.newsFeedEnabled && showsLeftContextPanels
    }

    private func holidayCacheToken(for holiday: DashboardNextPublicHoliday) -> String {
        DashboardPublicHolidayIconService.cacheToken(for: holiday)
    }

    private func refreshHolidayMetadata() {
        holidayMetadataTask?.cancel()
        let layout = publicHolidayDisplayLayout
        var holidays = layout.companions.flatMap(\.holidays)
        if let location = layout.location {
            holidays.append(contentsOf: location.holidays)
        }
        guard !holidays.isEmpty else {
            holidayExplanations = [:]
            return
        }

        var icons = holidayIcons
        var explanations = holidayExplanations
        for holiday in holidays {
            let token = holidayCacheToken(for: holiday)
            if icons[token] == nil {
                icons[token] = DashboardPublicHolidayIconService.cachedSymbol(for: holiday)
                    ?? DashboardPublicHolidayIconService.fallbackSymbol(for: holiday)
            }
            if explanations[token] == nil {
                explanations[token] = DashboardPublicHolidayExplanationService.cachedExplanation(for: holiday)
                    ?? DashboardPublicHolidayExplanationService.fallbackExplanation(for: holiday)
            }
        }
        holidayIcons = icons
        holidayExplanations = explanations

        holidayMetadataTask = Task {
            for holiday in holidays {
                guard !Task.isCancelled else { return }
                let token = holidayCacheToken(for: holiday)
                async let icon = DashboardPublicHolidayIconService.resolveSymbol(for: holiday)
                async let explanation = DashboardPublicHolidayExplanationService.resolveExplanation(for: holiday)
                let resolvedIcon = await icon
                let resolvedExplanation = await explanation
                guard !Task.isCancelled else { return }
                holidayIcons[token] = resolvedIcon
                holidayExplanations[token] = resolvedExplanation
            }
        }
    }

    @ViewBuilder
    private var publicHolidaySection: some View {
        let layout = publicHolidayDisplayLayout
        let companions = layout.companions
        let companionIndex = companions.isEmpty ? 0 : companionCountryIndex % companions.count
        let activeCompanion = companions.isEmpty ? nil : companions[companionIndex]

        if let location = layout.location, let activeCompanion {
            if !location.holidays.isEmpty, !activeCompanion.holidays.isEmpty {
                publicHolidayPairedRows(
                    location: location,
                    companion: activeCompanion,
                    companions: companions,
                    companionIndex: companionIndex
                )
            } else {
                dashboardColumns(spacing: dashboardRowSpacing) {
                    flexDashboardColumn {
                        publicHolidayCountryColumn(location, subtitle: "Your location")
                    }

                    flexDashboardColumn {
                        publicHolidayCountryColumn(
                            activeCompanion,
                            subtitle: companions.count > 1 ? "Selected country \(companionIndex + 1) of \(companions.count)" : "Selected country",
                            showsCompanionControls: companions.count > 1,
                            onPreviousCompanion: {
                                guard companions.count > 1 else { return }
                                companionCountryIndex = (companionIndex - 1 + companions.count) % companions.count
                            },
                            onNextCompanion: {
                                guard companions.count > 1 else { return }
                                companionCountryIndex = (companionIndex + 1) % companions.count
                            }
                        )
                        .animation(.easeInOut(duration: 0.2), value: companionIndex)
                    }
                }
                .onAppear { refreshHolidayMetadata() }
                .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
                    guard companions.count > 1 else { return }
                    companionCountryIndex = (companionIndex + 1) % companions.count
                }
            }
        } else if let location = layout.location {
            publicHolidayCountryColumn(location, subtitle: "Your location")
                .frame(maxWidth: .infinity, alignment: .leading)
                .onAppear { refreshHolidayMetadata() }
        } else if let activeCompanion {
            publicHolidayCountryColumn(
                activeCompanion,
                subtitle: companions.count > 1 ? "Selected country \(companionIndex + 1) of \(companions.count)" : "Selected country",
                showsCompanionControls: companions.count > 1,
                onPreviousCompanion: {
                    guard companions.count > 1 else { return }
                    companionCountryIndex = (companionIndex - 1 + companions.count) % companions.count
                },
                onNextCompanion: {
                    guard companions.count > 1 else { return }
                    companionCountryIndex = (companionIndex + 1) % companions.count
                }
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear { refreshHolidayMetadata() }
            .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
                guard companions.count > 1 else { return }
                companionCountryIndex = (companionIndex + 1) % companions.count
            }
        } else if holidayService.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading public holidays…")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        } else if let statusMessage = holidayService.statusMessage {
            Text(statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func publicHolidayPairedRows(
        location: DashboardPublicHolidayCountryGroup,
        companion: DashboardPublicHolidayCountryGroup,
        companions: [DashboardPublicHolidayCountryGroup],
        companionIndex: Int
    ) -> some View {
        let rowCount = max(location.holidays.count, companion.holidays.count)

        return VStack(alignment: .leading, spacing: 10) {
            dashboardColumns(spacing: dashboardRowSpacing) {
                flexDashboardColumn {
                    publicHolidayColumnHeader(location, subtitle: "Your location")
                }

                flexDashboardColumn {
                    publicHolidayColumnHeader(
                        companion,
                        subtitle: companions.count > 1
                            ? "Selected country \(companionIndex + 1) of \(companions.count)"
                            : "Selected country",
                        showsCompanionControls: companions.count > 1,
                        onPreviousCompanion: {
                            guard companions.count > 1 else { return }
                            companionCountryIndex = (companionIndex - 1 + companions.count) % companions.count
                        },
                        onNextCompanion: {
                            guard companions.count > 1 else { return }
                            companionCountryIndex = (companionIndex + 1) % companions.count
                        }
                    )
                }
            }

            ForEach(0..<rowCount, id: \.self) { index in
                dashboardColumns(spacing: dashboardRowSpacing) {
                    flexDashboardColumn {
                        publicHolidayCardSlot(
                            holiday: index < location.holidays.count ? location.holidays[index] : nil,
                            accentIndex: index
                        )
                    }
                    flexDashboardColumn {
                        publicHolidayCardSlot(
                            holiday: index < companion.holidays.count ? companion.holidays[index] : nil,
                            accentIndex: index
                        )
                    }
                }
            }
        }
        .onAppear { refreshHolidayMetadata() }
        .onReceive(Timer.publish(every: 8, on: .main, in: .common).autoconnect()) { _ in
            guard companions.count > 1 else { return }
            companionCountryIndex = (companionIndex + 1) % companions.count
        }
        .animation(.easeInOut(duration: 0.2), value: companionIndex)
    }

    @ViewBuilder
    private func publicHolidayCardSlot(holiday: DashboardNextPublicHoliday?, accentIndex: Int) -> some View {
        Group {
            if let holiday {
                publicHolidayCard(holiday, accentIndex: accentIndex)
            } else {
                Color.clear
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func publicHolidayColumnHeader(
        _ group: DashboardPublicHolidayCountryGroup,
        subtitle: String,
        showsCompanionControls: Bool = false,
        onPreviousCompanion: (() -> Void)? = nil,
        onNextCompanion: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(subtitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let locationLabel = group.locationLabel {
                    Text("\(group.countryName) · \(locationLabel)")
                        .font(.subheadline.weight(.semibold))
                } else {
                    Text(group.countryName)
                        .font(.subheadline.weight(.semibold))
                }
            }

            Spacer(minLength: 0)

            if showsCompanionControls {
                HStack(spacing: 4) {
                    Button(action: { onPreviousCompanion?() }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.plain)
                    .help("Previous selected country")

                    Button(action: { onNextCompanion?() }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.plain)
                    .help("Next selected country")
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func publicHolidayCountryColumn(
        _ group: DashboardPublicHolidayCountryGroup,
        subtitle: String,
        showsCompanionControls: Bool = false,
        onPreviousCompanion: (() -> Void)? = nil,
        onNextCompanion: (() -> Void)? = nil
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            publicHolidayColumnHeader(
                group,
                subtitle: subtitle,
                showsCompanionControls: showsCompanionControls,
                onPreviousCompanion: onPreviousCompanion,
                onNextCompanion: onNextCompanion
            )

            if group.holidays.isEmpty {
                Text("No upcoming public holidays.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            } else {
                ForEach(Array(group.holidays.enumerated()), id: \.offset) { index, holiday in
                    publicHolidayCard(holiday, accentIndex: index)
                }
            }
        }
    }

    private func publicHolidayCard(_ holiday: DashboardNextPublicHoliday, accentIndex: Int) -> some View {
        let token = holidayCacheToken(for: holiday)
        let symbol = holidayIcons[token] ?? DashboardPublicHolidayIconService.fallbackSymbol(for: holiday)
        let explanation = holidayExplanations[token]
        let iconColor = DashboardPublicHolidayIconService.accentColor(for: holiday, index: accentIndex)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: symbol)
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(iconColor)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(holiday.name)
                        .font(.subheadline.weight(.semibold))
                    Text("\(holiday.relativeDescription) · \(formattedHolidayDate(holiday.date)) · \(holiday.weekdayName) · \(holiday.dayKindLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(holiday.scopeLabel)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(holiday.isNationwide ? iconColor : iconColor.opacity(0.85))

                    if let applicabilityLabel = holiday.applicabilityLabel {
                        Text(applicabilityLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 0)
            }

            if let explanation {
                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 42)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(iconColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func formattedHolidayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func weeklyForecastStrip(_ forecast: [DashboardDailyWeatherForecast]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(forecast) { day in
                    VStack(spacing: 6) {
                        Text(day.dayLabel)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Image(systemName: day.conditionSymbol)
                            .font(.title3)
                            .symbolRenderingMode(.multicolor)
                        Text(day.highTemperature)
                            .font(.caption.weight(.semibold))
                        Text(day.lowTemperature)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(minWidth: 54)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
    }

    @ViewBuilder
    private var weatherForecastSection: some View {
        Group {
            if let prompt = weatherService.locationAccessPrompt {
                locationAccessPromptCard(prompt)
            } else if let weather = weatherService.weather {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 14) {
                        Image(systemName: weather.conditionSymbol)
                            .font(.system(size: 32))
                            .symbolRenderingMode(.multicolor)
                            .frame(width: 40)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(weather.conditionDescription)
                                .font(.title3.weight(.semibold))
                            Text("High \(weather.highTemperature) · Low \(weather.lowTemperature)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if let rainSummary = weather.rainSummary {
                                Text(rainSummary)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }

                        Spacer(minLength: 0)

                        Button {
                            toggleWeatherSpeech()
                        } label: {
                            Image(systemName: weatherSpeechService.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                .font(.title3)
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(weatherSpeechService.isSpeaking ? "Stop speaking weather" : "Speak today's weather forecast")
                    }

                    if !weather.dailyForecast.isEmpty {
                        weeklyForecastStrip(weather.dailyForecast)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
            } else if weatherService.isAwaitingDeviceLocation {
                findingLocationCard
            } else if let statusMessage = weatherService.statusMessage {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: weatherService.isLoading ? "location" : "cloud.slash")
                        .foregroundStyle(.secondary)
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if weatherService.showsManualLocationEntry {
                        manualLocationEntryControls
                    }
                    Spacer(minLength: 0)
                    if !weatherService.isLoading {
                        Button("Try Again") {
                            weatherService.retryWeatherFetch()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            } else if weatherService.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading today's forecast…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            } else {
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: "cloud.slash")
                        .foregroundStyle(.secondary)
                    Text("Weather is unavailable right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Try Again") {
                        weatherService.retryWeatherFetch()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var findingLocationCard: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(weatherService.statusMessage ?? "Finding your location…")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if weatherService.showsManualLocationEntry {
                manualLocationEntryControls
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    private var manualLocationEntryControls: some View {
        HStack(spacing: 8) {
            TextField("City or postcode", text: $weatherService.manualLocationDraft)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 180)
                .controlSize(.small)
                .onSubmit {
                    weatherService.submitManualLocation()
                }
            Button("Use") {
                weatherService.submitManualLocation()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private func locationAccessPromptCard(_ prompt: DashboardWeatherLocationPrompt) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "location.slash")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)

                Text(prompt.message)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(prompt.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(index + 1).")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, alignment: .trailing)
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            Button(prompt.buttonTitle) {
                weatherService.performLocationAccessAction(prompt.action)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var metricsAndBillsRow: some View {
        let showSummary = dashboardPreferences.summaryMetricsEnabled
        let showBills = dashboardPreferences.billPreparationEnabled

        if showSummary || showBills {
            dashboardColumns(spacing: usesCompactDashboardLayout ? 16 : 20) {
                if showSummary {
                    flexDashboardColumn {
                        collapsibleDashboardSection(
                            isExpanded: summaryExpanded,
                            title: summaryTitle,
                            systemImage: "square.grid.2x2.fill"
                        ) {
                            summaryAndResourceCards
                        }
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
                        }
                    }
                }

                if showBills {
                    flexDashboardColumn {
                        collapsibleDashboardSection(
                            isExpanded: paymentPreparationExpanded,
                            title: paymentPreparationTitle,
                            systemImage: "sparkles",
                            titleUsesGradient: true
                        ) {
                            paymentPreparationContent
                        }
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(
                                    LinearGradient(
                                        colors: [.purple.opacity(0.25), .orange.opacity(0.2)],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 1
                                )
                        }
                    }
                }
            }
        }
    }

    private var summaryTitle: String {
        let clipCount = viewModel.clipboardEntries.count
        return "Summary · \(snapshot.unreadMailCount) email · \(snapshot.passwordCount) passwords · \(clipCount) clip\(clipCount == 1 ? "" : "s")"
    }

    private var paymentPreparationTitle: String {
        if billPaymentSummary.groups.isEmpty {
            return "Payment preparation"
        }
        let billCount = billPaymentSummary.groups.reduce(0) { $0 + $1.billCount }
        return "Payment preparation · \(billCount) bill\(billCount == 1 ? "" : "s") due soon"
    }

    @ViewBuilder
    private var paymentPreparationContent: some View {
        if billPaymentSummary.groups.isEmpty {
            Text("Nothing to prepare in the next two weeks.")
                .foregroundStyle(.secondary)
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Spacer()
                    Button("Open Bills") {
                        viewModel.sidebarSelection = .workspace(.bills)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                billPaymentPreparationCard
            }
        }
    }

    private var summaryAndResourceCards: some View {
        DashboardMetricsSummaryBox(
            unreadMailCount: snapshot.unreadMailCount,
            passwordCount: snapshot.passwordCount,
            clipboardCount: viewModel.clipboardEntries.count,
            upcomingBillsCount: snapshot.upcomingBills.count,
            onUnreadEmail: viewModel.openInboxFromDashboardUnreadSummary,
            onPasswords: { viewModel.sidebarSelection = .workspace(.notes) },
            onClipboard: { viewModel.sidebarSelection = .workspace(.clipboard) },
            onBills: { viewModel.sidebarSelection = .workspace(.bills) }
        )
    }

    private var headerCloudSyncPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Cloud sync", systemImage: "icloud")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                cloudSyncRow(
                    title: "Nucleus Cloud",
                    systemImage: "cloud",
                    isConnected: cloudSyncService.status.isConnected,
                    statusLabel: cloudSyncService.status.label,
                    connectTitle: isConnectingNucleusCloud ? "Opening Browser…" : "Connect",
                    isConnectDisabled: isConnectingNucleusCloud,
                    compact: true,
                    onConnect: {
                        isConnectingNucleusCloud = true
                        nucleusCloudMessage = "Authorize this Mac in your browser…"
                        Task {
                            nucleusCloudMessage = await viewModel.connectNucleusCloud()
                            isConnectingNucleusCloud = false
                        }
                    }
                )

                Divider()

                cloudSyncRow(
                    title: "iCloud",
                    systemImage: "icloud.fill",
                    isConnected: iCloudIsConnected,
                    statusLabel: iCloudStatusLabel,
                    connectTitle: iCloudConnectTitle,
                    isConnectDisabled: false,
                    compact: true,
                    onConnect: connectICloud
                )
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))

            if let nucleusCloudMessage {
                Text(nucleusCloudMessage)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var iCloudIsConnected: Bool {
        syncService.status.isAvailable && NucleusDatabase.usesCloudKitSync
    }

    private var iCloudStatusLabel: String {
        if syncService.status.isAvailable, NucleusDatabase.usesCloudKitSync {
            return syncService.status.label
        }
        if !NucleusDatabase.usesCloudKitSync,
           let error = NucleusDatabase.lastCloudKitSetupError,
           !error.isEmpty {
            return error
        }
        return syncService.status.label
    }

    private var iCloudConnectTitle: String {
        if case .noAccount = syncService.status {
            return "Sign in to iCloud"
        }
        return "Open Settings"
    }

    private func connectICloud() {
        if case .noAccount = syncService.status {
            viewModel.openSystemICloudSettings()
            return
        }
        viewModel.openSettings(tab: .iCloud)
        Task { await syncService.refreshAccountStatus() }
    }

    private func cloudSyncRow(
        title: String,
        systemImage: String,
        isConnected: Bool,
        statusLabel: String,
        connectTitle: String,
        isConnectDisabled: Bool,
        compact: Bool = false,
        onConnect: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: compact ? 8 : 12) {
            Image(systemName: isConnected ? "checkmark.circle.fill" : systemImage)
                .foregroundStyle(isConnected ? .green : .secondary)
                .font(compact ? .caption : .body)
                .frame(width: compact ? 16 : 22)

            VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                Text(title)
                    .font(compact ? .caption.weight(.semibold) : .subheadline.weight(.semibold))
                Text(statusLabel)
                    .font(compact ? .caption2 : .caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(compact ? 2 : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            if !isConnected {
                Button(connectTitle, action: onConnect)
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .disabled(isConnectDisabled)
            }
        }
        .padding(.horizontal, compact ? 12 : 16)
        .padding(.vertical, compact ? 8 : 12)
    }

    private var billPaymentPreparationCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(billPaymentSummary.groups) { group in
                HStack(spacing: 12) {
                    Image(systemName: group.category.systemImage)
                        .foregroundStyle(.purple)
                        .frame(width: 22)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(group.category.label) · \(group.currencyCode)")
                            .font(.subheadline.weight(.semibold))
                        Text("\(group.billCount == 1 ? "1 bill" : "\(group.billCount) bills") due \(DashboardInsightsEngine.dueWindowDisplayLabel(from: group.earliestDueDate, to: group.latestDueDate))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Text(NucleusFormatters.currencyString(group.totalAmount, currencyCode: group.currencyCode))
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                if group.id != billPaymentSummary.groups.last?.id {
                    Divider()
                }
            }
        }
        .background(
            LinearGradient(
                colors: [
                    Color.purple.opacity(0.08),
                    Color.orange.opacity(0.06),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    LinearGradient(
                        colors: [.purple.opacity(0.25), .orange.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        }
    }

    private var productivityCollapsibleSection: some View {
        collapsibleDashboardSection(
            isExpanded: productivityExpanded,
            title: productivityTitle,
            systemImage: "chart.bar.fill"
        ) {
            productivitySectionContent
        }
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 14))
        .overlay {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(Color.teal.opacity(0.2), lineWidth: 1)
        }
    }

    private var productivityTitle: String {
        let total = snapshot.productivityBuckets.reduce(0) { $0 + $1.count }
        if total == 0 {
            return "Productivity"
        }
        return "Productivity · \(total) captures (7 days)"
    }

    private var productivitySectionContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("How your recent clipboard captures break down over the last 7 days.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if snapshot.productivityBuckets.allSatisfy({ $0.count == 0 }) {
                ContentUnavailableView(
                    "No clipboard activity yet",
                    systemImage: "doc.on.clipboard",
                    description: Text("Copy something from another app to build your productivity profile.")
                )
                .frame(height: 220)
            } else {
                Chart(snapshot.productivityBuckets) { bucket in
                    BarMark(
                        x: .value("Category", bucket.category.rawValue),
                        y: .value("Captures", bucket.count)
                    )
                    .foregroundStyle(by: .value("Category", bucket.category.rawValue))
                    .cornerRadius(6)
                }
                .chartForegroundStyleScale([
                    ClipboardProductivityCategory.development.rawValue: Color.blue,
                    ClipboardProductivityCategory.communication.rawValue: Color.green,
                    ClipboardProductivityCategory.research.rawValue: Color.purple,
                    ClipboardProductivityCategory.notesAndDrafts.rawValue: Color.orange,
                    ClipboardProductivityCategory.adminText.rawValue: Color.teal,
                    ClipboardProductivityCategory.dataAndNumbers.rawValue: Color.pink,
                ])
                .chartYAxis {
                    AxisMarks(position: .leading)
                }
                .frame(height: 260)
                .padding(16)
                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var analysisStatusBar: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            HStack(spacing: 12) {
                Text(analysisStatusSentence(now: context.date))
                    .fixedSize(horizontal: false, vertical: true)

                Button("Analyse Now") {
                    viewModel.refreshDashboardAnalysisNow()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func analysisStatusSentence(now: Date) -> String {
        let lastAnalysis: String
        if let analyzedAt = viewModel.dashboardAnalyzedAt {
            lastAnalysis = "Last analysis \(DashboardDurationFormatting.analysisAgo(from: analyzedAt, now: now))"
        } else {
            lastAnalysis = "No analysis yet"
        }

        let nextAnalysis: String
        if let nextAt = viewModel.nextDashboardAnalysisAt {
            if nextAt <= now {
                nextAnalysis = "next analyse due now"
            } else {
                nextAnalysis = "next analyse \(DashboardDurationFormatting.analysisUntil(nextAt, now: now))"
            }
        } else {
            nextAnalysis = "next analyse in 30 minutes"
        }

        return "\(lastAnalysis), \(nextAnalysis)."
    }

    @ViewBuilder
    private func dashboardColumns(
        spacing: CGFloat? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let rowSpacing = spacing ?? dashboardRowSpacing
        if usesCompactDashboardLayout {
            VStack(alignment: .leading, spacing: rowSpacing) {
                content()
            }
        } else {
            HStack(alignment: .top, spacing: rowSpacing) {
                content()
            }
        }
    }

    private func flexDashboardColumn<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DashboardMetricsSummaryBox: View {
    let unreadMailCount: Int
    let passwordCount: Int
    let clipboardCount: Int
    let upcomingBillsCount: Int
    let onUnreadEmail: () -> Void
    let onPasswords: () -> Void
    let onClipboard: () -> Void
    let onBills: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Summary", systemImage: "square.grid.2x2")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    SummaryMetricItem(
                        title: "Unread email",
                        value: "\(unreadMailCount)",
                        systemImage: "envelope.badge",
                        tint: .blue,
                        isHighlighted: unreadMailCount > 0,
                        action: onUnreadEmail
                    )

                    Divider()

                    SummaryMetricItem(
                        title: "Passwords stored",
                        value: "\(passwordCount)",
                        systemImage: "key.fill",
                        tint: .orange,
                        action: onPasswords
                    )
                }

                Divider()

                HStack(spacing: 0) {
                    SummaryMetricItem(
                        title: "Recent clips",
                        value: "\(clipboardCount)",
                        systemImage: "doc.on.clipboard",
                        tint: .teal,
                        action: onClipboard
                    )

                    Divider()

                    SummaryMetricItem(
                        title: "Bills due soon",
                        value: "\(upcomingBillsCount)",
                        systemImage: "dollarsign.circle",
                        tint: .purple,
                        action: onBills
                    )
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }
}

private struct SummaryMetricItem: View {
    let title: String
    let value: String
    let systemImage: String
    let tint: Color
    var isHighlighted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(tint)

                Text(value)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
            .background {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.yellow.opacity(0.24))
                }
            }
            .overlay {
                if isHighlighted {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.yellow.opacity(0.55), lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct ResourceUsageSummaryCard: View {
    let metrics: DashboardProcessMetrics?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Resource usage", systemImage: "gauge.with.dots.needle.67percent")
                .font(.subheadline.weight(.semibold))

            VStack(spacing: 0) {
                metricRow(label: "CPU", value: metrics?.formattedCPU ?? "—")
                Divider()
                metricRow(label: "Memory", value: metrics?.formattedMemory ?? "—")
            }
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func metricRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
            Text(value)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ContextPanelsContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
