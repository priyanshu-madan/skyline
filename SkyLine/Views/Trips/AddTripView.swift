//
//  AddTripView.swift
//  SkyLine
//
//  View for creating new trips.
//
//  This file also hosts the app's FORM PRIMITIVES (below the AddTripView body).
//  Every form and settings surface in SkyLine — AddTrip, AddEntry, EditEntry,
//  LocationPicker, Settings, EditProfile — is assembled from them, so a field in
//  one screen is physically the same object as a field in another.
//

import SwiftUI
import CoreLocation
import MapKit

struct AddTripView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss


    @State private var title = ""
    @State private var destination = ""
    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
    @State private var description = ""
    @State private var selectedDestination: DestinationSuggestion?
    @State private var showingSuggestions = false
    @State private var searchWorkItem: DispatchWorkItem?
    @State private var isSelectingFromDropdown = false

    @StateObject private var destinationSearchManager = DestinationSearchManager()

    @State private var isCreating = false
    @State private var error: String?
    @State private var showingMapActions = false

    @FocusState private var isDestinationFieldFocused: Bool

    @ScaledMetric(relativeTo: .body) private var mapHeight: CGFloat = 190

    // Validation
    private var isValidTrip: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        endDate > startDate
    }

    var body: some View {
        let theme = themeManager.currentTheme

        return ZStack {
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FormScreenHeader(title: "Create Trip") { dismiss() }

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        tripSection
                        datesSection
                        notesSection

                        if let error = error {
                            FormErrorBanner(message: error)
                        }

                        actionButtonsSection
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .skylineScrollEdges()
            }
        }
        // System-drawn controls (the compact DatePicker chip, the text caret, the
        // menu sheet) resolve against the environment's colour scheme, not against
        // `themeManager`. Pinning it here is what keeps them in the app's theme
        // rather than the device's when this screen is presented modally.
        .environment(\.colorScheme, theme.colorScheme)
        .confirmationDialog(
            "View on Maps",
            isPresented: $showingMapActions,
            titleVisibility: .visible,
            presenting: selectedDestination
        ) { selectedDest in
            Button("View on Apple Maps") {
                openInAppleMaps(destination: selectedDest)
            }

            Button("View on Google Maps") {
                openInGoogleMaps(destination: selectedDest)
            }

            Button("Cancel", role: .cancel) {
                // Explicitly handle cancel
            }
        }
    }

    // MARK: - Sections

    private var tripSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "The trip")

            FormField(
                title: "Trip title",
                text: $title,
                placeholder: "Summer in Japan",
                isRequired: true,
                icon: "suitcase"
            )

            destinationField
        }
    }

    private var destinationField: some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: "Destination", isRequired: true)

            FormFieldRow(icon: "mappin", isFocused: isDestinationFieldFocused) {
                TextField("Where are you going?", text: $destination)
                    .appFont(.body, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)
                    .tint(theme.colors.primary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .focused($isDestinationFieldFocused)
                    .onChange(of: destination) { _, newValue in
                        searchDestinations(newValue)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if showingSuggestions && (!destinationSearchManager.searchResults.isEmpty || destinationSearchManager.isSearching) {
                DestinationSearchResultsView(
                    searchResults: destinationSearchManager.searchResults,
                    isSearching: destinationSearchManager.isSearching,
                    onSelect: { completion in
                        selectDestination(completion)
                    }
                )
            }

            if let selectedDest = selectedDestination {
                destinationMapPreview(for: selectedDest)
            }
        }
    }

    private var datesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Dates")

            HStack(alignment: .top, spacing: AppSpacing.sm + 4) {
                dateWell(title: "Start", label: "Start date", selection: $startDate)
                dateWell(title: "End", label: "End date", selection: $endDate)
            }

            if endDate <= startDate {
                FormHint(text: "The end date needs to come after the start date.", isCritical: true)
            }
        }
    }

    private func dateWell(title: String, label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: title)

            FormFieldRow(icon: "calendar") {
                DatePicker(label, selection: selection, displayedComponents: .date)
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(themeManager.currentTheme.colors.primary)
                    .accessibilityLabel(Text(label))

                Spacer(minLength: 0)
            }
        }
    }

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Notes")

            FormField(
                title: "Anything worth remembering",
                text: $description,
                placeholder: "Who you went with, what you booked…",
                isMultiline: true,
                icon: "doc.text"
            )
        }
    }

    // MARK: - Destination Map Preview

    private func destinationMapPreview(for destination: DestinationSuggestion) -> some View {
        let theme = themeManager.currentTheme
        let coordinate = CLLocationCoordinate2D(
            latitude: destination.latitude,
            longitude: destination.longitude
        )
        let region = MKCoordinateRegion(
            center: coordinate,
            span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
        )
        let shape = RoundedRectangle(cornerRadius: AppRadius.card, style: .continuous)

        return Map(initialPosition: .region(region)) {
            Marker(destination.displayName, coordinate: coordinate)
                .tint(theme.colors.primary)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControlVisibility(.hidden)
        .allowsHitTesting(false)
        .id("\(destination.latitude),\(destination.longitude)")  // Force map to recreate when destination changes
        .frame(height: mapHeight)
        .frame(maxWidth: .infinity)
        .clipShape(shape)
        // The map is its own imagery, so the only elevation cue it gets is a
        // definition line. A shadow here would be invisible on the dark page and
        // a second signal on the light one.
        .overlay(shape.stroke(theme.colors.border, lineWidth: 1))
        .overlay(alignment: .bottomLeading) {
            // Never bare text on a map: the affordance rides in a glass capsule.
            HStack(spacing: AppSpacing.xs + 2) {
                Image(systemName: "map")
                Text("Open in Maps")
            }
            .appFont(.verdictLabel)
            .foregroundStyle(theme.colors.text)
            .padding(.horizontal, AppSpacing.sm + 2)
            .padding(.vertical, AppSpacing.xs + 2)
            .skylineGlassCapsule(theme: theme)
            .padding(AppSpacing.glassInset)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            showingMapActions = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Map showing \(destination.displayName)"))
        .accessibilityHint(Text("Opens in Maps"))
        .accessibilityAddTraits(.isButton)
    }

    // MARK: - Action Buttons Section

    private var actionButtonsSection: some View {
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.sm) {
                FormPrimaryButton(
                    title: "Create Trip",
                    systemImage: "checkmark",
                    busyTitle: "Creating…",
                    isBusy: isCreating,
                    isEnabled: isValidTrip
                ) {
                    createTrip()
                }

                FormSecondaryButton(title: "Cancel") {
                    dismiss()
                }
            }
        }
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Helper Methods

    private func searchDestinations(_ query: String) {
        // Don't trigger search if we're programmatically setting from dropdown
        if isSelectingFromDropdown {
            isSelectingFromDropdown = false
            return
        }

        // Cancel previous search
        searchWorkItem?.cancel()

        guard !query.isEmpty, query.count > 2 else {
            destinationSearchManager.clearSearch()
            showingSuggestions = false
            return
        }

        // Debounce search requests
        let workItem = DispatchWorkItem {
            destinationSearchManager.search(for: query)
            showingSuggestions = true
        }

        searchWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: workItem)
    }

    private func selectDestination(_ completion: MKLocalSearchCompletion) {
        Task {
            if let destinationSuggestion = await destinationSearchManager.getLocationDetails(for: completion) {
                await MainActor.run {
                    selectedDestination = destinationSuggestion
                    isSelectingFromDropdown = true
                    destination = destinationSuggestion.displayName
                    showingSuggestions = false
                    isDestinationFieldFocused = false // Dismiss keyboard
                }
            }
        }
    }

    // MARK: - Map Actions

    private func openDirections(to destination: DestinationSuggestion) {
        let coordinate = CLLocationCoordinate2D(
            latitude: destination.latitude,
            longitude: destination.longitude
        )
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = destination.displayName
        mapItem.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDriving])
    }

    private func openInAppleMaps(destination: DestinationSuggestion) {
        let coordinate = CLLocationCoordinate2D(
            latitude: destination.latitude,
            longitude: destination.longitude
        )
        let mapItem = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        mapItem.name = destination.displayName
        mapItem.openInMaps()
    }

    private func openInGoogleMaps(destination: DestinationSuggestion) {
        // URL encode the place name for Google Maps
        let placeName = destination.displayName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""

        // Use place name with coordinates for more accurate results
        let googleMapsURL = "comgooglemaps://?q=\(placeName)&center=\(destination.latitude),\(destination.longitude)"
        let googleMapsWebURL = "https://www.google.com/maps/search/?api=1&query=\(placeName)"

        if let url = URL(string: googleMapsURL), UIApplication.shared.canOpenURL(url) {
            // Google Maps app is installed
            UIApplication.shared.open(url)
        } else if let url = URL(string: googleMapsWebURL) {
            // Fall back to web version
            UIApplication.shared.open(url)
        }
    }

    private func createTrip() {
        guard isValidTrip else { return }

        isCreating = true
        error = nil

        Task {
            let tripId = UUID().uuidString

            let trip = Trip(
                id: tripId,
                title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                destination: destination.trimmingCharacters(in: .whitespacesAndNewlines),
                destinationCode: selectedDestination?.airportCode,
                state: selectedDestination?.state,
                country: selectedDestination?.country,
                startDate: startDate,
                endDate: endDate,
                description: description.isEmpty ? nil : description.trimmingCharacters(in: .whitespacesAndNewlines),
                coverImageURL: nil,
                latitude: selectedDestination?.latitude,
                longitude: selectedDestination?.longitude
            )

            let result = await tripStore.addTrip(trip)

            await MainActor.run {
                isCreating = false

                switch result {
                case .success:
                    dismiss()
                case .failure(let tripError):
                    error = tripError.localizedDescription
                }
            }
        }
    }
}

