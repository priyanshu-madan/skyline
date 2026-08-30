//
//  BoardingPassBarcodeService.swift
//  SkyLine
//
//  Reads a boarding pass the way the airline intended it to be read: by
//  decoding the PDF417 (or Aztec) barcode printed on it and parsing the IATA
//  BCBP payload inside.
//
//  This replaces uploading a photograph of the pass - passenger name, PNR,
//  frequent flyer number and all - to a third-party router and asking a vision
//  model to guess. Everything here runs on the device, ships no model, needs no
//  key, and finishes in milliseconds.
//
//  Division of labour, and it is not negotiable:
//
//    From the BARCODE (checksummed, exact): passenger name, PNR, origin,
//    destination, operating carrier, flight number, date of flight, cabin,
//    seat, check-in sequence, passenger status.
//
//    From TEXT RECOGNITION (printed, heuristic): gate, terminal, boarding time,
//    departure and arrival times, airline and city display names. BCBP does not
//    encode any of these - see `BoardingPassPrintedFields`.
//
//  A printed guess may never overwrite a barcode value. `merge` is the only
//  place the two meet and it takes the barcode's side by construction.
//
//  On the text half: the owner has said Vision text recognition is not accurate
//  enough to EXTRACT a flight, and it is not used for that - a pass with no
//  readable barcode goes to the remote fallback in `UnifiedBoardingPassService`
//  instead. What survives here is only the reading of labelled values off a
//  pass whose barcode already decoded, and it is behind
//  `UnifiedBoardingPassService.barcodeEnrichment` so the choice is one edit.
//

import Foundation
import UIKit
import Vision

// MARK: - Service

final class BoardingPassBarcodeService: ObservableObject {

    static let shared = BoardingPassBarcodeService()

    @Published var isProcessing = false
    @Published var lastError: String?

    private init() {}

    /// Every symbology an IATA boarding pass has ever been printed with.
    ///
    /// PDF417 is the standard. Aztec is used by a number of European carriers
    /// and by Apple Wallet. QR and DataMatrix show up on a few airlines' mobile
    /// passes. The BCBP payload inside is identical in all four.
    private static let symbologies: [BarcodeSymbology] = [.pdf417, .aztec, .qr, .dataMatrix]

    // MARK: Outcome

    /// What a scan found, including what it rejected.
    ///
    /// The counts exist so that a caller can distinguish "no barcode in this
    /// photo" from "a barcode that is not a boarding pass" from "a boarding
    /// pass whose payload is malformed". A bare `nil` cannot tell them apart,
    /// and the difference decides whether retrying is worth anything.
    struct ScanOutcome {
        /// The parsed pass, if exactly one payload parsed.
        let boardingPass: BCBPBoardingPass?
        /// Printed-only fields recovered from text recognition.
        let printedFields: BoardingPassPrintedFields
        /// How many barcodes decoded to a string at all.
        let barcodesFound: Int
        /// Why each candidate payload was rejected. Never contains the payload
        /// itself: those bytes are the passenger's name and record locator.
        let rejections: [String]
        /// Lines of recognised text. Retained for the printed-field pass only.
        let recognisedLineCount: Int
        /// `true` when the iOS 26 single-pass document request produced the
        /// result, `false` when the discrete barcode/text requests did.
        let usedRecognizeDocuments: Bool

        /// Every barcode detector on this platform refused to run.
        ///
        /// This is not the same as "there is no barcode in the photo", and the
        /// difference matters: it decides whether falling back to a remote
        /// model is warranted or whether the app is simply blind here. It is
        /// `true` on the iOS Simulator, where the barcode detector is absent -
        /// see `scan`.
        let detectorUnavailable: Bool

        /// What each detector said when it refused. Never a payload.
        let detectorErrors: [String]

        var foundBoardingPass: Bool { boardingPass != nil }
    }

    // MARK: Public interface

