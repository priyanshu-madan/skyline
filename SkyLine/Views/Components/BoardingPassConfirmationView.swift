//
//  BoardingPassConfirmationView.swift
//  SkyLine
//
//  Confirmation view for scanned boarding pass data
//

import SwiftUI

struct BoardingPassConfirmationView: View {
    let boardingPassData: BoardingPassData
    let onConfirm: (BoardingPassData) -> Void
    let onCancel: () -> Void
    
    @StateObject private var configService = ConfigurationService.shared
    
    @State private var editedData: BoardingPassData
    @State private var showingValidationErrors = false
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
    
    init(boardingPassData: BoardingPassData, onConfirm: @escaping (BoardingPassData) -> Void, onCancel: @escaping () -> Void) {
        self.boardingPassData = boardingPassData
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._editedData = State(initialValue: boardingPassData)
        
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
        GeometryReader { geometry in
            ZStack {
                Color(UIColor.systemGroupedBackground)
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Header
                    header
                    
                    // Scrollable content
                    ScrollView {
                        VStack(spacing: 0) {
                            // Hero section
                            heroSection
                            
                            // Content cards
                            VStack(spacing: 12) {
                                routeAndTimesCard
                                flightInformationCard
                                additionalDetailsCard
                            }
                            .padding(.horizontal, 20)
                            .padding(.bottom, 120) // Space for sticky buttons
                        }
                    }
                    
                    Spacer()
                }
                
                // Sticky bottom buttons
                VStack {
                    Spacer()
                    stickyBottomButtons
                }
            }
        }
        .alert("Validation Error", isPresented: $showingValidationErrors) {
            Button("OK") { }
        } message: {
            Text(getValidationErrorMessage())
        }
        .onAppear {
            print("📋 BoardingPassConfirmationView appeared for flight: \(boardingPassData.flightNumber ?? "nil")")
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Button(action: {
                onCancel()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(.systemBlue))
            }
            
            Spacer()
            
            Text("Confirm Flight Details")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.primary)
            
            Spacer()
            
