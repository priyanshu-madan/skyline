//
//  DestinationImageUploadView.swift
//  SkyLine
//
//  Admin view for uploading destination images to CloudKit
//

import SwiftUI
import PhotosUI

struct DestinationImageUploadView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var imageService = DestinationImageService.shared
    
    @State private var selectedImage: PhotosPickerItem?
    @State private var selectedUIImage: UIImage?
    @State private var airportCode: String = ""
    @State private var cityName: String = ""
    @State private var countryName: String = ""
    @State private var imageURL: String = ""
    
    @State private var isUploading: Bool = false
    @State private var uploadSuccess: Bool = false
    @State private var uploadError: String?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    VStack(spacing: 8) {
                        Text("Upload Destination Image")
                            .font(.system(.title, design: .monospaced))
                            .fontWeight(.bold)
                        
                        Text("Add beautiful destination images for flight details")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    
                    // Image Picker
                    VStack(spacing: 16) {
                        if let image = selectedUIImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(height: 200)
                                .cornerRadius(12)
                                .clipped()
                        } else {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(themeManager.currentTheme.colors.surface)
                                .frame(height: 200)
                                .overlay(
                                    VStack(spacing: 8) {
                                        Image(systemName: "photo.badge.plus")
                                            .font(.system(size: 32, design: .monospaced))
                                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                        
                                        Text("Select Image")
                                            .font(.system(.body, design: .monospaced))
                                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    }
                                )
                        }
                        
                        PhotosPicker(
                            selection: $selectedImage,
                            matching: .images,
                            photoLibrary: .shared()
                        ) {
                            HStack {
                                Image(systemName: "photo")
                                Text("Choose Photo")
                            }
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.white)
                            .padding()
                            .background(themeManager.currentTheme.colors.primary)
                            .cornerRadius(8)
                        }
                    }
                    
                    // Form Fields
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Airport Code (Required)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            
                            TextField("LAX", text: $airportCode)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(.body, design: .monospaced))
                                .textCase(.uppercase)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("City Name (Required)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            
                            TextField("Los Angeles", text: $cityName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Country Name (Optional)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            
                            TextField("United States", text: $countryName)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(.body, design: .monospaced))
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Image Source URL (Optional)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                            
                            TextField("https://...", text: $imageURL)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .font(.system(.body, design: .monospaced))
                                .keyboardType(.URL)
                        }
                    }
                    
                    // Upload Button
                    Button {
                        uploadImage()
                    } label: {
                        HStack {
                            if isUploading {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                                Text("Uploading...")
                            } else {
                                Image(systemName: "icloud.and.arrow.up")
                                Text("Upload to CloudKit")
                            }
                        }
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(canUpload ? themeManager.currentTheme.colors.primary : Color.gray)
                        .cornerRadius(8)
                    }
                    .disabled(!canUpload || isUploading)
                    
                    // Status Messages
                    if uploadSuccess {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Image uploaded successfully!")
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding()
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    if let error = uploadError {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.system(.body, design: .monospaced))
                        }
                        .padding()
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("Admin")
            .navigationBarTitleDisplayMode(.inline)
        }
        .onChange(of: selectedImage) { _, newValue in
            Task {
                if let data = try? await newValue?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedUIImage = image
                }
            }
        }
    }
    
    private var canUpload: Bool {
        selectedUIImage != nil && 
        !airportCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func uploadImage() {
        guard let image = selectedUIImage else { return }
        
        isUploading = true
        uploadSuccess = false
        uploadError = nil
        
        Task {
            let success = await imageService.uploadDestinationImage(
                airportCode: airportCode.trimmingCharacters(in: .whitespacesAndNewlines),
                cityName: cityName.trimmingCharacters(in: .whitespacesAndNewlines),
                countryName: countryName.isEmpty ? nil : countryName.trimmingCharacters(in: .whitespacesAndNewlines),
                image: image,
                imageURL: imageURL.isEmpty ? nil : imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            
            await MainActor.run {
                isUploading = false
                
                if success {
                    uploadSuccess = true
                    // Reset form
                    selectedImage = nil
                    selectedUIImage = nil
                    airportCode = ""
                    cityName = ""
                    countryName = ""
                    imageURL = ""
                } else {
                    uploadError = "Failed to upload image. Please try again."
                }
            }
        }
    }
}

#Preview {
    DestinationImageUploadView()
        .environmentObject(ThemeManager())
}