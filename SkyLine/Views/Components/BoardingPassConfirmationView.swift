//
//  BoardingPassConfirmationView.swift
//  SkyLine
//
//  Review-and-correct sheet for a scanned boarding pass.
//
//  ── Why this screen rendered a DARK CARD inside a LIGHT APP ────────────────
//
//  Every surface in the previous version was a dynamic UIKit colour: the page
//  was `Color(UIColor.systemGroupedBackground)`, the cards `Color(.systemBackground)`,
//  the fields `Color(.systemGray6)`, the ink `.primary` / `.secondary`, the
//  accents `Color(.systemBlue)`, the hairlines `Color(.separator)`. Those all
//  resolve against `UITraitCollection.userInterfaceStyle` — the DEVICE
//  appearance — and never against `themeManager.currentTheme`. On a
//  dark-appearance phone running the app's Light theme every one of them came
//  back dark while the rest of the app came back light. Roughly sixty-five
//  colours, one bug.
//
//  This file now names no system colour at all. Every fill, ink, stroke and
//  accent comes from `themeManager.currentTheme.colors`, and the screen root
//  writes the app theme into the environment with
//  `.environment(\.colorScheme, theme.colorScheme)` so the system-drawn parts we
//  do not paint ourselves — the compact DatePickers, the text carets, the
//  keyboard, the validation alert — follow the app rather than the device.
//  `.preferredColorScheme` is not enough here: this view lives inside a sheet
//  presented from the globe sheet, and a preference does not reliably reach that
//  far. `.environment` is a value, so it does.
//
//  ── Surface model (shared with the rest of the app's forms) ────────────────
//
//  A card is LIFTED, a field is RECESSED. Fields are therefore `FormFieldRow`
//  wells — `surface` fill, one `border` hairline, no shadow — reusing the same
//  primitives as AddTripView / AddEntryView / EditEntryView so this screen is
//  not a second form vocabulary. An empty date or time slot fills with
//  `background` behind a dashed `primary` outline, so "nothing was scanned here,
//  tap to add" is a visible state rather than an absence.
//
//  Errors never rely on colour alone: a failing field gets an `error` ring, an
//  `exclamationmark.triangle.fill` glyph and a sentence, which is three signals.
//
//  ── Type ──────────────────────────────────────────────────────────────────
//
//  `.appFont(_:)` throughout. The old file hard-coded 9pt–20pt system sizes,
//  which froze the screen out of Dynamic Type and is why airport codes and
//  labels truncated. `AppTextStyle` carries the line budget, the minimum scale
//  factor and the Dynamic Type ceiling with it.
//
//  Behaviour is unchanged: same bindings, same validation, same
//  ConfigurationService strings, same pickers, same callbacks, same logging.
//

import SwiftUI

struct BoardingPassConfirmationView: View {
    let boardingPassData: BoardingPassData
    let onConfirm: (BoardingPassData) -> Void
    let onCancel: () -> Void

    /// True when this screen was handed a pass with nothing in it at all, which
    /// is how manual entry arrives: the same form, presented empty.
    ///
    /// Derived from the DATA rather than passed in as a flag, because the caller
    /// that presents this sheet presents it for both cases from one place. It
    /// changes copy only — the fields, the validation and the save path are
    /// identical, and that identity is the point of doing manual entry this way
    /// rather than building a second form.
    private let isManualEntry: Bool

    @EnvironmentObject private var themeManager: ThemeManager
    @StateObject private var configService = ConfigurationService.shared

    @State private var editedData: BoardingPassData
    @State private var showingValidationErrors = false

    /// Which of the two city fields the SCREEN filled in, rather than the scan
    /// or the user.
    ///
    /// The lookup behind a code may only replace a city it put there itself. It
    /// must not overwrite a city that came off a boarding pass or that the user
    /// typed, and it must be free to correct itself when the code changes —
    /// typing PHL and then fixing it to JFK used to leave "Philadelphia" sitting
    /// under JFK forever, because the rule was "fill only when empty".
    @State private var departureCityIsDerived = false
    @State private var arrivalCityIsDerived = false

    /// Set for the length of the save. The airline and city lookups behind
    /// `enriched` can reach the network, so there is a real gap between the tap
    /// and the sheet leaving — long enough to tap Save twice and store the
    /// flight twice.
    @State private var isSaving = false
    @State private var departureTime = Date()
    @State private var arrivalTime = Date()
    @State private var departureDate = Date()
    @State private var arrivalDate = Date()

    // Track whether data was actually extracted from boarding pass
    @State private var hasDepartureDate: Bool
    @State private var hasArrivalDate: Bool
    @State private var hasDepartureTime: Bool
    @State private var hasArrivalTime: Bool

    // Validation states for real-time feedback
    @State private var flightNumberError: String?
    @State private var departureCodeError: String?
    @State private var arrivalCodeError: String?
    @State private var confirmationCodeError: String?
    @State private var dateTimeError: String?
    @State private var seatError: String?
    @State private var gateError: String?
    @State private var terminalError: String?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Focus is tracked only so a well can show which slot the caret is in.
    /// On a data-correction screen that is the difference between "I am editing
    /// the arrival code" and "I am editing something".
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField: Hashable {
        case flightNumber
        case confirmationCode
        case airline
        case departureCode
        case departureCity
        case arrivalCode
        case arrivalCity
        case terminal
        case gate
        case seat
        case passengerName
    }

    // Metrics scale with the body text so glyph wells and row heights grow in
    // step with the type beside them.
    @ScaledMetric(relativeTo: .body) private var arrowWell: CGFloat = 30
    @ScaledMetric(relativeTo: .body) private var heroBadge: CGFloat = 42
    @ScaledMetric(relativeTo: .body) private var fieldRowHeight: CGFloat = 52
    @ScaledMetric(relativeTo: .body) private var iconWell: CGFloat = 22
    @ScaledMetric(relativeTo: .body) private var bottomBarClearance: CGFloat = 172

    private let wellShape = RoundedRectangle(cornerRadius: AppRadius.xl, style: .continuous)