    /// Decode and parse, returning the app's boarding pass model.
    ///
    /// - Parameters:
    ///   - referenceDate: "now", for resolving the barcode's yearless Julian
    ///     flight date. Injected so a test can pin it.
    ///   - includePrintedFields: whether to fill gate, terminal, times and
    ///     display names from recognised text. The caller decides, because that
    ///     is a policy question - see `UnifiedBoardingPassService.barcodeEnrichment` -
    ///     and not one this service should answer on its own.
    func parseImage(
        _ image: UIImage,
        referenceDate: Date = Date(),
        includePrintedFields: Bool = true
    ) async -> BoardingPassData? {
        await MainActor.run {
            isProcessing = true
            lastError = nil
        }
        defer { Task { @MainActor in self.isProcessing = false } }

        let outcome = await scan(image, referenceDate: referenceDate)

        guard let pass = outcome.boardingPass else {
            let message: String
            if outcome.detectorUnavailable {
                message = "No barcode detector available on this platform"
            } else if outcome.barcodesFound == 0 {
                message = "No barcode found in the image"
            } else if let first = outcome.rejections.first {
                message = "Barcode found but not a boarding pass: \(first)"
            } else {
                message = "Barcode found but could not be read"
            }
            await MainActor.run { self.lastError = message }
            print("📵 Barcode: \(message)")
            return nil
        }

        return Self.merge(
            barcode: pass,
            printed: includePrintedFields ? outcome.printedFields : BoardingPassPrintedFields()
        )
    }

    /// Full scan: barcodes plus text, in as few Vision passes as the OS allows.
    ///
    /// Three detectors are attempted in order because they are three different
    /// pieces of the OS with three different failure modes, and barcode
    /// decoding is the entire point of this service:
    ///
    ///   1. `RecognizeDocumentsRequest` (iOS 26) - codes and text in one pass.
    ///   2. `DetectBarcodesRequest` (iOS 18 Swift API) - more aggressive on a
    ///      photo where the pass is one object among many.
    ///   3. `VNDetectBarcodesRequest` - the mature ObjC-era detector.
    ///
    /// Measured on the iOS 26.0 Simulator (iPhone 17 Pro), all three fail:
    /// `DetectBarcodesRequest` throws `operationFailed("Failed to create
    /// barcode detector.")`, `VNDetectBarcodesRequest` throws "Could not create
    /// inference context", and `RecognizeDocumentsRequest` returns a document
    /// with zero barcodes for a symbol that macOS decodes correctly. Barcode
    /// scanning therefore cannot be exercised on a simulator at all; that is
    /// what `detectorUnavailable` is for, and it is why the round-trip test
    /// needs a device.
    func scan(_ image: UIImage, referenceDate: Date = Date()) async -> ScanOutcome {
        guard let cgImage = Self.cgImage(from: image) else {
            return ScanOutcome(
                boardingPass: nil,
                printedFields: BoardingPassPrintedFields(),
                barcodesFound: 0,
                rejections: ["Image could not be converted to a bitmap"],
                recognisedLineCount: 0,
                usedRecognizeDocuments: false,
                detectorUnavailable: false,
                detectorErrors: []
            )
        }
        let orientation = Self.cgOrientation(from: image.imageOrientation)

        var payloads: [DecodedBarcode] = []
        var lines: [String] = []
        var usedRecognizeDocuments = false
        var detectorErrors: [String] = []

        // Verified present in the iOS 26.0 SDK as `Vision.RecognizeDocumentsRequest`
        // with `barcodeDetectionOptions.symbologies` and `document.barcodes`.
        // The availability check is real rather than decorative: the type is
        // annotated `@available(iOS 26.0, *)` and the project's floor could drop.
        if #available(iOS 26.0, *) {
            do {
                let raw = try await Self.scanWithDocuments(cgImage, orientation: orientation)
                payloads = raw.payloads
                lines = raw.lines
                usedRecognizeDocuments = true
            } catch {
                detectorErrors.append("RecognizeDocumentsRequest: \(error.localizedDescription)")
            }
        }