// =====================================================================
// MARK: - FORM PRIMITIVES
// =====================================================================
//
// SURFACE MODEL, and why forms differ from the rest of the app:
//
//   A card is LIFTED — you could pick it up — so it is glass.
//   A field is RECESSED — a slot you put something into — so it is an opaque
//   `surface` well with a single 1pt `border` hairline and no shadow.
//
// That reads correctly in both palettes for opposite reasons. In light,
// surface 0xFFFFFF on background 0xF7F8FC is a ~1.5% luminance step: almost
// nothing, which is exactly what a recessed slot should be, with the hairline
// doing the defining. In dark, surface 0x151D30 on background 0x0A0F1C is a
// small step *upward*; again too little to read as a lifted card, exactly right
// for a well.
//
// Read-only values fill with `background` instead of `surface`, so a field you
// cannot type into physically recedes to the page. That is a real semantic
// distinction, expressed with two tokens rather than one token at two opacities.

// MARK: Form Well
/// The recessed field treatment. One elevation signal: a `border` hairline.
/// Never a shadow — a black-based shadow has nowhere to go on 0x0A0F1C.
private struct FormWellStyle: ViewModifier {
    let theme: AppTheme
    let cornerRadius: CGFloat
    let isEditable: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(shape.fill(isEditable ? theme.colors.surface : theme.colors.background))
            .overlay(
                shape.stroke(
                    isFocused ? theme.colors.primary : theme.colors.border,
                    lineWidth: isFocused ? 1.5 : 1
                )
            )
            .containerShape(shape)
            .animation(.easeInOut(duration: 0.22), value: isFocused)
    }
}

