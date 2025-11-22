//
//  PhotoPickerView.swift
//  SkyLine
//
//  SwiftUI photo picker for boarding pass screenshots
//

import SwiftUI
import PhotosUI

struct PhotoPickerView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var scanner = BoardingPassScanner()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingPicker = false
    @State private var extractedData: BoardingPassData?
    @State private var showingConfirmation = false
    
    let onFlightExtracted: (BoardingPassData) -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Scan Button
            Button(action: { isShowingPicker = true }) {
                HStack(spacing: 12) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(.headline, design: .monospaced))
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan Boarding Pass")
                            .font(.system(.body, weight: .bold, design: .monospaced))
                        Text("From Apple Wallet screenshot")
                            .font(.system(.caption, design: .monospaced))
                            .opacity(0.8)
                    }
                    
                    Spacer()
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(
                    LinearGradient(
                        colors: [themeManager.currentTheme.colors.primary, themeManager.currentTheme.colors.primary.opacity(0.8)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: themeManager.currentTheme.colors.primary.opacity(0.3), radius: 8, x: 0, y: 4)
            }
            .disabled(scanner.isProcessing)
            
            // Processing State
            if scanner.isProcessing {
                HStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(0.8)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scanning boarding pass...")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Text("Reading flight details")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(themeManager.currentTheme.colors.surface)
                .cornerRadius(8)
            }
            
            // Error State
            if let error = scanner.lastError {
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(.body, weight: .bold, design: .monospaced))
                        .foregroundColor(themeManager.currentTheme.colors.error)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Scan Failed")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.error)
                        Text(error)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    }
                    
                    Spacer()
                    
                    Button("Retry") {
                        isShowingPicker = true
                    }
                    .font(.system(.caption, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(themeManager.currentTheme.colors.error.opacity(0.1))
                .cornerRadius(8)
            }
        }
        .photosPicker(isPresented: $isShowingPicker, selection: $selectedPhoto, matching: .images)
        .onChange(of: selectedPhoto) { newPhoto in
            if let newPhoto = newPhoto {
                processSelectedPhoto(newPhoto)
            }
        }
        .sheet(isPresented: $showingConfirmation) {
            if let data = extractedData {
                BoardingPassConfirmationView(
                    boardingPassData: data,
                    onConfirm: { confirmedData in
                        showingConfirmation = false
                        onFlightExtracted(confirmedData)
                        extractedData = nil
                    },
                    onCancel: {
                        showingConfirmation = false
                        extractedData = nil
                    }
                )
                .environmentObject(themeManager)
            }
        }
    }
    
    // MARK: - Photo Processing
    
    private func processSelectedPhoto(_ photo: PhotosPickerItem) {
        Task {
            do {
                guard let imageData = try await photo.loadTransferable(type: Data.self),
                      let uiImage = UIImage(data: imageData) else {
                    await MainActor.run {
                        scanner.lastError = "Failed to load selected image"
                    }
                    return
                }
                
                print("📸 Processing boarding pass image...")
                
                if let boardingPassData = await scanner.scanBoardingPass(from: uiImage) {
                    await MainActor.run {
                        extractedData = boardingPassData
                        showingConfirmation = true
                    }
                    print("✅ OCR completed successfully:", boardingPassData.summary)
                } else {
                    print("❌ OCR failed to extract boarding pass data")
                }
                
            } catch {
                await MainActor.run {
                    scanner.lastError = "Error loading image: \(error.localizedDescription)"
                }
                print("❌ Error processing photo:", error)
            }
        }
    }
}


// MARK: - Form Field Component

struct FormField: View {
    let title: String
    @Binding var value: String?
    let placeholder: String
    let icon: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(.caption, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.primary)
                    .frame(width: 16)
                
                Text(title)
                    .font(.system(.caption, weight: .bold, design: .monospaced))
                    .foregroundColor(themeManager.currentTheme.colors.textSecondary)
            }
            
            TextField(placeholder, text: Binding(
                get: { value ?? "" },
                set: { value = $0.isEmpty ? nil : $0 }
            ))
            .font(.system(.body, design: .monospaced))
            .foregroundColor(themeManager.currentTheme.colors.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(themeManager.currentTheme.colors.surface)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(themeManager.currentTheme.colors.primary.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

#Preview {
    PhotoPickerView { data in
        print("Flight extracted:", data.summary)
    }
    .environmentObject(ThemeManager())
}