        if payloads.isEmpty {
            do {
                let raw = try await Self.scanWithDiscreteRequests(cgImage, orientation: orientation)
                payloads = raw.payloads
                if lines.isEmpty { lines = raw.lines }
            } catch {
                detectorErrors.append("DetectBarcodesRequest: \(error.localizedDescription)")
            }
        }

        if payloads.isEmpty {
            do {
                payloads = try Self.scanWithLegacyRequest(cgImage, orientation: orientation)
            } catch {
                detectorErrors.append("VNDetectBarcodesRequest: \(error.localizedDescription)")
            }
        }

        // Nothing decoded AND something refused to run: the platform is blind
        // here, which is a different report from "no barcode in this photo".
        let detectorUnavailable = payloads.isEmpty && !detectorErrors.isEmpty

        let (pass, rejections) = Self.firstBoardingPass(in: payloads, referenceDate: referenceDate)

        let printed = BoardingPassPrintedFieldReader.extract(
            from: lines,
            originCode: pass?.primaryLeg?.origin,
            destinationCode: pass?.primaryLeg?.destination
        )

        if let pass {
            // Never the payload, never the passenger. Enough to debug a bad
            // scan and nothing that should not be in a log.
            print("🎫 Barcode: parsed BCBP \(pass.legs.count) leg(s), version \(pass.versionNumber ?? "-"), id \(pass.stableID)")
        } else if detectorUnavailable {
            print("📵 Barcode: no barcode detector on this platform - \(detectorErrors.joined(separator: "; "))")
        }

