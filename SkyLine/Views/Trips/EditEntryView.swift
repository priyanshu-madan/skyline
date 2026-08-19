//
//  EditEntryView.swift
//  SkyLine
//
//  View for editing existing trip entries.
//  Same primitives as AddEntryView, so an edited entry and a new one are the
//  same form wearing a different title.
//

import SwiftUI
import CoreLocation

struct EditEntryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @EnvironmentObject var tripStore: TripStore
    @Environment(\.dismiss) private var dismiss

    let entry: TripEntry

    @State private var selectedEntryType: TripEntryType
    @State private var title: String
    @State private var content: String
    @State private var timestamp: Date
    @State private var useCurrentLocation: Bool
    @State private var currentLocation: CLLocation?
    @State private var locationName: String

    @State private var isUpdating = false
    @State private var error: String?
    @State private var showingLocationPicker = false
    @State private var showingDeleteConfirmation = false

    @StateObject private var locationManager = SkyLineLocationManager()

    init(entry: TripEntry) {
        self.entry = entry
        self._selectedEntryType = State(initialValue: entry.entryType)
        self._title = State(initialValue: entry.title)
        self._content = State(initialValue: entry.content)
        self._timestamp = State(initialValue: entry.timestamp)
        self._useCurrentLocation = State(initialValue: entry.hasLocation)
        self._locationName = State(initialValue: entry.locationName ?? "")

        if let lat = entry.latitude, let lng = entry.longitude {
            self._currentLocation = State(initialValue: CLLocation(latitude: lat, longitude: lng))
        }
    }

    private var isValidEntry: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let theme = themeManager.currentTheme

        return ZStack {
            // This screen previously set no background at all, so it inherited the
            // system one — which resolves against the DEVICE appearance, not the
            // app theme. That is the whole light/dark bug in one line.
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                FormScreenHeader(title: "Edit Entry") { dismiss() }

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        entryTypeSection
                        detailsSection
                        timestampSection
                        locationSection

                        if let error = error {
                            FormErrorBanner(message: error)
                        }

                        actionButtons
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.xxl)
                }
                .scrollDismissesKeyboard(.interactively)
                .skylineScrollEdges()
            }
        }
        .environment(\.colorScheme, theme.colorScheme)
        .onAppear {
            requestLocationIfNeeded()
        }
        .confirmationDialog("Delete Entry", isPresented: $showingDeleteConfirmation) {
            Button("Delete Entry", role: .destructive) {
                deleteEntry()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this entry? This action cannot be undone.")
        }
    }

    // MARK: - Entry Type Picker

    private var entryTypeSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Type")

            // One GlassEffectContainer so the selected cell's material merges with
            // its neighbours instead of nine blurs stacking.
            SkyLineGlassPanel(spacing: AppSpacing.sm) {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 3),
                    spacing: AppSpacing.sm
                ) {
                    ForEach(TripEntryType.allCases, id: \.self) { type in
                        entryTypeCard(for: type)
                    }
                }
            }
        }
    }

    private func entryTypeCard(for type: TripEntryType) -> some View {
        let theme = themeManager.currentTheme
        let isSelected = selectedEntryType == type
        let shape = RoundedRectangle(cornerRadius: AppRadius.lg, style: .continuous)

        return Button {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            withAnimation(.easeInOut(duration: 0.22)) {
                selectedEntryType = type
            }
        } label: {
            VStack(spacing: AppSpacing.sm) {
                Text(type.emoji)
                    .appFont(.headline, lineLimit: .exactly(1))

                Text(type.displayName)
                    .appFont(.verdictLabel, lineLimit: .exactly(2))
                    .foregroundStyle(isSelected ? theme.colors.primary : theme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, AppSpacing.sm + 4)
            .padding(.horizontal, AppSpacing.xs)
            .frame(maxWidth: .infinity)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        // Selected: glass tinted with `primary` plus a ring. Unselected: the same
        // recessed well every field uses. Two non-colour signals (the material and
        // the ring) carry the state, so it survives greyscale.
        .modifier(EntryTypeCardSurface(isSelected: isSelected, theme: theme, shape: shape))
        .animation(.easeInOut(duration: 0.22), value: isSelected)
        .accessibilityLabel(Text(type.displayName))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: - Entry Details Form

    private var detailsSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Details")

            FormField(
                title: "Title",
                text: $title,
                placeholder: "What happened?",
                isRequired: true,
                icon: "pencil"
            )

            FormField(
                title: "Description",
                text: $content,
                placeholder: "Tell the story…",
                isMultiline: true,
                icon: "note.text"
            )
        }
    }

    // MARK: - Timestamp Section

    private var timestampSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "When")

            FormFieldRow(icon: "clock") {
                DatePicker(
                    "Date and time",
                    selection: $timestamp,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .tint(themeManager.currentTheme.colors.primary)
                .accessibilityLabel(Text("Date and time"))

                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Location Section

    private var locationSection: some View {
        let theme = themeManager.currentTheme

        return VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Where")

            FormFieldRow(icon: "location") {
                Toggle(isOn: $useCurrentLocation) {
                    Text("Use current location")
                        .appFont(.body, lineLimit: .exactly(1))
                        .foregroundStyle(theme.colors.text)
                }
                .tint(theme.colors.primary)
            }

            if !useCurrentLocation {
                FormField(
                    title: "Place name",
                    text: $locationName,
                    placeholder: "Where were you?",
                    icon: "mappin"
                )
            }
        }
        .onChange(of: useCurrentLocation) { _, newValue in
            if newValue {
                requestLocationIfNeeded()
            }
        }
    }

    // MARK: - Action Buttons

    private var actionButtons: some View {
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            VStack(spacing: AppSpacing.sm) {
                FormPrimaryButton(
                    title: "Update Entry",
                    systemImage: "checkmark",
                    busyTitle: "Updating…",
                    isBusy: isUpdating,
                    isEnabled: isValidEntry
                ) {
                    updateEntry()
                }

                FormSecondaryButton(title: "Cancel") {
                    dismiss()
                }

                // Destructive, and therefore never a filled block: `error` ink on a
                // glass capsule, sitting apart from the two constructive actions.
                FormSecondaryButton(
                    title: "Delete Entry",
                    systemImage: "trash",
                    role: .destructive
                ) {
                    showingDeleteConfirmation = true
                }
                .padding(.top, AppSpacing.sm)
            }
        }
        .padding(.top, AppSpacing.xs)
    }

    // MARK: - Helper Functions

    private func requestLocationIfNeeded() {
        if useCurrentLocation {
            locationManager.requestLocation()
            currentLocation = locationManager.currentLocation
        }
    }


    private func updateEntry() {
        isUpdating = true
        error = nil

        let updatedEntry = TripEntry(
            id: entry.id,
            tripId: entry.tripId,
            timestamp: timestamp,
            entryType: selectedEntryType,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content.trimmingCharacters(in: .whitespacesAndNewlines),
            imageURLs: entry.imageURLs, // Keep existing images for now
            latitude: useCurrentLocation ? currentLocation?.coordinate.latitude : nil,
            longitude: useCurrentLocation ? currentLocation?.coordinate.longitude : nil,
            locationName: useCurrentLocation ? (currentLocation != nil ? "Current Location" : nil) : (locationName.isEmpty ? nil : locationName),
            flightId: entry.flightId,
            isPreview: entry.isPreview,
            createdAt: entry.createdAt,
            updatedAt: Date()
        )

        Task {
            let result = await tripStore.updateEntry(updatedEntry)

            await MainActor.run {
                isUpdating = false

                switch result {
                case .success:
                    dismiss()
                case .failure(let tripError):
                    error = tripError.localizedDescription
                }
            }
        }
    }

    private func deleteEntry() {
        Task {
            let result = await tripStore.deleteEntry(entry.id, tripId: entry.tripId)

            await MainActor.run {
                switch result {
                case .success:
                    dismiss()
                case .failure(let error):
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

// MARK: - Entry Type Card Surface
/// Glass when selected, recessed well when not. Split into a modifier so the
/// branch does not sit inside the button's view builder, where it would force the
/// type checker to unify two different opaque result types on every rebuild.
private struct EntryTypeCardSurface: ViewModifier {
    let isSelected: Bool
    let theme: AppTheme
    let shape: RoundedRectangle

    func body(content: Content) -> some View {
        if isSelected {
            content
                .skylineGlass(
                    .control,
                    in: shape,
                    tint: theme.colors.primary.opacity(0.45),
                    interactive: true,
                    theme: theme
                )
                .overlay(shape.stroke(theme.colors.primary, lineWidth: 1.5))
        } else {
            content
                .background(shape.fill(theme.colors.surface))
                .overlay(shape.stroke(theme.colors.border, lineWidth: 1))
        }
    }
}

#Preview {
    EditEntryView(entry: TripEntry.sample)
        .environmentObject(ThemeManager())
        .environmentObject(TripStore.shared)
}
