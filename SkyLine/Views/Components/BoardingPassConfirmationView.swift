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
    
    @EnvironmentObject var themeManager: ThemeManager
    @State private var editedData: BoardingPassData
    @State private var showingValidationErrors = false
    @Environment(\.dismiss) private var dismiss
    
    init(boardingPassData: BoardingPassData, onConfirm: @escaping (BoardingPassData) -> Void, onCancel: @escaping () -> Void) {
        self.boardingPassData = boardingPassData
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._editedData = State(initialValue: boardingPassData)
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Flight Information Section
                    flightInfoSection
                    
                    // Route Information Section
                    routeSection
                    
                    // Time Information Section
                    timeSection
                    
                    // Terminal & Gate Section
                    terminalGateSection
                    
                    // Passenger Information Section
                    passengerInfoSection
                    
                    // Action Buttons
                    actionButtonsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("Confirm Flight Details")
            .navigationBarTitleDisplayMode(.inline)
            .background(themeManager.currentTheme.colors.background)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                }
            }
        }
        .alert("Validation Error", isPresented: $showingValidationErrors) {
            Button("OK") { }
        } message: {
            Text("Please ensure flight number, departure airport, and arrival airport are filled in.")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.viewfinder")
                .font(.system(size: 48, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.primary)
            
            VStack(spacing: 8) {
                Text("Boarding Pass Scanned")
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                
                Text("Please review and edit the extracted flight information below")
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(16)
    }
    
    private var flightInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Flight Information")
            
            VStack(spacing: 12) {
                EditableField(
                    label: "Flight Number",
                    value: Binding(
                        get: { editedData.flightNumber ?? "" },
                        set: { editedData.flightNumber = $0.isEmpty ? nil : $0.uppercased() }
                    ),
                    placeholder: "e.g., UA546",
                    isRequired: true
                )
                
                EditableField(
                    label: "Confirmation Code",
                    value: Binding(
                        get: { editedData.confirmationCode ?? "" },
                        set: { editedData.confirmationCode = $0.isEmpty ? nil : $0.uppercased() }
                    ),
                    placeholder: "e.g., ABC123",
                    isRequired: false
                )
            }
        }
        .padding(20)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
    
    private var routeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Route")
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("From")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                    
                    TextField("LAX", text: Binding(
                        get: { editedData.departureCode ?? "" },
                        set: { editedData.departureCode = $0.isEmpty ? nil : $0.uppercased() }
                    ))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(themeManager.currentTheme.colors.background)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeManager.currentTheme.colors.primary.opacity(0.3), lineWidth: 1)
                    )
                }
                
                VStack {
                    Text("✈️")
                        .font(.system(size: 24, design: .monospaced))
                        .padding(.top, 20)
                }
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("To")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                    
                    TextField("JFK", text: Binding(
                        get: { editedData.arrivalCode ?? "" },
                        set: { editedData.arrivalCode = $0.isEmpty ? nil : $0.uppercased() }
                    ))
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(themeManager.currentTheme.colors.background)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(themeManager.currentTheme.colors.primary.opacity(0.3), lineWidth: 1)
                    )
                    .multilineTextAlignment(.center)
                }
            }
        }
        .padding(20)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
    
    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Times")
            
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Departure")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                    
                    TextField("7:35 PM", text: Binding(
                        get: { editedData.departureTime ?? "" },
                        set: { editedData.departureTime = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(themeManager.currentTheme.colors.background)
                    .cornerRadius(8)
                }
                
                VStack(alignment: .trailing, spacing: 8) {
                    Text("Arrival")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                        .textCase(.uppercase)
                    
                    TextField("10:15 PM", text: Binding(
                        get: { editedData.arrivalTime ?? "" },
                        set: { editedData.arrivalTime = $0.isEmpty ? nil : $0 }
                    ))
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.text)
                    .textFieldStyle(PlainTextFieldStyle())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(themeManager.currentTheme.colors.background)
                    .cornerRadius(8)
                }
            }
        }
        .padding(20)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
    
    private var terminalGateSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Terminal & Gate")
            
            HStack(spacing: 16) {
                EditableField(
                    label: "Terminal",
                    value: Binding(
                        get: { editedData.terminal ?? "" },
                        set: { editedData.terminal = $0.isEmpty ? nil : $0.uppercased() }
                    ),
                    placeholder: "A, B, C, etc.",
                    isRequired: false
                )
                
                EditableField(
                    label: "Gate",
                    value: Binding(
                        get: { editedData.gate ?? "" },
                        set: { editedData.gate = $0.isEmpty ? nil : $0.uppercased() }
                    ),
                    placeholder: "C109",
                    isRequired: false
                )
            }
        }
        .padding(20)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
    
    private var passengerInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Passenger Information")
            
            VStack(spacing: 12) {
                EditableField(
                    label: "Passenger Name",
                    value: Binding(
                        get: { editedData.passengerName ?? "" },
                        set: { editedData.passengerName = $0.isEmpty ? nil : $0.uppercased() }
                    ),
                    placeholder: "LAST/FIRST",
                    isRequired: false
                )
                
                EditableField(
                    label: "Seat",
                    value: Binding(
                        get: { editedData.seat ?? "" },
                        set: { editedData.seat = $0.isEmpty ? nil : $0.uppercased() }
                    ),
                    placeholder: "23D",
                    isRequired: false
                )
            }
        }
        .padding(20)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                if validateData() {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onConfirm(editedData)
                } else {
                    showingValidationErrors = true
                }
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                    
                    Text("SAVE FLIGHT")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [themeManager.currentTheme.colors.success, themeManager.currentTheme.colors.success.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
            }
            
            Button(action: {
                let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                impactFeedback.impactOccurred()
                onCancel()
            }) {
                HStack(spacing: 12) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 18, weight: .medium, design: .monospaced))
                    
                    Text("CANCEL")
                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                }
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(themeManager.currentTheme.colors.background)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                )
            }
        }
        .padding(20)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
    }
    
    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.text)
            Spacer()
        }
    }
    
    private func validateData() -> Bool {
        return editedData.flightNumber != nil && 
               !editedData.flightNumber!.isEmpty &&
               editedData.departureCode != nil && 
               !editedData.departureCode!.isEmpty &&
               editedData.arrivalCode != nil && 
               !editedData.arrivalCode!.isEmpty
    }
}