            Button(action: {
                resetToOriginal()
            }) {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(Color(.systemBlue))
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .bottom
        )
    }
    
    // MARK: - Hero Section
    
    private var heroSection: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(Color(.systemBlue).opacity(0.1))
                    .frame(width: 48, height: 48)
                
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(Color(.systemBlue))
            }
            
            Text("Boarding Pass Scanned")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(.primary)
            
            Text("Review and edit if needed")
                .font(.system(size: 13, weight: .regular))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.systemGray5)),
            alignment: .bottom
        )
    }
    
    // MARK: - Flight Information Card
    
    private var flightInformationCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("FLIGHT INFORMATION")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Flight Number")
                                .font(.system(size: 13, weight: .regular))
                                .foregroundColor(.secondary)
                            
                            Text("*")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(.red)
                        }
                        
                        TextField(configService.getPlaceholder(for: .flightNumber), text: Binding(
                            get: { editedData.flightNumber ?? "" },
                            set: { newValue in
                                editedData.flightNumber = newValue.isEmpty ? nil : newValue.uppercased()
                                // Real-time validation
                                if !newValue.isEmpty && !isValidFlightNumber(newValue.uppercased()) {
                                    flightNumberError = configService.getErrorMessage(for: .flightNumberInvalid)
                                } else {
                                    flightNumberError = nil
                                }
                                
                                // Auto-suggest airline based on flight number using AirlineService
                                Task {
                                    if let airline = await AirlineService.shared.getAirlineFromFlightNumber(newValue.uppercased()) {
                                        await MainActor.run {
                                            if editedData.airline?.isEmpty != false {
                                                editedData.airline = airline
                                            }
                                        }
                                    }
                                }
                            }
                        ))
                        .font(.system(size: 17, weight: .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(textFieldStyle(hasError: flightNumberError != nil))
                        
                        errorText(flightNumberError)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Confirmation")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                        
                        TextField(configService.getPlaceholder(for: .confirmationCode), text: Binding(
                            get: { editedData.confirmationCode ?? "" },
                            set: { newValue in
                                editedData.confirmationCode = newValue.isEmpty ? nil : newValue.uppercased()
                                // Real-time validation for optional field
                                if !newValue.isEmpty && !isValidConfirmationCode(newValue.uppercased()) {
                                    confirmationCodeError = configService.getErrorMessage(for: .confirmationCodeInvalid)
                                } else {
                                    confirmationCodeError = nil
                                }
                            }
                        ))
                        .font(.system(size: 17, weight: .regular))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(textFieldStyle(hasError: confirmationCodeError != nil))
                        
                        errorText(confirmationCodeError)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Airline")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    TextField(configService.getPlaceholder(for: .airline), text: Binding(
                        get: { editedData.airline ?? "" },
                        set: { editedData.airline = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.system(size: 17, weight: .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color(.systemGray4).opacity(0.3), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Route & Times Card
    
    private var routeAndTimesCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("FLIGHT DETAILS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            HStack(alignment: .top, spacing: 12) {
                // Departure Side
                VStack(alignment: .center, spacing: 12) {
                    Text("DEPARTURE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.3)
                    
                    VStack(alignment: .center, spacing: 8) {
                        // Airport Code
                        VStack(spacing: 4) {
                            TextField(configService.getPlaceholder(for: .departureAirport), text: Binding(
                                get: { editedData.departureCode ?? "" },
                                set: { newValue in
                                    editedData.departureCode = newValue.isEmpty ? nil : newValue.uppercased()
                                    // Real-time validation
                                    if !newValue.isEmpty && !isValidAirportCode(newValue.uppercased()) {
                                        departureCodeError = configService.getErrorMessage(for: .airportCodeInvalid)
                                    } else {
                                        departureCodeError = nil
                                    }
                                    
                                    // Auto-suggest city name from airport code using AirportService
                                    Task {
                                        let airportInfo = await AirportService.shared.getAirportInfo(for: newValue.uppercased())
                                        await MainActor.run {
                                            if let city = airportInfo.city, editedData.departureCity?.isEmpty != false {
                                                editedData.departureCity = city
                                            }
                                        }
                                    }
                                }
                            ))
                            .font(.system(size: 20, weight: .medium))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .overlay(textFieldStyle(hasError: departureCodeError != nil))
                            
                            if let error = departureCodeError {
                                Text(error)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // City
                        TextField(configService.getPlaceholder(for: .departureCity), text: Binding(
                            get: { editedData.departureCity ?? "" },
                            set: { editedData.departureCity = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.clear)
                        
                        // Date
                        VStack(alignment: .center, spacing: 4) {
                            Text("Date")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            if hasDepartureDate {
                                DatePicker("", selection: $departureDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .onChange(of: departureDate) { newDate in
                                        editedData.departureDate = newDate
                                        print("🔄 Updated departure date: \(newDate.formatted())")
                                        // Trigger date/time validation
                                        if let error = validateDateTimeLogic() {
                                            dateTimeError = error
                                        } else {
                                            dateTimeError = nil
                                        }
                                    }
                                    .frame(height: 36)
                                    .padding(.horizontal, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            } else {
                                Button(action: {
                                    hasDepartureDate = true
                                    editedData.departureDate = departureDate
                                    print("➕ Added departure date: \(departureDate.formatted())")
                                }) {
                                    HStack {
                                        Text("N/A")
                                            .font(.system(size: 17, weight: .regular))
                                            .foregroundColor(.secondary)
                                        
                                        Image(systemName: "plus.circle.fill")
                                            .font(.system(size: 14, weight: .medium))
                                            .foregroundColor(.blue)
                                    }
                                    .frame(height: 36)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color(.systemBlue).opacity(0.5), lineWidth: 1)
                                            .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [3]))
                                    )
                                }
                            }
                        }
                        
                        // Time
                        VStack(alignment: .center, spacing: 4) {
                            Text("Time")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            if hasDepartureTime {
                                DatePicker("", selection: $departureTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .onChange(of: departureTime) { newTime in
                                        editedData.departureTime = formatTimeForBoardingPass(newTime)
                                        // Trigger date/time validation
                                        if let error = validateDateTimeLogic() {
                                            dateTimeError = error
                                        } else {
                                            dateTimeError = nil
                                        }
                                    }
                                    .frame(height: 36)
                                    .padding(.horizontal, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            } else {
                                Button(action: {
                                    hasDepartureTime = true
                                    editedData.departureTime = formatTimeForBoardingPass(departureTime)
                                }) {
                                    Text("N/A")
                                        .font(.system(size: 17, weight: .regular))
                                        .foregroundColor(.secondary)
                                        .frame(height: 36)
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                
                // Arrow
                VStack {
                    Spacer()
                    ZStack {
                        Circle()
                            .fill(Color(.systemBlue).opacity(0.1))
                            .frame(width: 28, height: 28)
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(Color(.systemBlue))
                    }
                    Spacer()
                }
                .frame(maxHeight: .infinity)
                
                // Arrival Side
                VStack(alignment: .center, spacing: 12) {
                    Text("ARRIVAL")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.secondary)
                        .tracking(0.3)
                    
                    VStack(alignment: .center, spacing: 8) {
                        // Airport Code
                        VStack(spacing: 4) {
                            TextField(configService.getPlaceholder(for: .arrivalAirport), text: Binding(
                                get: { editedData.arrivalCode ?? "" },
                                set: { newValue in
                                    editedData.arrivalCode = newValue.isEmpty ? nil : newValue.uppercased()
                                    // Real-time validation
                                    if !newValue.isEmpty {
                                        if !isValidAirportCode(newValue.uppercased()) {
                                            arrivalCodeError = configService.getErrorMessage(for: .airportCodeInvalid)
                                        } else if newValue.uppercased() == editedData.departureCode {
                                            arrivalCodeError = configService.getErrorMessage(for: .airportCodeSameAsOther)
                                        } else {
                                            arrivalCodeError = nil
                                        }
                                    } else {
                                        arrivalCodeError = nil
                                    }
                                    
                                    // Auto-suggest city name from airport code using AirportService
                                    Task {
                                        let airportInfo = await AirportService.shared.getAirportInfo(for: newValue.uppercased())
                                        await MainActor.run {
                                            if let city = airportInfo.city, editedData.arrivalCity?.isEmpty != false {
                                                editedData.arrivalCity = city
                                            }
                                        }
                                    }
                                }
                            ))
                            .font(.system(size: 20, weight: .medium))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(Color(.systemGray6))
                            .cornerRadius(10)
                            .overlay(textFieldStyle(hasError: arrivalCodeError != nil))
                            
                            if let error = arrivalCodeError {
                                Text(error)
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(.red)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        
                        // City
                        TextField(configService.getPlaceholder(for: .arrivalCity), text: Binding(
                            get: { editedData.arrivalCity ?? "" },
                            set: { editedData.arrivalCity = $0.isEmpty ? nil : $0 }
                        ))
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.clear)
                        
                        // Date
                        VStack(alignment: .center, spacing: 4) {
                            Text("Date")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            if hasArrivalDate {
                                DatePicker("", selection: $arrivalDate, displayedComponents: .date)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .onChange(of: arrivalDate) { newDate in
                                        editedData.arrivalDate = newDate
                                        print("🔄 Updated arrival date: \(newDate.formatted())")
                                        // Trigger date/time validation
                                        if let error = validateDateTimeLogic() {
                                            dateTimeError = error
                                        } else {
                                            dateTimeError = nil
                                        }
                                    }
                                    .frame(height: 36)
                                    .padding(.horizontal, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            } else {
                                Button(action: {
                                    hasArrivalDate = true
                                    editedData.arrivalDate = arrivalDate
                                    print("➕ Added arrival date: \(arrivalDate.formatted())")
                                }) {
                                    Text("N/A")
                                        .font(.system(size: 17, weight: .regular))
                                        .foregroundColor(.secondary)
                                        .frame(height: 36)
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        
                        // Time
                        VStack(alignment: .center, spacing: 4) {
                            Text("Time")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                            
                            if hasArrivalTime {
                                DatePicker("", selection: $arrivalTime, displayedComponents: .hourAndMinute)
                                    .datePickerStyle(.compact)
                                    .labelsHidden()
                                    .onChange(of: arrivalTime) { newTime in
                                        editedData.arrivalTime = formatTimeForBoardingPass(newTime)
                                        // Trigger date/time validation
                                        if let error = validateDateTimeLogic() {
                                            dateTimeError = error
                                        } else {
                                            dateTimeError = nil
                                        }
                                    }
                                    .frame(height: 36)
                                    .padding(.horizontal, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                            } else {
                                Button(action: {
                                    hasArrivalTime = true
                                    editedData.arrivalTime = formatTimeForBoardingPass(arrivalTime)
                                }) {
                                    Text("N/A")
                                        .font(.system(size: 17, weight: .regular))
                                        .foregroundColor(.secondary)
                                        .frame(height: 36)
                                        .frame(maxWidth: .infinity)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
            }
            
            // Date/Time validation error display
            if let dateTimeError = dateTimeError {
                HStack {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: 14))
                        .foregroundColor(.orange)
                    
                    Text(dateTimeError)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.orange)
                    
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color(.systemGray4).opacity(0.3), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Additional Details Card
    
    private var additionalDetailsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ADDITIONAL DETAILS")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Terminal")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                        
                        TextField(configService.getPlaceholder(for: .terminal), text: Binding(
                            get: { editedData.terminal ?? "" },
                            set: { editedData.terminal = $0.isEmpty ? nil : $0.uppercased() }
                        ))
                        .font(.system(size: 17, weight: .regular))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.clear, lineWidth: 0)
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Gate")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                        
                        TextField(configService.getPlaceholder(for: .gate), text: Binding(
                            get: { editedData.gate ?? "" },
                            set: { editedData.gate = $0.isEmpty ? nil : $0.uppercased() }
                        ))
                        .font(.system(size: 17, weight: .regular))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.clear, lineWidth: 0)
                        )
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Seat")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                        
                        TextField(configService.getPlaceholder(for: .seat), text: Binding(
                            get: { editedData.seat ?? "" },
                            set: { newValue in
                                editedData.seat = newValue.isEmpty ? nil : newValue.uppercased()
                                // Real-time validation for optional field
                                if !newValue.isEmpty && !isValidSeatNumber(newValue.uppercased()) {
                                    seatError = configService.getErrorMessage(for: .seatNumberInvalid)
                                } else {
                                    seatError = nil
                                }
                            }
                        ))
                        .font(.system(size: 17, weight: .regular))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(.systemGray6))
                        .cornerRadius(10)
                        .overlay(textFieldStyle(hasError: seatError != nil))
                        
                        errorText(seatError)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Passenger Name")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(.secondary)
                    
                    TextField(configService.getPlaceholder(for: .passengerName), text: Binding(
                        get: { editedData.passengerName ?? "" },
                        set: { editedData.passengerName = $0.isEmpty ? nil : $0.uppercased() }
                    ))
                    .font(.system(size: 17, weight: .regular))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.clear, lineWidth: 0)
                    )
                }
            }
        }
        .padding(12)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color(.systemGray4).opacity(0.3), radius: 1, x: 0, y: 1)
    }
    
    // MARK: - Sticky Bottom Buttons
    
    private var stickyBottomButtons: some View {
        VStack(spacing: 8) {
            Button(action: {
                if validateData() {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onConfirm(editedData)
                } else {
                    showingValidationErrors = true
                }
            }) {
                Text(configService.getButtonText(for: .saveFlightButton))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(.systemBlue))
                    .cornerRadius(12)
            }
            
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                onCancel()
            }) {
                Text(configService.getButtonText(for: .cancelButton))
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(Color(.systemBlue))
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.systemBlue), lineWidth: 1)
                    )
                    .cornerRadius(12)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 0.5)
                .foregroundColor(Color(.separator)),
            alignment: .top
        )
    }
    
    // MARK: - Helper Functions
    
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
        editedData = boardingPassData
        
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
        
        // Check if departure is in the past (more than 24 hours ago)
        let dayAgo = Date().addingTimeInterval(-24 * 60 * 60)
        if departureDateTime < dayAgo {
            return "Departure date seems too far in the past"
        }
        
        // Check if arrival is before departure
        if arrivalDateTime <= departureDateTime {
            return "Arrival must be after departure"
        }
        
        // Check if flight duration is unrealistic (more than 24 hours)
        let duration = arrivalDateTime.timeIntervalSince(departureDateTime)
        if duration > 24 * 60 * 60 {
            return "Flight duration seems unusually long"
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
    
    // MARK: - Validation Styling Helpers
    
    private func textFieldStyle(hasError: Bool) -> some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(hasError ? Color.red : Color.clear, lineWidth: hasError ? 1.5 : 0)
    }
    
    private func errorText(_ error: String?) -> some View {
        Group {
            if let error = error {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    
                    Text(error)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.red)
                    
                    Spacer()
                }
                .padding(.horizontal, 4)
                .padding(.top, 2)
            }
        }
    }
}

#Preview("Boarding Pass Confirmation") {
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
}