/// The floating panel treatment, for surfaces that genuinely hover above the page
/// (a search dropdown). Elevation is chosen per theme because the two palettes have
/// opposite luminance polarity: a shadow simply does not exist on a near-black page,
/// and a hairline is a hard mechanical line on warm paper.
private struct FormPanelStyle: ViewModifier {
    let theme: AppTheme
    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(shape.fill(theme.colors.surface))
            .clipShape(shape)
            .overlay {
                if theme == .dark {
                    shape.stroke(theme.colors.border, lineWidth: 1)
                }
            }
            .shadow(
                color: theme == .light ? theme.colors.scrim : Color.clear,
                radius: 14,
                x: 0,
                y: 6
            )
            .containerShape(shape)
    }
}

extension View {
    /// Recessed field chrome. The default for anything the user types into.
    func formWell(
        theme: AppTheme,
        cornerRadius: CGFloat = AppRadius.xl,
        isEditable: Bool = true,
        isFocused: Bool = false
    ) -> some View {
        modifier(
            FormWellStyle(
                theme: theme,
                cornerRadius: cornerRadius,
                isEditable: isEditable,
                isFocused: isFocused
            )
        )
    }

    /// Lifted panel chrome, for dropdowns that overlay the form.
    func formFloatingPanel(theme: AppTheme, cornerRadius: CGFloat = AppRadius.lg) -> some View {
        modifier(FormPanelStyle(theme: theme, cornerRadius: cornerRadius))
    }
}