        return ScanOutcome(
            boardingPass: pass,
            printedFields: printed,
            barcodesFound: payloads.count,
            rejections: rejections,
            recognisedLineCount: lines.count,
            usedRecognizeDocuments: usedRecognizeDocuments,
            detectorUnavailable: detectorUnavailable,
            detectorErrors: detectorErrors
        )
    }

    // MARK: - Merge

    /// Fills `BoardingPassData` from the barcode, then adds only the fields the
    /// barcode cannot carry.
    ///
    /// Static and pure so the precedence rule is testable without a camera.
    static func merge(
        barcode: BCBPBoardingPass,
        printed: BoardingPassPrintedFields
    ) -> BoardingPassData {

        var data = BoardingPassData()

        // --- Barcode. Authoritative.
        data.passengerName = barcode.passengerName

        if let leg = barcode.primaryLeg {
            data.flightNumber = leg.flightDesignator
            data.departureCode = leg.origin
            data.arrivalCode = leg.destination
            data.departureDate = leg.flightDate
            data.seat = leg.seatNumber
            data.confirmationCode = leg.operatingCarrierPNR
        }

        // --- Printed. Only ever fills what BCBP leaves empty.
        data.gate = printed.gate
        data.terminal = printed.terminal
        data.departureTime = printed.departureTime
        data.arrivalTime = printed.arrivalTime
        data.departureCity = printed.departureCity
        data.arrivalCity = printed.arrivalCity

        // The airline's display name is printed, not encoded. Falling back to
        // the two-letter designator is deliberate: `WY` is right, and a name
        // the OCR invented is not.
        data.airline = printed.airlineName ?? barcode.primaryLeg?.operatingCarrier

        // An arrival clock earlier than the departure clock means the flight
        // lands on the next day. This is an inference from two printed values,
        // so it is only made when both are present, and it ignores timezones
        // because the pass does not carry any.
        if let departureDate = data.departureDate,
           let departureTime = printed.departureTime,
           let arrivalTime = printed.arrivalTime {
            let landsNextDay = arrivalTime < departureTime
            data.arrivalDate = landsNextDay
                ? BCBPParser.calendar.date(byAdding: .day, value: 1, to: departureDate)
                : departureDate
        }

        return data
    }

    /// Reasserts every barcode-derived field over a result produced by any
    /// other method.
    ///
    /// The chain in `UnifiedBoardingPassService` short-circuits on a successful
    /// barcode, so this is only reached when the barcode read something the
    /// downstream consumer still considered incomplete. It exists so that "a
    /// language model may never overwrite a checksummed value" is enforced by
    /// code rather than by the order of a `for` loop.
    static func overlay(barcode: BoardingPassData, onto other: BoardingPassData) -> BoardingPassData {
        var merged = other

        // Barcode wins outright.
        if let value = barcode.flightNumber { merged.flightNumber = value }
        if let value = barcode.departureCode { merged.departureCode = value }
        if let value = barcode.arrivalCode { merged.arrivalCode = value }
        if let value = barcode.departureDate { merged.departureDate = value }
        if let value = barcode.seat { merged.seat = value }
        if let value = barcode.confirmationCode { merged.confirmationCode = value }
        if let value = barcode.passengerName { merged.passengerName = value }

        // Printed-only fields: keep whatever is there, fill the gaps.
        merged.gate = merged.gate ?? barcode.gate
        merged.terminal = merged.terminal ?? barcode.terminal
        merged.departureTime = merged.departureTime ?? barcode.departureTime
        merged.arrivalTime = merged.arrivalTime ?? barcode.arrivalTime
        merged.departureCity = merged.departureCity ?? barcode.departureCity
        merged.arrivalCity = merged.arrivalCity ?? barcode.arrivalCity
        merged.airline = merged.airline ?? barcode.airline

        return merged
    }

    // MARK: - Payload selection

    /// A decoded barcode, before anyone has decided what it is.
    struct DecodedBarcode {
        let payload: String
        /// Ranking only. PDF417 and Aztec are what boarding passes use, so a
        /// stray QR code on the same photo never wins.
        let rank: Int
    }

    struct RawScan {
        let payloads: [DecodedBarcode]
        let lines: [String]
        let usedRecognizeDocuments: Bool
    }

    /// Parses candidates in symbology order and returns the first real pass.
    static func firstBoardingPass(
        in payloads: [DecodedBarcode],
        referenceDate: Date
    ) -> (BCBPBoardingPass?, [String]) {

        var rejections: [String] = []

        for candidate in payloads.sorted(by: { $0.rank < $1.rank }) {
            guard BCBPParser.looksLikeBCBP(candidate.payload) else {
                // Not even the right shape - a Wi-Fi QR, a URL, a bag tag.
                rejections.append("payload is not a BCBP payload")
                continue
            }
            do {
                return (try BCBPParser.parse(candidate.payload, referenceDate: referenceDate), rejections)
            } catch let error as BCBPParseError {
                // The description names the field, never its value.
                rejections.append(error.description)
            } catch {
                rejections.append("unexpected parse failure")
            }
        }
        return (nil, rejections)
    }

    private static func rank(for symbology: BarcodeSymbology) -> Int {
        switch symbology {
        case .pdf417: return 0
        case .aztec: return 1
        case .dataMatrix: return 2
        case .qr: return 3
        default: return 4
        }
    }

    // MARK: - Vision

    @available(iOS 26.0, *)
    private static func scanWithDocuments(
        _ cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> RawScan {

        var request = RecognizeDocumentsRequest()
        request.barcodeDetectionOptions.enabled = true
        request.barcodeDetectionOptions.symbologies = symbologies
        // A boarding pass is codes and abbreviations. Language correction turns
        // `MCT` into `MOT` and `ETD` into `ET`.
        request.textRecognitionOptions.useLanguageCorrection = false

        let handler = ImageRequestHandler(cgImage, orientation: orientation)
        let documents = try await handler.perform(request)

        var payloads: [DecodedBarcode] = []
        var lines: [String] = []

        for document in documents {
            for barcode in document.document.barcodes {
                guard let payload = barcode.payloadString, !payload.isEmpty else { continue }
                payloads.append(DecodedBarcode(payload: payload, rank: rank(for: barcode.symbology)))
            }
            lines.append(contentsOf: recognisedLines(from: document.document))
        }

        return RawScan(payloads: payloads, lines: lines, usedRecognizeDocuments: true)
    }

    @available(iOS 26.0, *)
    private static func recognisedLines(from container: DocumentObservation.Container) -> [String] {
        var lines = container.text.lines.compactMap { $0.topCandidates(1).first?.string }
        if lines.isEmpty {
            lines = container.text.transcript
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
        return lines
    }

    private static func scanWithDiscreteRequests(
        _ cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) async throws -> RawScan {

        let handler = ImageRequestHandler(cgImage, orientation: orientation)

        var barcodeRequest = DetectBarcodesRequest()
        barcodeRequest.symbologies = symbologies
        let barcodes = try await handler.perform(barcodeRequest)

        let payloads: [DecodedBarcode] = barcodes.compactMap { barcode in
            guard let payload = barcode.payloadString, !payload.isEmpty else { return nil }
            return DecodedBarcode(payload: payload, rank: rank(for: barcode.symbology))
        }

        // Text is a separate request and a separate failure: a barcode that
        // read fine must not be thrown away because OCR fell over.
        var lines: [String] = []
        do {
            var textRequest = RecognizeTextRequest()
            textRequest.recognitionLevel = .accurate
            textRequest.usesLanguageCorrection = false
            let observations = try await handler.perform(textRequest)
            lines = observations.compactMap { $0.topCandidates(1).first?.string }
        } catch {
            print("📵 Barcode: text recognition failed (\(error.localizedDescription)); barcode fields only")
        }

        return RawScan(payloads: payloads, lines: lines, usedRecognizeDocuments: false)
    }

    /// The pre-Swift-Vision detector.
    ///
    /// Kept as a last resort rather than deleted: it is a different code path
    /// from `DetectBarcodesRequest` and has a decade of hardening behind it. A
    /// boarding pass that decodes here and nowhere else is still a decoded
    /// boarding pass.
    private static func scanWithLegacyRequest(
        _ cgImage: CGImage,
        orientation: CGImagePropertyOrientation
    ) throws -> [DecodedBarcode] {

        let request = VNDetectBarcodesRequest()
        request.symbologies = [.pdf417, .aztec, .qr, .dataMatrix]

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: orientation, options: [:])
        try handler.perform([request])

        return (request.results ?? []).compactMap { observation in
            guard let payload = observation.payloadStringValue, !payload.isEmpty else { return nil }
            return DecodedBarcode(payload: payload, rank: legacyRank(for: observation.symbology))
        }
    }

    private static func legacyRank(for symbology: VNBarcodeSymbology) -> Int {
        switch symbology {
        case .pdf417: return 0
        case .aztec: return 1
        case .dataMatrix: return 2
        case .qr: return 3
        default: return 4
        }
    }

    // MARK: - Image plumbing

    /// A `UIImage` from the photo picker is usually CGImage-backed, but one
    /// built from Core Image filters is not, and `Vision` needs a bitmap.
    private static func cgImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage { return cgImage }
        if let ciImage = image.ciImage {
            return CIContext().createCGImage(ciImage, from: ciImage.extent)
        }
        return nil
    }

    /// A camera photo carries its rotation in metadata, not in its pixels.
    /// Handing Vision the bitmap without the orientation means scanning a
    /// sideways boarding pass, which PDF417 detection tolerates far less well
    /// than text recognition does.
    private static func cgOrientation(from orientation: UIImage.Orientation) -> CGImagePropertyOrientation {
        switch orientation {
        case .up: return .up
        case .down: return .down
        case .left: return .left
        case .right: return .right
        case .upMirrored: return .upMirrored
        case .downMirrored: return .downMirrored
        case .leftMirrored: return .leftMirrored
        case .rightMirrored: return .rightMirrored
        @unknown default: return .up
        }
    }
}
