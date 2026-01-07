//
//  UploadItineraryView.swift
//  SkyLine
//
//  Smart itinerary upload and processing view
//

import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import PDFKit

struct UploadItineraryView: View {
    @EnvironmentObject var themeManager: ThemeManager
    @Environment(\.dismiss) private var dismiss
    
    @StateObject private var aiService = AIItineraryService.shared
    @State private var selectedUploadType: UploadType = .image
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var selectedImages: [UIImage] = []
    @State private var showingDocumentPicker = false
    @State private var documentURL: URL?
    @State private var manualText = ""
    @State private var urlText = ""
    
    @State private var processingResult: ParsedItinerary?
    @State private var showingReview = false
    @State private var error: String?
    
    let onItineraryProcessed: (ParsedItinerary) -> Void
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Upload Type Selector
                    uploadTypeSelector
                    
                    // Upload Interface
                    if !aiService.isProcessing {
                        uploadInterface
                    }
                    
                    // Processing Status
                    if aiService.isProcessing {
                        processingStatusView
                    }
                    
                    // Error Display
                    if let error = error {
                        errorView(error)
                    }
                    
                    // Process Button
                    if canProcess {
                        processButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }
            .navigationTitle("Upload Itinerary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        if !aiService.isProcessing {
                            dismiss()
                        }
                    }
                    .disabled(aiService.isProcessing)
                }
            }
            .overlay(
                // Processing overlay
                aiService.isProcessing ? processingOverlay : nil
            )
        }
        .sheet(isPresented: $showingDocumentPicker) {
            DocumentPicker(documentURL: $documentURL)
        }
        .sheet(isPresented: $showingReview) {
            if let itinerary = processingResult {
                ReviewItineraryView(
                    parsedItinerary: itinerary,
                    onConfirm: { finalItinerary in
                        onItineraryProcessed(finalItinerary)
                        dismiss()
                    },
                    onCancel: {
                        showingReview = false
                        processingResult = nil
                    }
                )
            }
        }
        .onChange(of: selectedPhotos) { _, newItems in
            loadImages(from: newItems)
        }
        .onChange(of: documentURL) { _, newURL in
            if newURL != nil {
                // Document was selected, could process immediately or wait for user
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundColor(themeManager.currentTheme.colors.primary)
            
            Text("Smart Itinerary Import")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            Text("Upload images, documents, or text to automatically create your trip timeline")
                .font(.system(.body, design: .rounded))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 20)
    }
    
    // MARK: - Upload Type Selector
    
    private var uploadTypeSelector: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose Import Method")
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                ForEach(UploadType.allCases, id: \.self) { type in
                    UploadTypeCard(
                        type: type,
                        isSelected: selectedUploadType == type,
                        onTap: { selectedUploadType = type }
                    )
                }
            }
        }
    }
    
    // MARK: - Upload Interface
    
    private var uploadInterface: some View {
        VStack(spacing: 16) {
            switch selectedUploadType {
            case .image:
                imageUploadSection
            case .document:
                documentUploadSection
            case .text:
                textInputSection
            case .url:
                urlInputSection
            }
        }
    }
    
    private var imageUploadSection: some View {
        VStack(spacing: 16) {
            if selectedImages.isEmpty {
                PhotosPicker(
                    selection: $selectedPhotos,
                    maxSelectionCount: 5,
                    matching: .images
                ) {
                    uploadPlaceholder(
                        icon: "camera.fill",
                        title: "Select Images",
                        description: "Choose photos of your itinerary, schedules, or travel documents"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                VStack(spacing: 12) {
                    Text("Selected Images")
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 8) {
                        ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(height: 80)
                                    .cornerRadius(8)
                                    .clipped()
                                
                                Button {
                                    removeImage(at: index)
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .offset(x: 4, y: -4)
                            }
                        }
                        
                        if selectedImages.count < 5 {
                            PhotosPicker(
                                selection: $selectedPhotos,
                                maxSelectionCount: 5 - selectedImages.count,
                                matching: .images
                            ) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(themeManager.currentTheme.colors.surface)
                                    .frame(height: 80)
                                    .overlay(
                                        Image(systemName: "plus")
                                            .font(.system(size: 24))
                                            .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            }
        }
    }
    
    private var documentUploadSection: some View {
        VStack(spacing: 16) {
            if documentURL == nil {
                Button {
                    showingDocumentPicker = true
                } label: {
                    uploadPlaceholder(
                        icon: "doc.text",
                        title: "Select Document",
                        description: "Choose PDF, Excel, Word, or text files containing your itinerary"
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "doc.text")
                            .foregroundColor(themeManager.currentTheme.colors.primary)
                        Text(documentURL?.lastPathComponent ?? "Document")
                            .font(.system(.body, design: .rounded))
                            .foregroundColor(themeManager.currentTheme.colors.text)
                        Spacer()
                        Button("Change") {
                            showingDocumentPicker = true
                        }
                        .foregroundColor(themeManager.currentTheme.colors.primary)
                    }
                    .padding()
                    .background(themeManager.currentTheme.colors.surface)
                    .cornerRadius(8)
                }
            }
        }
    }
    
    private var textInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Paste your itinerary text")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            TextEditor(text: $manualText)
                .font(.system(.body, design: .rounded))
                .frame(minHeight: 120)
                .padding(12)
                .background(themeManager.currentTheme.colors.surface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                )
        }
    }
    
    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enter itinerary URL")
                .font(.system(.subheadline, design: .rounded, weight: .medium))
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            TextField("https://example.com/my-itinerary", text: $urlText)
                .font(.system(.body, design: .rounded))
                .padding(12)
                .background(themeManager.currentTheme.colors.surface)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(themeManager.currentTheme.colors.border, lineWidth: 1)
                )
                .keyboardType(.URL)
                .textContentType(.URL)
        }
    }
    
    // MARK: - Processing Status
    
    private var processingStatusView: some View {
        VStack(spacing: 16) {
            // Animated spinner + progress
            HStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                    .scaleEffect(0.8)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Processing with AI")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundColor(themeManager.currentTheme.colors.text)
                    
                    Text(aiService.currentStatus)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
                
                Spacer()
            }
            
            // Progress bar
            VStack(spacing: 8) {
                ProgressView(value: aiService.processingProgress)
                    .progressViewStyle(LinearProgressViewStyle(tint: themeManager.currentTheme.colors.primary))
                    .frame(height: 6)
                
                HStack {
                    Text("\(Int(aiService.processingProgress * 100))%")
                        .font(.system(.caption, design: .rounded, weight: .medium))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                    
                    Spacer()
                    
                    Text("Please wait...")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                }
            }
        }
        .padding()
        .background(themeManager.currentTheme.colors.primary.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.colors.primary.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Process Button
    
    private var processButton: some View {
        Button {
            processItinerary()
        } label: {
            HStack {
                Image(systemName: "wand.and.rays")
                Text("Process Itinerary")
            }
            .font(.system(.body, design: .rounded, weight: .semibold))
            .foregroundColor(.white)
            .padding()
            .frame(maxWidth: .infinity)
            .background(themeManager.currentTheme.colors.primary)
            .cornerRadius(12)
        }
        .disabled(aiService.isProcessing)
    }
    
    // MARK: - Helper Views
    
    private func uploadPlaceholder(icon: String, title: String, description: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 32))
                .foregroundColor(themeManager.currentTheme.colors.primary)
            
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .semibold))
                .foregroundColor(themeManager.currentTheme.colors.text)
            
            Text(description)
                .font(.system(.body, design: .rounded))
                .foregroundColor(themeManager.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
        .background(themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeManager.currentTheme.colors.border, style: StrokeStyle(lineWidth: 2, dash: [8]))
        )
    }
    
    private func errorView(_ message: String) -> some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            Text(message)
                .font(.system(.body, design: .rounded))
                .foregroundColor(.red)
        }
        .padding()
        .background(Color.red.opacity(0.1))
        .cornerRadius(8)
    }
    
    // MARK: - Computed Properties
    
    private var canProcess: Bool {
        switch selectedUploadType {
        case .image:
            return !selectedImages.isEmpty
        case .document:
            return documentURL != nil
        case .text:
            return !manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .url:
            return !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
    
    // MARK: - Methods
    
    private func loadImages(from items: [PhotosPickerItem]) {
        for item in items {
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run {
                        selectedImages.append(image)
                    }
                }
            }
        }
    }
    
    private func removeImage(at index: Int) {
        selectedImages.remove(at: index)
        if index < selectedPhotos.count {
            selectedPhotos.remove(at: index)
        }
    }
    
    private func processItinerary() {
        error = nil
        
        Task {
            let result: Result<ParsedItinerary, AIItineraryError>
            
            switch selectedUploadType {
            case .image:
                if let firstImage = selectedImages.first {
                    result = await aiService.processImage(firstImage)
                } else {
                    error = "No image selected"
                    return
                }
                
            case .document:
                if let url = documentURL {
                    // Extract text from document and process
                    let extractedText = await extractTextFromDocument(url)
                    result = await aiService.processText(extractedText, sourceType: .pdf)
                } else {
                    error = "No document selected"
                    return
                }
                
            case .text:
                result = await aiService.processText(manualText, sourceType: .text)
                
            case .url:
                // For now, treat URL as text input - could be enhanced to fetch content
                result = await aiService.processText(urlText, sourceType: .url)
            }
            
            switch result {
            case .success(let itinerary):
                processingResult = itinerary
                showingReview = true
            case .failure(let aiError):
                error = aiError.localizedDescription
            }
        }
    }
    
    private func extractTextFromDocument(_ url: URL) async -> String {
        let fileExtension = url.pathExtension.lowercased()
        
        switch fileExtension {
        case "pdf":
            return await extractTextFromPDF(url)
        case "txt", "rtf":
            return await extractTextFromTextFile(url)
        case "csv":
            return await extractTextFromCSV(url)
        default:
            // For other formats (Excel, Word, etc.), return basic file info
            return "Document: \(url.lastPathComponent)\nFile type: \(fileExtension)\nPlease copy and paste the text content manually using the Text input method."
        }
    }
    
    private func extractTextFromPDF(_ url: URL) async -> String {
        guard url.startAccessingSecurityScopedResource() else {
            return "Unable to access PDF file"
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        guard let pdfDocument = PDFDocument(url: url) else {
            return "Unable to read PDF file"
        }
        
        var extractedText = ""
        let pageCount = pdfDocument.pageCount
        
        for i in 0..<pageCount {
            if let page = pdfDocument.page(at: i),
               let pageText = page.string {
                extractedText += pageText + "\n\n"
            }
        }
        
        return extractedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func extractTextFromTextFile(_ url: URL) async -> String {
        guard url.startAccessingSecurityScopedResource() else {
            return "Unable to access text file"
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            return content.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error reading text file: \(error.localizedDescription)"
        }
    }
    
    private func extractTextFromCSV(_ url: URL) async -> String {
        guard url.startAccessingSecurityScopedResource() else {
            return "Unable to access CSV file"
        }
        defer { url.stopAccessingSecurityScopedResource() }
        
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            // Convert CSV to more readable format
            let lines = content.components(separatedBy: .newlines)
            var formattedText = ""
            
            for (index, line) in lines.enumerated() {
                if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                    let fields = line.components(separatedBy: ",")
                    if index == 0 {
                        formattedText += "Headers: " + fields.joined(separator: " | ") + "\n\n"
                    } else {
                        formattedText += "Row \(index): " + fields.joined(separator: " | ") + "\n"
                    }
                }
            }
            
            return formattedText.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return "Error reading CSV file: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Processing Overlay
    
    private var processingOverlay: some View {
        VStack(spacing: 20) {
            Spacer()
            
            VStack(spacing: 16) {
                // Large spinner
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.5)
                
                VStack(spacing: 8) {
                    Text("AI Processing")
                        .font(.system(.title3, design: .rounded, weight: .semibold))
                        .foregroundColor(.white)
                    
                    Text(aiService.currentStatus)
                        .font(.system(.body, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }
                
                // Progress indicator
                VStack(spacing: 8) {
                    ProgressView(value: aiService.processingProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: .white))
                        .frame(width: 200, height: 4)
                    
                    Text("\(Int(aiService.processingProgress * 100))% Complete")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(24)
            .background(Color.black.opacity(0.8))
            .cornerRadius(16)
            .shadow(radius: 20)
            
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.4))
        .ignoresSafeArea()
    }
}

// MARK: - Upload Type

enum UploadType: String, CaseIterable {
    case image = "image"
    case document = "document"
    case text = "text"
    case url = "url"
    
    var displayName: String {
        switch self {
        case .image: return "Images"
        case .document: return "Documents"
        case .text: return "Text"
        case .url: return "URL"
        }
    }
    
    var icon: String {
        switch self {
        case .image: return "photo"
        case .document: return "doc.text"
        case .text: return "text.alignleft"
        case .url: return "link"
        }
    }
    
    var description: String {
        switch self {
        case .image: return "Upload photos of itineraries, schedules, confirmations"
        case .document: return "Import PDF, Excel, Word files"
        case .text: return "Paste text directly"
        case .url: return "Import from web links"
        }
    }
}

// MARK: - Upload Type Card

struct UploadTypeCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    let type: UploadType
    let isSelected: Bool
    let onTap: () -> Void
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: type.icon)
                .font(.system(size: 24))
                .foregroundColor(isSelected ? .white : themeManager.currentTheme.colors.primary)
            
            Text(type.displayName)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundColor(isSelected ? .white : themeManager.currentTheme.colors.text)
            
            Text(type.description)
                .font(.system(.caption, design: .rounded))
                .foregroundColor(isSelected ? .white.opacity(0.8) : themeManager.currentTheme.colors.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding()
        .frame(maxWidth: .infinity, minHeight: 100)
        .background(isSelected ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.surface)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isSelected ? themeManager.currentTheme.colors.primary : themeManager.currentTheme.colors.border, lineWidth: 2)
        )
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Document Picker

struct DocumentPicker: UIViewControllerRepresentable {
    @Binding var documentURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [
            .pdf,
            .text,
            .commaSeparatedText,
            UTType("com.microsoft.excel.xls")!,
            UTType("org.openxmlformats.spreadsheetml.sheet")!,
            .rtf,
            .plainText
        ])
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: DocumentPicker
        
        init(_ parent: DocumentPicker) {
            self.parent = parent
        }
        
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.documentURL = urls.first
            parent.dismiss()
        }
    }
}

#Preview {
    UploadItineraryView { _ in
        // Handle processed itinerary
    }
    .environmentObject(ThemeManager())
}