// MARK: - Form Screen Header
/// One header for every form and settings screen: a glass back control, a title,
/// and an optional trailing text action. The circular control is
/// `SkyLineGlassIconButton` so the hit target, the symbol size and the haptic are
/// the same object the globe overlay uses.
struct FormScreenHeader: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    var trailingTitle: String? = nil
    var isTrailingBusy: Bool = false
    var onBack: () -> Void
    var onTrailing: (() -> Void)? = nil

    @ScaledMetric(relativeTo: .body) private var controlWidth: CGFloat = 44

    var body: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.sm) {
            SkyLineGlassIconButton(
                systemImage: "chevron.left",
                accessibilityLabel: "Back",
                action: onBack
            )

            Spacer(minLength: AppSpacing.sm)

            Text(title)
                .appFont(.headline, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.text)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: AppSpacing.sm)

            Group {
                if let trailingTitle, let onTrailing {
                    Button(action: onTrailing) {
                        Group {
                            if isTrailingBusy {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(trailingTitle)
                                    .appFont(.bodyBold, lineLimit: .exactly(1))
                            }
                        }
                        .frame(minWidth: controlWidth)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(theme.colors.primary)
                    .tint(theme.colors.primary)
                } else {
                    // Balances the leading control so the title stays optically centred.
                    Color.clear
                        .frame(width: controlWidth, height: controlWidth)
                        .accessibilityHidden(true)
                }
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.sm)
        .padding(.bottom, AppSpacing.lg)
    }
}

// MARK: - Section Header
/// The one section-header convention: verdict-label weight, uppercased, secondary
/// ink, and a real header trait so VoiceOver can jump between sections.
struct FormSectionHeader: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String

    var body: some View {
        Text(title.uppercased())
            .appFont(.verdictLabel, lineLimit: .exactly(1))
            .foregroundStyle(themeManager.currentTheme.colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - Field Label
struct FormFieldLabel: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    var isRequired: Bool = false

    var body: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.xs + 2) {
            Text(title)
                .appFont(.captionBold, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.text)

            if isRequired {
                Text("Required")
                    .appFont(.footnote, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Field Row
/// The canonical field container: an optional leading glyph well, then whatever
/// control the field needs, inside one recessed surface.
struct FormFieldRow<Content: View>: View {
    @EnvironmentObject var themeManager: ThemeManager

    var icon: String? = nil
    var alignment: VerticalAlignment = .center
    var isEditable: Bool = true
    var isFocused: Bool = false
    @ViewBuilder var content: () -> Content

    @ScaledMetric(relativeTo: .body) private var iconWell: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var minRowHeight: CGFloat = 52

    var body: some View {
        let theme = themeManager.currentTheme

        return HStack(alignment: alignment, spacing: AppSpacing.sm + 4) {
            if let icon {
                Image(systemName: icon)
                    .font(AppTypography.mono(.callout, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: iconWell)
                    .accessibilityHidden(true)
            }

            content()
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm + 4)
        .frame(minHeight: minRowHeight)
        .formWell(theme: theme, isEditable: isEditable, isFocused: isFocused)
    }
}

// MARK: - Form Field
/// Label + recessed input. The one text-entry primitive; every screen routes
/// through it so field height, radius, glyph well and focus ring are identical.
struct FormField: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    @Binding var text: String
    let placeholder: String
    var isRequired: Bool = false
    var isMultiline: Bool = false
    var icon: String?

    @FocusState private var isFocused: Bool

    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: title, isRequired: isRequired)

            FormFieldRow(
                icon: icon,
                alignment: isMultiline ? .top : .center,
                isFocused: isFocused
            ) {
                field
                    .foregroundStyle(theme.colors.text)
                    .tint(theme.colors.primary)
                    .focused($isFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        if isMultiline {
            TextField(placeholder, text: $text, axis: .vertical)
                .appFont(.body, lineLimit: .unlimited)
                .lineLimit(3...6)
        } else {
            TextField(placeholder, text: $text)
                .appFont(.body, lineLimit: .exactly(1))
        }
    }
}

// MARK: - Read-only Value Row
/// A value the user can see but not change. Fills with `background` rather than
/// `surface` so it visibly recedes to the page instead of pretending to be a slot.
struct FormReadOnlyRow: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    let value: String
    var icon: String? = nil

    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: title)

            FormFieldRow(icon: icon, isEditable: false) {
                Text(value)
                    .appFont(.body, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Hint / Error
/// Inline guidance under a field. Never a filled block — a 10%-tint error banner
/// reads as warm mud on the dark palette and as a sticky note on the light one.
struct FormHint: View {
    @EnvironmentObject var themeManager: ThemeManager

    let text: String
    var isCritical: Bool = false

    var body: some View {
        let theme = themeManager.currentTheme
        let ink = isCritical ? theme.colors.error : theme.colors.textSecondary

        return HStack(alignment: .top, spacing: AppSpacing.sm) {
            Image(systemName: isCritical ? "exclamationmark.triangle.fill" : "info.circle")
                .foregroundStyle(ink)
                .accessibilityHidden(true)

            Text(text)
                .foregroundStyle(ink)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .appFont(.bodySmall, lineLimit: .unlimited)
        .accessibilityElement(children: .combine)
    }
}

/// The failure message a submit can produce. Same treatment as `FormHint`, named
/// separately because it carries an assertive accessibility announcement.
struct FormErrorBanner: View {
    let message: String

    var body: some View {
        FormHint(text: message, isCritical: true)
            .accessibilityAddTraits(.isStaticText)
    }
}

// MARK: - Buttons
/// The single loud action on a form. `.glassProminent` + `.tint(primary)` rather
/// than white-on-`primary`: `primary` is a DARK ink in the light theme and a LIGHT
/// ink in the dark theme, so a hand-set white label measures 5.83:1 in light and
/// 2.62:1 in dark. Letting the button style pick its own label colour is the only
/// way one call site reads correctly in both.
struct FormPrimaryButton: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    var systemImage: String? = nil
    var busyTitle: String? = nil
    var isBusy: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            action()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                    Text(busyTitle ?? title)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                }
            }
            .appFont(.bodyBold, lineLimit: .exactly(1))
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm + 2)
        }
        .buttonStyle(.glassProminent)
        .buttonBorderShape(.capsule)
        .tint(themeManager.currentTheme.colors.primary)
        // Disabled state comes from the button style, not a grey fill. `Color.gray`
        // is unmanaged and reads as a live control on the dark palette.
        .disabled(!isEnabled || isBusy)
    }
}