// MARK: - Editable Field Component

struct EditableField: View {
    let label: String
    @Binding var value: String
    let placeholder: String
    let isRequired: Bool
    
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(label)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    .textCase(.uppercase)
                
                if isRequired {
                    Text("*")
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.error)
                }
                
                Spacer()
            }
            
            TextField(placeholder, text: $value)
                .font(.system(size: 16, weight: .medium, design: .monospaced))
                .foregroundColor(themeManager.currentTheme.colors.text)
                .textFieldStyle(PlainTextFieldStyle())
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(themeManager.currentTheme.colors.background)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isRequired && value.isEmpty ? 
                            themeManager.currentTheme.colors.error.opacity(0.5) :
                            themeManager.currentTheme.colors.border,
                            lineWidth: 1
                        )
                )
        }
    }
}

#Preview("Boarding Pass Confirmation") {
    BoardingPassConfirmationView(
        boardingPassData: BoardingPassData(
            flightNumber: "UA546",
            departureCode: "EWR",
            arrivalCode: "ORD",
            departureDate: nil,
            departureTime: "7:35 PM",
            arrivalTime: "9:45 PM",
            gate: "C109",
            terminal: "C",
            seat: "23D",
            confirmationCode: "ABC123",
            passengerName: "MADAN/PRIYANSHU"
        ),
        onConfirm: { data in
            print("Confirmed:", data)
        },
        onCancel: {
            print("Cancelled")
        }
    )
    .environmentObject(ThemeManager())
}