    init(boardingPassData: BoardingPassData, onConfirm: @escaping (BoardingPassData) -> Void, onCancel: @escaping () -> Void) {
        self.boardingPassData = boardingPassData
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self.isManualEntry = Self.carriesNothing(boardingPassData)
        self._editedData = State(initialValue: Self.normalizedCodes(in: boardingPassData))

        // Initialize time picker values from boarding pass data
        let parsedDepartureTime = Self.parseTimeString(boardingPassData.departureTime)
        let parsedArrivalTime = Self.parseTimeString(boardingPassData.arrivalTime)

        // Use actual boarding pass data if available, otherwise use current date as placeholder for date pickers
        let currentDate = Date()
        let flightDate = boardingPassData.departureDate ?? currentDate
        let arrivalFlightDate = boardingPassData.arrivalDate ?? currentDate

        // For time pickers, combine extracted times with dates, or use current time as placeholder
        let departureDateTime = parsedDepartureTime != nil ?
            Self.combineDateAndTime(date: flightDate, time: parsedDepartureTime!) : currentDate
        let arrivalDateTime = parsedArrivalTime != nil ?
            Self.combineDateAndTime(date: arrivalFlightDate, time: parsedArrivalTime!) : currentDate

        self._departureTime = State(initialValue: departureDateTime)
        self._arrivalTime = State(initialValue: arrivalDateTime)
        self._departureDate = State(initialValue: flightDate)
        self._arrivalDate = State(initialValue: arrivalFlightDate)

        // Track what data was actually extracted
        self._hasDepartureDate = State(initialValue: boardingPassData.departureDate != nil)
        self._hasArrivalDate = State(initialValue: boardingPassData.arrivalDate != nil)
        self._hasDepartureTime = State(initialValue: parsedDepartureTime != nil)
        self._hasArrivalTime = State(initialValue: parsedArrivalTime != nil)
    }

    var body: some View {
        let theme = themeManager.currentTheme

        return ZStack(alignment: .bottom) {
            // The page. Previously `Color(UIColor.systemGroupedBackground)`,
            // which is exactly the colour that disagreed with the app's theme.
            theme.colors.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header(theme: theme)

                ScrollView {
                    VStack(alignment: .leading, spacing: AppSpacing.lg) {
                        heroSection(theme: theme)
                        routeSection(theme: theme)
                        departureSection(theme: theme)
                        arrivalSection(theme: theme)

                        // Cross-field failure ("arrival before departure"), so it
                        // belongs to both legs rather than to either one.
                        if let dateTimeError = dateTimeError {
                            FormHint(text: dateTimeError, isCritical: true)
                        }

                        flightInformationSection(theme: theme)
                        additionalDetailsSection(theme: theme)
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                    .padding(.bottom, bottomBarClearance)
                }
                .scrollDismissesKeyboard(.interactively)
                .skylineScrollEdges()
            }

            stickyBottomBar(theme: theme)
        }
        // Pins the compact DatePickers, the caret, the keyboard and the alert to
        // the app theme instead of the device appearance.
        .environment(\.colorScheme, theme.colorScheme)
        .alert("Validation Error", isPresented: $showingValidationErrors) {
            Button("OK") { }
        } message: {
            Text(getValidationErrorMessage())
        }
        .onAppear {
            print("📋 BoardingPassConfirmationView appeared — mode=\(isManualEntry ? "manual" : "scanned") flight: \(boardingPassData.flightNumber ?? "nil")")
        }
    }

    // MARK: - Header

    /// Cancel, title, reset. Both controls are `SkyLineGlassIconButton`, so the
    /// 44pt hit target, the symbol weight and the Reduce Transparency fallback
    /// are the same object the globe overlay and every form header use — and no
    /// call site in this file touches `.glassEffect` directly.
    private func header(theme: AppTheme) -> some View {
        SkyLineGlassPanel(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                SkyLineGlassIconButton(
                    systemImage: "xmark",
                    accessibilityLabel: "Cancel"
                ) {
                    onCancel()
                }

                Spacer(minLength: AppSpacing.sm)

                // There is nothing to confirm on a form the user is filling in
                // themselves. Same screen, same controls; the title says which
                // job it is doing.
                Text(isManualEntry ? "Add Flight" : "Confirm Flight Details")
                    .appFont(.headline, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: AppSpacing.sm)

                SkyLineGlassIconButton(
                    systemImage: "arrow.counterclockwise",
                    accessibilityLabel: isManualEntry ? "Clear all fields" : "Reset to scanned values"
                ) {
                    resetToOriginal()
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.top, AppSpacing.sm)
            .padding(.bottom, AppSpacing.md)
        }
    }

    // MARK: - Hero

    /// A confirmation banner, not a hero image: it says the scan worked and that
    /// the values below are editable. `success` rather than the old
    /// `Color(.systemBlue)` so it does not compete with the `primary` save CTA,
    /// and it clears AA in both palettes (5.1:1 light, well clear in dark).
    ///
    /// Manual entry has no scan to report, so the same banner carries the one
    /// thing the user actually needs to know before typing: which three fields
    /// are required. Its badge is a RECESSED well — `background` fill inside the
    /// lifted card, neutral ink — the same "nothing here yet" vocabulary as the
    /// empty date slots below, rather than a success seal for something that has
    /// not happened.
    private func heroSection(theme: AppTheme) -> some View {
        HStack(spacing: AppSpacing.md) {
            Image(systemName: isManualEntry ? "square.and.pencil" : "checkmark.seal.fill")
                .font(AppTypography.mono(.title3, weight: .semibold))
                .foregroundStyle(isManualEntry ? theme.colors.textSecondary : theme.colors.success)
                .frame(width: heroBadge, height: heroBadge)
                .background(
                    Circle().fill(
                        isManualEntry
                            ? theme.colors.background
                            : theme.colors.success.opacity(theme == .light ? 0.12 : 0.18)
                    )
                )
                .overlay(
                    Circle().stroke(
                        isManualEntry ? theme.colors.border : theme.colors.success.opacity(0.45),
                        lineWidth: 1
                    )
                )
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: AppSpacing.xs) {
                Text(isManualEntry ? "Enter Flight Details" : "Boarding Pass Scanned")
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)

                Text(isManualEntry
                     ? "Flight number and both airports are required."
                     : "Review and edit if needed")
                    .appFont(.bodySmall, lineLimit: .unlimited)
                    .foregroundStyle(theme.colors.textSecondary)
            }