/// The reversible action beside it. Glass, never a second filled button.
struct FormSecondaryButton: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    var systemImage: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        let theme = themeManager.currentTheme
        let ink = role == .destructive ? theme.colors.error : theme.colors.text

        return Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            action()
        } label: {
            HStack(spacing: AppSpacing.sm) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
            }
            .appFont(.bodyBold, lineLimit: .exactly(1))
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm + 2)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.capsule)
        .tint(ink)
    }
}

// MARK: - Destination Search Results
struct DestinationSearchResultsView: View {
    @EnvironmentObject var themeManager: ThemeManager

    let searchResults: [MKLocalSearchCompletion]
    let isSearching: Bool
    let onSelect: (MKLocalSearchCompletion) -> Void

    var body: some View {
        let theme = themeManager.currentTheme

        return VStack(spacing: 0) {
            if isSearching {
                HStack(spacing: AppSpacing.sm + 2) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(theme.colors.primary)

                    Text("Searching destinations…")
                        .appFont(.bodySmall, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.textSecondary)

                    Spacer(minLength: 0)
                }
                .padding(AppSpacing.md)
            } else {
                ForEach(Array(searchResults.enumerated()), id: \.element.title) { index, result in
                    Button {
                        onSelect(result)
                    } label: {
                        DestinationResultRow(title: result.title, subtitle: result.subtitle)
                    }
                    .buttonStyle(.plain)

                    if index < searchResults.count - 1 {
                        Rectangle()
                            .fill(theme.colors.border)
                            .frame(height: 1)
                            .padding(.leading, AppSpacing.md)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
        .formFloatingPanel(theme: theme)
        .accessibilityElement(children: .contain)
    }
}

/// One row of the destination dropdown. Two type tokens, not four.
struct DestinationResultRow: View {
    @EnvironmentObject var themeManager: ThemeManager

    let title: String
    let subtitle: String

    var body: some View {
        let theme = themeManager.currentTheme

        return HStack(spacing: AppSpacing.sm + 4) {
            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(title)
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .appFont(.placeMeta, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "arrow.up.left")
                .font(AppTypography.mono(.caption, weight: .semibold))
                .foregroundStyle(theme.colors.primary)
                .accessibilityHidden(true)
        }
        .padding(AppSpacing.md)
        .contentShape(Rectangle())
    }
}


#Preview {
    AddTripView()
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}