            Spacer(minLength: 0)
        }
        .padding(AppSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(wellShape.fill(theme.colors.surface))
        .overlay(wellShape.stroke(theme.colors.border, lineWidth: 1))
        .containerShape(wellShape)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Route

    /// Codes side by side with the arrow between them, because that pair *is*
    /// the flight. Labels and wells live in two parallel HStacks sharing one
    /// fixed-width middle column, so the label above a well is always exactly as
    /// wide as the well — no alignment guides, nothing to drift under Dynamic
    /// Type.
    private func routeSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormSectionHeader(title: "Route")
                .padding(.bottom, AppSpacing.xs)

            HStack(spacing: AppSpacing.sm) {
                FormFieldLabel(title: "From", isRequired: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: arrowWell, height: 1)
                    .accessibilityHidden(true)

                FormFieldLabel(title: "To", isRequired: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: AppSpacing.sm) {
                airportCodeWell(
                    theme: theme,
                    placeholder: configService.getPlaceholder(for: .departureAirport),
                    accessibilityLabel: "Departure airport code",
                    focus: .departureCode,
                    hasError: departureCodeError != nil,
                    text: departureCodeBinding
                )

                routeArrow(theme: theme)

                airportCodeWell(
                    theme: theme,
                    placeholder: configService.getPlaceholder(for: .arrivalAirport),
                    accessibilityLabel: "Arrival airport code",
                    focus: .arrivalCode,
                    hasError: arrivalCodeError != nil,
                    text: arrivalCodeBinding
                )
            }

            HStack(spacing: AppSpacing.sm) {
                FormFieldLabel(title: "Departure city")
                    .frame(maxWidth: .infinity, alignment: .leading)

                Color.clear
                    .frame(width: arrowWell, height: 1)
                    .accessibilityHidden(true)

                FormFieldLabel(title: "Arrival city")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, AppSpacing.xs)

            HStack(spacing: AppSpacing.sm) {
                cityWell(
                    theme: theme,
                    placeholder: configService.getPlaceholder(for: .departureCity),
                    accessibilityLabel: "Departure city",
                    focus: .departureCity,
                    text: Binding(
                        get: { editedData.departureCity ?? "" },
                        set: {
                            editedData.departureCity = $0.isEmpty ? nil : $0
                            // Typed by hand: the code lookup no longer owns it.
                            departureCityIsDerived = false
                        }
                    )
                )

                Color.clear
                    .frame(width: arrowWell, height: 1)
                    .accessibilityHidden(true)

                cityWell(
                    theme: theme,
                    placeholder: configService.getPlaceholder(for: .arrivalCity),
                    accessibilityLabel: "Arrival city",
                    focus: .arrivalCity,
                    text: Binding(
                        get: { editedData.arrivalCity ?? "" },
                        set: {
                            editedData.arrivalCity = $0.isEmpty ? nil : $0
                            arrivalCityIsDerived = false
                        }
                    )
                )
            }

            // Named rather than tucked under a column: at this width a hint under
            // the right-hand well is ambiguous about which airport it means.
            if let departureCodeError = departureCodeError {
                FormHint(text: "Departure airport: \(departureCodeError)", isCritical: true)
            }
            if let arrivalCodeError = arrivalCodeError {
                FormHint(text: "Arrival airport: \(arrivalCodeError)", isCritical: true)
            }
        }
    }

    private func routeArrow(theme: AppTheme) -> some View {
        Image(systemName: "arrow.right")
            .font(AppTypography.mono(.footnote, weight: .semibold))
            .foregroundStyle(theme.colors.textSecondary)
            .frame(width: arrowWell, height: arrowWell)
            .background(Circle().fill(theme.colors.surface))
            .overlay(Circle().stroke(theme.colors.border, lineWidth: 1))
            .accessibilityHidden(true)
    }

    private func airportCodeWell(
        theme: AppTheme,
        placeholder: String,
        accessibilityLabel: String,
        focus: FocusedField,
        hasError: Bool,
        text: Binding<String>
    ) -> some View {
        FormFieldRow(isFocused: focusedField == focus) {
            TextField(placeholder, text: text)
                .appFont(.airportCode, lineLimit: .exactly(1))
                .foregroundStyle(theme.colors.text)
                .tint(theme.colors.primary)
                .multilineTextAlignment(.center)
                // The setter already uppercases, so the keyboard is told to agree
                // rather than fight it with autocorrect.
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($focusedField, equals: focus)
                .frame(maxWidth: .infinity)
                .accessibilityLabel(Text(accessibilityLabel))
        }
        .frame(maxWidth: .infinity)
        .overlay(errorRing(hasError, theme: theme))
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: hasError)
    }

    private func cityWell(
        theme: AppTheme,
        placeholder: String,
        accessibilityLabel: String,
        focus: FocusedField,
        text: Binding<String>
    ) -> some View {
        FormFieldRow(isFocused: focusedField == focus) {
            TextField(placeholder, text: text)
                .appFont(.bodySmall, lineLimit: .exactly(1))
                // An editable value is `text` ink. The old file drew these in
                // `.secondary`, which made a field the user can type into look
                // like a caption.
                .foregroundStyle(theme.colors.text)
                .tint(theme.colors.primary)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: focus)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(Text(accessibilityLabel))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Departure / Arrival

    private func departureSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Departure")

            dateTimeField(
                theme: theme,
                label: "Date",
                icon: "calendar",
                accessibilityLabel: "Departure date",
                isSet: hasDepartureDate,
                selection: $departureDate,
                components: .date,
                onAdd: {
                    hasDepartureDate = true
                    editedData.departureDate = departureDate
                    print("➕ Added departure date: \(departureDate.formatted())")
                },
                onChange: { newDate in
                    editedData.departureDate = newDate
                    print("🔄 Updated departure date: \(newDate.formatted())")
                    // Trigger date/time validation
                    if let error = validateDateTimeLogic() {
                        dateTimeError = error
                    } else {
                        dateTimeError = nil
                    }
                }
            )

            dateTimeField(
                theme: theme,
                label: "Time",
                icon: "clock",
                accessibilityLabel: "Departure time",
                isSet: hasDepartureTime,
                selection: $departureTime,
                components: .hourAndMinute,
                onAdd: {
                    hasDepartureTime = true
                    editedData.departureTime = formatTimeForBoardingPass(departureTime)
                },
                onChange: { newTime in
                    editedData.departureTime = formatTimeForBoardingPass(newTime)
                    // Trigger date/time validation
                    if let error = validateDateTimeLogic() {
                        dateTimeError = error
                    } else {
                        dateTimeError = nil
                    }
                }
            )
        }
    }

    private func arrivalSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Arrival")

            dateTimeField(
                theme: theme,
                label: "Date",
                icon: "calendar",
                accessibilityLabel: "Arrival date",
                isSet: hasArrivalDate,
                selection: $arrivalDate,
                components: .date,
                onAdd: {
                    hasArrivalDate = true
                    editedData.arrivalDate = arrivalDate
                    print("➕ Added arrival date: \(arrivalDate.formatted())")
                },
                onChange: { newDate in
                    editedData.arrivalDate = newDate
                    print("🔄 Updated arrival date: \(newDate.formatted())")
                    // Trigger date/time validation
                    if let error = validateDateTimeLogic() {
                        dateTimeError = error
                    } else {
                        dateTimeError = nil
                    }
                }
            )

            dateTimeField(
                theme: theme,
                label: "Time",
                icon: "clock",
                accessibilityLabel: "Arrival time",
                isSet: hasArrivalTime,
                selection: $arrivalTime,
                components: .hourAndMinute,
                onAdd: {
                    hasArrivalTime = true
                    editedData.arrivalTime = formatTimeForBoardingPass(arrivalTime)
                },
                onChange: { newTime in
                    editedData.arrivalTime = formatTimeForBoardingPass(newTime)
                    // Trigger date/time validation
                    if let error = validateDateTimeLogic() {
                        dateTimeError = error
                    } else {
                        dateTimeError = nil
                    }
                }
            )
        }
    }

    /// One date-or-time slot, in its two states. Full width rather than the old
    /// two-up grid: a `.compact` DatePicker cannot shrink, so at half width it
    /// clipped its own value — the exact truncation this repaint is meant to end.
    @ViewBuilder
    private func dateTimeField(
        theme: AppTheme,
        label: String,
        icon: String,
        accessibilityLabel: String,
        isSet: Bool,
        selection: Binding<Date>,
        components: DatePickerComponents,
        onAdd: @escaping () -> Void,
        onChange: @escaping (Date) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: label)

            if isSet {
                FormFieldRow(icon: icon) {
                    DatePicker("", selection: selection, displayedComponents: components)
                        .datePickerStyle(.compact)
                        .labelsHidden()
                        .tint(theme.colors.primary)
                        .accessibilityLabel(Text(accessibilityLabel))
                        .onChange(of: selection.wrappedValue) { _, newValue in
                            onChange(newValue)
                        }

                    Spacer(minLength: 0)
                }
            } else {
                emptySlotButton(
                    theme: theme,
                    icon: icon,
                    accessibilityLabel: accessibilityLabel,
                    action: onAdd
                )
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSet)
    }

    /// Nothing was scanned for this slot. Fills with `background` rather than
    /// `surface` so it visibly recedes to the page — it is not a slot yet — and
    /// wears a dashed `primary` outline so "tap to add" is an affordance rather
    /// than a guess. Full-strength `primary` on purpose: at 55% it blends to
    /// 2.4:1 against the page in the light theme, under the 3:1 floor for a
    /// non-text control.
    private func emptySlotButton(
        theme: AppTheme,
        icon: String,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.sm + 4) {
                Image(systemName: icon)
                    .font(AppTypography.mono(.callout, weight: .medium))
                    .foregroundStyle(theme.colors.textSecondary)
                    .frame(width: iconWell)

                Text("N/A")
                    .appFont(.body, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.textSecondary)

                Spacer(minLength: 0)

                Image(systemName: "plus.circle.fill")
                    .font(AppTypography.mono(.callout, weight: .medium))
                    .foregroundStyle(theme.colors.primary)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm + 4)
            .frame(maxWidth: .infinity)
            .frame(minHeight: fieldRowHeight)
            .background(wellShape.fill(theme.colors.background))
            .overlay(
                wellShape.strokeBorder(
                    theme.colors.primary,
                    style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                )
            )
            .contentShape(wellShape)
        }
        .buttonStyle(.plain)
        .containerShape(wellShape)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityValue(Text("Not set"))
        .accessibilityHint(Text("Adds a value you can edit"))
    }

    // MARK: - Flight Information

    private func flightInformationSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Flight information")

            textFieldBlock(
                theme: theme,
                label: "Flight number",
                isRequired: true,
                icon: "airplane",
                placeholder: configService.getPlaceholder(for: .flightNumber),
                focus: .flightNumber,
                error: flightNumberError,
                uppercases: true,
                text: flightNumberBinding
            )

            textFieldBlock(
                theme: theme,
                label: "Confirmation code",
                icon: "ticket",
                placeholder: configService.getPlaceholder(for: .confirmationCode),
                focus: .confirmationCode,
                error: confirmationCodeError,
                uppercases: true,
                text: confirmationCodeBinding
            )

            textFieldBlock(
                theme: theme,
                label: "Airline",
                icon: "airplane.circle",
                placeholder: configService.getPlaceholder(for: .airline),
                focus: .airline,
                error: nil,
                uppercases: false,
                text: Binding(
                    get: { editedData.airline ?? "" },
                    set: { editedData.airline = $0.isEmpty ? nil : $0 }
                )
            )
        }
    }

    // MARK: - Additional Details

    private func additionalDetailsSection(theme: AppTheme) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            FormSectionHeader(title: "Additional details")

            // Terminal / Gate / Seat were three across at 9pt–17pt fixed sizes,
            // which is roughly 90pt of usable width each. Full-width rows instead:
            // this is the app's form vocabulary everywhere else, and a correction
            // screen has no business truncating the value being corrected.
            textFieldBlock(
                theme: theme,
                label: "Terminal",
                icon: "building.2",
                placeholder: configService.getPlaceholder(for: .terminal),
                focus: .terminal,
                error: terminalError,
                uppercases: true,
                text: Binding(
                    get: { editedData.terminal ?? "" },
                    set: { editedData.terminal = $0.isEmpty ? nil : $0.uppercased() }
                )
            )

            textFieldBlock(
                theme: theme,
                label: "Gate",
                icon: "door.left.hand.open",
                placeholder: configService.getPlaceholder(for: .gate),
                focus: .gate,
                error: gateError,
                uppercases: true,
                text: Binding(
                    get: { editedData.gate ?? "" },
                    set: { editedData.gate = $0.isEmpty ? nil : $0.uppercased() }
                )
            )

            textFieldBlock(
                theme: theme,
                label: "Seat",
                icon: "chair.lounge",
                placeholder: configService.getPlaceholder(for: .seat),
                focus: .seat,
                error: seatError,
                uppercases: true,
                text: seatBinding
            )

            textFieldBlock(
                theme: theme,
                label: "Passenger name",
                icon: "person",
                placeholder: configService.getPlaceholder(for: .passengerName),
                focus: .passengerName,
                error: nil,
                uppercases: true,
                text: Binding(
                    get: { editedData.passengerName ?? "" },
                    set: { editedData.passengerName = $0.isEmpty ? nil : $0.uppercased() }
                )
            )
        }
    }

    /// Label, recessed well, and — when the field is failing — an error ring plus
    /// a sentence. Three signals for one failure, so it survives greyscale and
    /// Differentiate Without Color.
    private func textFieldBlock(
        theme: AppTheme,
        label: String,
        isRequired: Bool = false,
        icon: String,
        placeholder: String,
        focus: FocusedField,
        error: String?,
        uppercases: Bool,
        text: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            FormFieldLabel(title: label, isRequired: isRequired)

            FormFieldRow(icon: icon, isFocused: focusedField == focus) {
                TextField(placeholder, text: text)
                    .appFont(.body, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.text)
                    .tint(theme.colors.primary)
                    .textInputAutocapitalization(uppercases ? .characters : .words)
                    .autocorrectionDisabled(uppercases)
                    .focused($focusedField, equals: focus)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel(Text(label))
            }
            .overlay(errorRing(error != nil, theme: theme))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: error)

            if let error = error {
                FormHint(text: error, isCritical: true)
            }
        }
    }

    /// Drawn over `FormFieldRow`'s own hairline so the well keeps its shape and
    /// only its outline changes. `Color.clear` when there is nothing wrong keeps
    /// the view identity stable across the transition.
    private func errorRing(_ hasError: Bool, theme: AppTheme) -> some View {
        wellShape.strokeBorder(
            hasError ? theme.colors.error : Color.clear,
            lineWidth: hasError ? 1.5 : 0
        )
    }

    // MARK: - Sticky Bottom Bar

    /// Opaque `surface`, deliberately not glass. This bar sits over the fields the
    /// user is correcting; a translucent one would let half-legible values bleed
    /// through the single control that commits them. Being opaque also means it
    /// has nothing to fall back to under Reduce Transparency — the setting cannot
    /// change how it reads.
    private func stickyBottomBar(theme: AppTheme) -> some View {
        VStack(spacing: AppSpacing.sm) {
            saveButton(theme: theme)

            // Glass capsule, and it fires the same light impact the old cancel
            // button did — so `onCancel` is passed straight through rather than
            // wrapped in a second generator.
            FormSecondaryButton(title: configService.getButtonText(for: .cancelButton)) {
                onCancel()
            }
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.md)
        .padding(.bottom, AppSpacing.sm)
        .frame(maxWidth: .infinity)
        .background {
            theme.colors.surface
                // A black-based shadow has nowhere to go on a 0x0A0F1C page, so
                // the dark theme leans on the hairline alone.
                .shadow(
                    color: theme == .light ? theme.colors.scrim : Color.clear,
                    radius: 12,
                    x: 0,
                    y: -3
                )
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(theme.colors.border)
                        .frame(height: 1)
                }
                .ignoresSafeArea(edges: .bottom)
        }
    }

    /// The one loud action. Filled `primary` with `onAccent` ink — the token that
    /// exists precisely because `primary` flips polarity between the themes, so
    /// the old `.foregroundColor(.white)` on `Color(.systemBlue)` measured 5.8:1
    /// in light and 2.62:1 in dark. `onAccent` is white on light and near-black
    /// on dark: 5.8:1 and 7.1:1.
    private func saveButton(theme: AppTheme) -> some View {
        Button {
            print("💾 Confirm: Save tapped — flight='\(editedData.flightNumber ?? "nil")' dep='\(editedData.departureCode ?? "nil")' arr='\(editedData.arrivalCode ?? "nil")' date=\(String(describing: editedData.departureDate))")
            if validateData() {
                print("✅ Confirm: validation passed, saving")
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                save()
            } else {
                print("""
                ❌ Confirm: validation FAILED
                   flightNumber: \(flightNumberError ?? "ok")
                   departureCode: \(departureCodeError ?? "ok")
                   arrivalCode: \(arrivalCodeError ?? "ok")
                   dateTime: \(dateTimeError ?? "ok")
                   seat: \(seatError ?? "ok")  gate: \(gateError ?? "ok")  terminal: \(terminalError ?? "ok")
                """)
                showingValidationErrors = true
            }
        } label: {
            HStack(spacing: AppSpacing.sm) {
                // The spinner is the only thing that changes while saving, and
                // it sits INSIDE the capsule so the bar does not resize under
                // the user's thumb. `onAccent` is the ink on this fill in both
                // palettes, so the spinner uses it too rather than a tint that
                // would vanish on one of them.
                if isSaving {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(theme.colors.onAccent)
                }

                Text(configService.getButtonText(for: .saveFlightButton))
                    .appFont(.bodyBold, lineLimit: .exactly(1))
                    .foregroundStyle(theme.colors.onAccent)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, AppSpacing.sm + 4)
            .background(Capsule(style: .continuous).fill(theme.colors.primary))
            .contentShape(Capsule(style: .continuous))
            .opacity(isSaving ? 0.7 : 1)
        }
        .buttonStyle(.plain)
        .disabled(isSaving)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSaving)
    }

    /// Fills in what the codes already imply, then hands the pass up.
    ///
    /// A SCANNED pass was enriched on the way out of `UnifiedBoardingPassService`,
    /// so United/Philadelphia/Denver were already on it before this screen opened.
    /// A TYPED one has never been near that service: the airline and city lookups
    /// on this screen hang off each field's own `onChange`, which fills a blank
    /// city as you type but is a per-field race and does nothing at all for a
    /// value that arrives any other way. Running `enriched` once at the point of
    /// save is the same lookups from the same place the scanner uses, so a hand
    /// typed UA323 PHL→DEN is stored with exactly what a scanned one would be.
    ///
    /// It only ever FILLS BLANKS, so this is a no-op for a pass that already has
    /// an airline and both cities — including every scan.
    private func save() {
        guard !isSaving else { return }
        isSaving = true

        Task {
            let enriched = await UnifiedBoardingPassService.enriched(editedData)
            print("🧭 Confirm: enriched — airline='\(enriched.airline ?? "nil")' from='\(enriched.departureCity ?? "nil")' to='\(enriched.arrivalCity ?? "nil")' id=\(enriched.id)")
            await MainActor.run {
                isSaving = false
                onConfirm(enriched)
            }
        }
    }

    // MARK: - Bindings
    //
    // Extracted verbatim from the old inline `Binding(get:set:)` closures so the
    // section builders stay readable. Not one rule changed.

    /// The one rule for a machine-readable field, applied to TYPING as well as to
    /// arrival.
    ///
    /// `normalizedCodes(in:)` already squashes and uppercases a pass on the way
    /// in, and its comment says why: `flightNumberPattern` is
    /// `^[A-Z]{2,3}[0-9]{1,4}$`, which has no room for a space. But it ran only
    /// at init, so the rule held for a SCANNED "UA 323" and not for a TYPED one
    /// — a person entering a flight by hand, which is the normal way to write a
    /// flight number, watched "flight number is invalid" appear under a flight
    /// number that is perfectly correct, and the Save button reject it.
    ///
    /// Squashing in the setter means the field shows the canonical value as it is
    /// typed, so what is validated, what is displayed and what is saved are the
    /// same string.
    private static func canonical(_ value: String) -> String? {
        let squashed = value
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .uppercased()
        return squashed.isEmpty ? nil : squashed
    }

    private var flightNumberBinding: Binding<String> {
        Binding(
            get: { editedData.flightNumber ?? "" },
            set: { rawValue in
                let newValue = Self.canonical(rawValue) ?? ""
                editedData.flightNumber = newValue.isEmpty ? nil : newValue
                // Real-time validation
                if !newValue.isEmpty && !isValidFlightNumber(newValue) {
                    flightNumberError = configService.getErrorMessage(for: .flightNumberInvalid)
                } else {
                    flightNumberError = nil
                }

                // Auto-suggest airline based on flight number using AirlineService
                Task {
                    if let airline = await AirlineService.shared.getAirlineFromFlightNumber(newValue) {
                        await MainActor.run {
                            if editedData.airline?.isEmpty != false {
                                editedData.airline = airline
                            }
                        }
                    }
                }
            }
        )
    }

    private var confirmationCodeBinding: Binding<String> {
        Binding(
            get: { editedData.confirmationCode ?? "" },
            set: { rawValue in
                let newValue = Self.canonical(rawValue) ?? ""
                editedData.confirmationCode = newValue.isEmpty ? nil : newValue
                // Real-time validation for optional field
                if !newValue.isEmpty && !isValidConfirmationCode(newValue) {
                    confirmationCodeError = configService.getErrorMessage(for: .confirmationCodeInvalid)
                } else {
                    confirmationCodeError = nil
                }
            }
        )
    }

    private var departureCodeBinding: Binding<String> {
        Binding(
            get: { editedData.departureCode ?? "" },
            set: { rawValue in
                let newValue = Self.canonical(rawValue) ?? ""
                editedData.departureCode = newValue.isEmpty ? nil : newValue
                // Real-time validation
                if !newValue.isEmpty && !isValidAirportCode(newValue) {
                    departureCodeError = configService.getErrorMessage(for: .airportCodeInvalid)
                } else {
                    departureCodeError = nil
                }

                // Auto-suggest the city, but only once the field HOLDS a code.
                //
                // This used to fire on every keystroke, so typing "phl" asked the
                // airport service about "P", then "PH", then "PHL" — three
                // lookups racing, and the first one to answer won because the
                // rule was "fill only when empty". A hand-typed PHL came back as
                // Shanghai (Pudong), observed on device, from the lookup for "P".
                // A partial code is not a code, so it is not asked about.
                Task {
                    guard isValidAirportCode(newValue) else { return }
                    let airportInfo = await AirportService.shared.getAirportInfo(for: newValue)
                    await MainActor.run {
                        guard let city = airportInfo.city,
                              editedData.departureCode == newValue else { return }
                        if editedData.departureCity?.isEmpty != false || departureCityIsDerived {
                            editedData.departureCity = city
                            departureCityIsDerived = true
                        }
                    }
                }
            }
        )
    }

    private var arrivalCodeBinding: Binding<String> {
        Binding(
            get: { editedData.arrivalCode ?? "" },
            set: { rawValue in
                let newValue = Self.canonical(rawValue) ?? ""
                editedData.arrivalCode = newValue.isEmpty ? nil : newValue
                // Real-time validation
                if !newValue.isEmpty {
                    if !isValidAirportCode(newValue) {
                        arrivalCodeError = configService.getErrorMessage(for: .airportCodeInvalid)
                    } else if newValue == editedData.departureCode {
                        arrivalCodeError = configService.getErrorMessage(for: .airportCodeSameAsOther)
                    } else {
                        arrivalCodeError = nil
                    }
                } else {
                    arrivalCodeError = nil
                }

                // Same rule as the departure code above: a whole code, or no
                // lookup at all.
                Task {
                    guard isValidAirportCode(newValue) else { return }
                    let airportInfo = await AirportService.shared.getAirportInfo(for: newValue)
                    await MainActor.run {
                        guard let city = airportInfo.city,
                              editedData.arrivalCode == newValue else { return }
                        if editedData.arrivalCity?.isEmpty != false || arrivalCityIsDerived {
                            editedData.arrivalCity = city
                            arrivalCityIsDerived = true
                        }
                    }
                }
            }
        )
    }

    private var seatBinding: Binding<String> {
        Binding(
            get: { editedData.seat ?? "" },
            set: { rawValue in
                let newValue = Self.canonical(rawValue) ?? ""
                editedData.seat = newValue.isEmpty ? nil : newValue
                // Real-time validation for optional field
                if !newValue.isEmpty && !isValidSeatNumber(newValue) {
                    seatError = configService.getErrorMessage(for: .seatNumberInvalid)
                } else {
                    seatError = nil
                }
            }
        )
    }

    // MARK: - Helper Functions

    /// Puts the machine-readable fields into the form the validators expect.
    ///
    /// A confirmation prints a flight number the way a person reads it - "UA 323"
    /// - but `flightNumberPattern` is `^[A-Z]{2,3}[0-9]{1,4}$`, which has no room
    /// for a space. The scan was reading United 323 PHL->DEN perfectly and then
    /// the Save button sat disabled behind "flight number is invalid", which
    /// reads to the user as the scan having failed.
    ///
    /// Applied on the way IN rather than only inside the validator, so the field
    /// shows the canonical value and whatever is saved matches what was checked.
    static func normalizedCodes(in data: BoardingPassData) -> BoardingPassData {
        // One rule, one implementation: `canonical` is the same squash the
        // field setters apply while the user types.
        func squashed(_ value: String?) -> String? {
            guard let value else { return nil }
            return canonical(value)
        }

        var normalized = data
        normalized.flightNumber = squashed(data.flightNumber)
        normalized.departureCode = squashed(data.departureCode)
        normalized.arrivalCode = squashed(data.arrivalCode)
        normalized.confirmationCode = squashed(data.confirmationCode)
        normalized.seat = squashed(data.seat)
        return normalized
    }

    /// Whether this pass has nothing in it whatsoever.
    ///
    /// `isValid` is not the question — it asks for the three fields needed to
    /// SAVE, and a scan that read a seat and a gate but missed the flight number
    /// is invalid while being very much a scan. This asks whether ANY field
    /// arrived, which is the only thing that distinguishes "the user asked to
    /// type a flight in" from "a scan came back thin".
    static func carriesNothing(_ data: BoardingPassData) -> Bool {
        let text = [
            data.flightNumber, data.airline,
            data.departureCode, data.departureCity,
            data.arrivalCode, data.arrivalCity,
            data.departureTime, data.arrivalTime,
            data.gate, data.terminal, data.seat,
            data.confirmationCode, data.passengerName, data.flightDuration
        ]

        let carriesText = text.contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return !carriesText && data.departureDate == nil && data.arrivalDate == nil
    }

    private func validateData() -> Bool {
        // Clear all errors first
        flightNumberError = nil
        departureCodeError = nil
        arrivalCodeError = nil
        confirmationCodeError = nil
        dateTimeError = nil
        seatError = nil
        gateError = nil
        terminalError = nil

        var isValid = true

        // Validate flight number
        if let flightNumber = editedData.flightNumber, !flightNumber.isEmpty {
            if !isValidFlightNumber(flightNumber) {
                flightNumberError = configService.getErrorMessage(for: .flightNumberInvalid)
                isValid = false
            }
        } else {
            flightNumberError = "Flight number is required"
            isValid = false
        }

        // Validate departure airport code
        if let departureCode = editedData.departureCode, !departureCode.isEmpty {
            if !isValidAirportCode(departureCode) {
                departureCodeError = configService.getErrorMessage(for: .airportCodeInvalid)
                isValid = false
            }
        } else {
            departureCodeError = "Departure airport is required"
            isValid = false
        }

        // Validate arrival airport code
        if let arrivalCode = editedData.arrivalCode, !arrivalCode.isEmpty {
            if !isValidAirportCode(arrivalCode) {
                arrivalCodeError = configService.getErrorMessage(for: .airportCodeInvalid)
                isValid = false
            } else if arrivalCode == editedData.departureCode {
                arrivalCodeError = configService.getErrorMessage(for: .airportCodeSameAsOther)
                isValid = false
            }
        } else {
            arrivalCodeError = "Arrival airport is required"
            isValid = false
        }

        // Validate confirmation code (optional but if present should be valid)
        if let confirmationCode = editedData.confirmationCode, !confirmationCode.isEmpty {
            if !isValidConfirmationCode(confirmationCode) {
                confirmationCodeError = configService.getErrorMessage(for: .confirmationCodeInvalid)
                // Don't mark as invalid since confirmation is optional
            }
        }

        // Validate seat number (optional but if present should be valid)
        if let seat = editedData.seat, !seat.isEmpty {
            if !isValidSeatNumber(seat) {
                seatError = configService.getErrorMessage(for: .seatNumberInvalid)
                // Don't mark as invalid since seat is optional
            }
        }

        // Validate gate (optional but if present should be valid)
        if let gate = editedData.gate, !gate.isEmpty {
            if !isValidGate(gate) {
                gateError = configService.getErrorMessage(for: .gateInvalid)
                // Don't mark as invalid since gate is optional
            }
        }

        // Validate terminal (optional but if present should be valid)
        if let terminal = editedData.terminal, !terminal.isEmpty {
            if !isValidTerminal(terminal) {
                terminalError = configService.getErrorMessage(for: .terminalInvalid)
                // Don't mark as invalid since terminal is optional
            }
        }

        // Validate date/time logic
        if let dateTimeValidationError = validateDateTimeLogic() {
            dateTimeError = dateTimeValidationError
            isValid = false
        }

        return isValid
    }

    private func isValidFlightNumber(_ flightNumber: String) -> Bool {
        let pattern = configService.getValidationPattern(for: .flightNumber)
        return flightNumber.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidAirportCode(_ code: String) -> Bool {
        let pattern = configService.getValidationPattern(for: .airportCode)
        return code.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidConfirmationCode(_ code: String) -> Bool {
        let range = configService.config.validationRules.confirmationCodeLengthRange
        return code.count >= range.min && code.count <= range.max && code.allSatisfy { $0.isLetter || $0.isNumber }
    }

    private func isValidSeatNumber(_ seat: String) -> Bool {
        let pattern = configService.getValidationPattern(for: .seatNumber)
        return seat.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidGate(_ gate: String) -> Bool {
        let pattern = configService.getValidationPattern(for: .gate)
        return gate.range(of: pattern, options: .regularExpression) != nil
    }

    private func isValidTerminal(_ terminal: String) -> Bool {
        let maxLength = configService.config.validationRules.terminalMaxLength
        return terminal.count <= maxLength && !terminal.isEmpty
    }


    private func resetToOriginal() {
        // Reset all data to original boarding pass data
        editedData = Self.normalizedCodes(in: boardingPassData)

        // Clear all errors
        flightNumberError = nil
        departureCodeError = nil
        arrivalCodeError = nil
        confirmationCodeError = nil
        dateTimeError = nil
        seatError = nil
        gateError = nil
        terminalError = nil

        // Reset state tracking
        hasDepartureDate = boardingPassData.departureDate != nil
        hasArrivalDate = boardingPassData.arrivalDate != nil
        hasDepartureTime = Self.parseTimeString(boardingPassData.departureTime) != nil
        hasArrivalTime = Self.parseTimeString(boardingPassData.arrivalTime) != nil

        // Reset date picker values
        let currentDate = Date()
        let flightDate = boardingPassData.departureDate ?? currentDate
        let arrivalFlightDate = boardingPassData.arrivalDate ?? currentDate

        let parsedDepartureTime = Self.parseTimeString(boardingPassData.departureTime)
        let parsedArrivalTime = Self.parseTimeString(boardingPassData.arrivalTime)

        departureDate = flightDate
        arrivalDate = arrivalFlightDate
        departureTime = parsedDepartureTime != nil ?
            Self.combineDateAndTime(date: flightDate, time: parsedDepartureTime!) : currentDate
        arrivalTime = parsedArrivalTime != nil ?
            Self.combineDateAndTime(date: arrivalFlightDate, time: parsedArrivalTime!) : currentDate

        // Add haptic feedback
        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
        impactFeedback.impactOccurred()

        print("🔄 Reset to original boarding pass data")
    }

    private func validateDateTimeLogic() -> String? {
        // Only validate if we have both departure and arrival dates/times
        guard hasDepartureDate && hasArrivalDate && hasDepartureTime && hasArrivalTime else {
            return nil // Skip validation if incomplete data
        }

        let departureDateTime = Self.combineDateAndTime(date: departureDate, time: departureTime)
        let arrivalDateTime = Self.combineDateAndTime(date: arrivalDate, time: arrivalTime)

        // NO "departure is too far in the past" CHECK, and its absence is the
        // point. It used to reject any pass whose departure was more than 24
        // hours old, which made logging a flight you had already taken
        // impossible — you would scan the pass in your pocket on landing and be
        // told the date "seems too far in the past". Logging past flights is
        // what this app is for.
        //
        // `BusinessRules.allowPastDatesHours` and
        // `ErrorMessages.departureTooOld` in BoardingPassConfig, and
        // `ValidationError.departureTooOld`, are left in place: nothing reads
        // them now, and they are the hook if a bound is ever wanted back.

        // Check if arrival is before departure
        if arrivalDateTime <= departureDateTime {
            return "Arrival must be after departure"
        }

        return nil
    }

    private func getValidationErrorMessage() -> String {
        var errors: [String] = []

        if let error = flightNumberError {
            errors.append("Flight Number: \(error)")
        }
        if let error = departureCodeError {
            errors.append("Departure Airport: \(error)")
        }
        if let error = arrivalCodeError {
            errors.append("Arrival Airport: \(error)")
        }
        if let error = dateTimeError {
            errors.append("Date/Time: \(error)")
        }

        if errors.isEmpty {
            return "Please correct the highlighted fields and try again."
        } else {
            return errors.joined(separator: "\n\n")
        }
    }

    private func formatTimeForBoardingPass(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    static func parseTimeString(_ timeString: String?) -> Date? {
        guard let timeString = timeString, !timeString.isEmpty else {
            return nil
        }

        let timeFormats = ["HH:mm", "H:mm", "h:mm a", "hh:mm a"]

        for format in timeFormats {
            let formatter = DateFormatter()
            formatter.dateFormat = format
            formatter.locale = Locale(identifier: "en_US_POSIX")

            if let date = formatter.date(from: timeString) {
                return date
            }
        }

        return nil
    }

    static func combineDateAndTime(date: Date, time: Date) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute], from: time)

        var combinedComponents = DateComponents()
        combinedComponents.year = dateComponents.year
        combinedComponents.month = dateComponents.month
        combinedComponents.day = dateComponents.day
        combinedComponents.hour = timeComponents.hour
        combinedComponents.minute = timeComponents.minute

        return calendar.date(from: combinedComponents) ?? date
    }
}

#Preview("Boarding Pass Confirmation — Light") {
    BoardingPassConfirmationView(
        boardingPassData: BoardingPassData(
            flightNumber: "WY0153",
            departureCode: "MCT",
            arrivalCode: "ZRH",
            departureDate: nil,
            departureTime: "14:30",
            arrivalTime: "19:45",
            gate: "A12",
            terminal: "3",
            seat: "12A",
            confirmationCode: "ABC123",
            passengerName: "JOHN DOE"
        ),
        onConfirm: { data in
            print("Confirmed:", data)
        },
        onCancel: {
            print("Cancelled")
        }
    )
    .environmentObject(BoardingPassConfirmationPreviewTheme.light)
}

#Preview("Boarding Pass Confirmation — Dark") {
    BoardingPassConfirmationView(
        boardingPassData: BoardingPassData(
            flightNumber: "WY0153",
            departureCode: "MCT",
            arrivalCode: "ZRH",
            departureDate: nil,
            departureTime: "14:30",
            arrivalTime: "19:45",
            gate: "A12",
            terminal: "3",
            seat: "12A",
            confirmationCode: "ABC123",
            passengerName: "JOHN DOE"
        ),
        onConfirm: { data in
            print("Confirmed:", data)
        },
        onCancel: {
            print("Cancelled")
        }
    )
    .environmentObject(BoardingPassConfirmationPreviewTheme.dark)
}

/// Both previews are pinned to a theme rather than to a device appearance — the
/// interesting case for this screen is precisely the mismatch between the two.
private enum BoardingPassConfirmationPreviewTheme {
    static var light: ThemeManager {
        let manager = ThemeManager()
        manager.currentTheme = .light
        return manager
    }

    static var dark: ThemeManager {
        let manager = ThemeManager()
        manager.currentTheme = .dark
        return manager
    }
}
