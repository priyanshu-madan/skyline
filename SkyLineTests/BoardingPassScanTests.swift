//
//  BoardingPassScanTests.swift
//  SkyLineTests
//
//  Covers the two halves of a scan meeting each other:
//
//    - `BoardingPassPrintedFieldReader`, which reads the fields BCBP does not
//      encode out of on-device text recognition.
//    - `BoardingPassBarcodeService.merge` / `.overlay`, where the barcode's
//      checksummed values and the OCR's guesses are combined. The barcode wins,
//      and that is what most of these tests are about.
//
//  No Vision types appear here: everything under test is pure and static, so
//  the rules can be checked without a camera or a fixture image.
//

import CoreImage
import Foundation
import Testing
import UIKit
@testable import SkyLine

// MARK: - Helpers

private func pad(_ value: String, _ width: Int) -> String {
    precondition(value.count <= width)
    return value.padding(toLength: width, withPad: " ", startingAt: 0)
}

/// A minimal mandatory-only payload: `M`, one leg, name, e-ticket, then the
/// 37-character leg block.
private func syntheticPayload(
    name: String = "TESTER/ALEX",
    pnr: String = "ABC123",
    origin: String = "MCT",
    destination: String = "ZRH",
    carrier: String = "WY",
    flightNumber: String = "0153",
    julianDay: String = "153",
    seat: String = "012A"
) -> String {
    "M1" + pad(name, 20) + "E"
        + pad(pnr, 7) + pad(origin, 3) + pad(destination, 3) + pad(carrier, 3)
        + pad(flightNumber, 5) + pad(julianDay, 3) + "Y" + pad(seat, 4)
        + pad("0025", 5) + "3" + "00"
}

private let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
}()

private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
    utc.date(from: DateComponents(year: year, month: month, day: day))!
}

// MARK: - Printed fields

@Suite("Printed boarding pass fields")
struct BoardingPassPrintedFieldTests {

    @Test("Gate, terminal and times are read from labelled lines")
    func labelledFields() {
        let lines = [
            "OMAN AIR",
            "MUSCAT MCT",
            "ZURICH ZRH",
            "GATE A12",
            "TERMINAL 1",
            "BOARDING 08:35",
            "DEPARTS 09:05",
            "ARRIVES 13:40"
        ]

        let fields = BoardingPassPrintedFieldReader.extract(
            from: lines,
            originCode: "MCT",
            destinationCode: "ZRH"
        )

        #expect(fields.gate == "A12")
        #expect(fields.terminal == "1")
        #expect(fields.boardingTime == "08:35")
        #expect(fields.departureTime == "09:05")
        #expect(fields.arrivalTime == "13:40")
        #expect(fields.airlineName == "OMAN AIR")
        #expect(fields.departureCity == "MUSCAT")
        #expect(fields.arrivalCity == "ZURICH")
    }

    @Test("A label above its value is read as well as a label beside it")
    func labelAboveValue() {
        let lines = ["GATE", "B7", "TERMINAL", "3", "BOARDING TIME", "18:20"]
        let fields = BoardingPassPrintedFieldReader.extract(from: lines)

        #expect(fields.gate == "B7")
        #expect(fields.terminal == "3")
        #expect(fields.boardingTime == "18:20")
    }

    @Test("GATE CLOSES is a time, not a gate")
    func gateClosesIsNotAGate() {
        // `GATE CLOSES 14:05` read as a gate produces gate "14". The word
        // CLOSE has to lose to the time labels.
        let fields = BoardingPassPrintedFieldReader.extract(from: ["GATE CLOSES 14:05"])
        #expect(fields.boardingTime == "14:05")
        #expect(fields.gate == nil)
    }

    @Test("Times normalise to 24-hour HH:mm")
    func timeNormalisation() {
        #expect(BoardingPassPrintedFieldReader.time("09:05") == "09:05")
        #expect(BoardingPassPrintedFieldReader.time("9:05") == "09:05")
        #expect(BoardingPassPrintedFieldReader.time("0905") == "09:05")
        #expect(BoardingPassPrintedFieldReader.time("09.05") == "09:05")
        #expect(BoardingPassPrintedFieldReader.time("2:25 PM") == "14:25")
        #expect(BoardingPassPrintedFieldReader.time("12:15 AM") == "00:15")
        #expect(BoardingPassPrintedFieldReader.time("25:99") == nil)
        #expect(BoardingPassPrintedFieldReader.time("SEAT 12A") == nil)
    }

    @Test("A gate value matches the app's own gate pattern")
    func gateShape() {
        #expect(BoardingPassPrintedFieldReader.gate("A12") == "A12")
        #expect(BoardingPassPrintedFieldReader.gate("7") == "7")
        #expect(BoardingPassPrintedFieldReader.gate("12B") == "12B")
        // Not a gate: no digits at all, or far too long.
        #expect(BoardingPassPrintedFieldReader.gate("BOARDING") == nil)
        #expect(BoardingPassPrintedFieldReader.gate("A1234") == nil)
    }

    @Test("Nothing is invented from a card with no labels")
    func noLabelsMeansNoFields() {
        // The important half of a heuristic: silence when it does not know.
        let fields = BoardingPassPrintedFieldReader.extract(
            from: ["SKYLINE", "PRIORITY", "SEQ 0025", "12A"],
            originCode: "MCT",
            destinationCode: "ZRH"
        )
        #expect(fields.isEmpty)
    }

    @Test("A route line is not mistaken for a city name")
    func routeLineIsNotACity() {
        let fields = BoardingPassPrintedFieldReader.extract(
            from: ["MCT - ZRH", "FLIGHT WY 153"],
            originCode: "MCT",
            destinationCode: "ZRH"
        )
        #expect(fields.departureCity == nil)
        #expect(fields.arrivalCity == nil)
    }

    @Test("An airport line is never read as the airline")
    func airportIsNotAnAirline() {
        // AIRPORT is on the exclusion list, so the airport's own name loses.
        #expect(BoardingPassPrintedFieldReader.airlineName(in: "MUSCAT INTERNATIONAL AIRPORT") == nil)
        #expect(BoardingPassPrintedFieldReader.airlineName(in: "OMAN AIR") == "OMAN AIR")
        #expect(BoardingPassPrintedFieldReader.airlineName(in: "SWISS INTERNATIONAL AIR LINES") == "SWISS INTERNATIONAL AIR LINES")
        #expect(BoardingPassPrintedFieldReader.airlineName(in: "BRITISH AIRWAYS") == "BRITISH AIRWAYS")
        // A line with a number on it is a seat, a time or a flight, not a name.
        #expect(BoardingPassPrintedFieldReader.airlineName(in: "WY 153 AIR") == nil)
    }
}

// MARK: - Merge

@Suite("Barcode and printed text merge")
struct BoardingPassMergeTests {

    @Test("Barcode fields fill the model and printed fields fill only the gaps")
    func mergeFillsBothHalves() throws {
        let pass = try BCBPParser.parse(syntheticPayload(), referenceDate: day(2026, 6, 1))
        var printed = BoardingPassPrintedFields()
        printed.gate = "A12"
        printed.terminal = "1"
        printed.departureTime = "09:05"
        printed.arrivalTime = "13:40"
        printed.airlineName = "Oman Air"
        printed.departureCity = "Muscat"
        printed.arrivalCity = "Zurich"

        let data = BoardingPassBarcodeService.merge(barcode: pass, printed: printed)

        // From the barcode.
        #expect(data.flightNumber == "WY153")
        #expect(data.departureCode == "MCT")
        #expect(data.arrivalCode == "ZRH")
        #expect(data.seat == "12A")
        #expect(data.confirmationCode == "ABC123")
        #expect(data.passengerName == "ALEX TESTER")
        #expect(data.departureDate == day(2026, 6, 2))

        // From text recognition.
        #expect(data.gate == "A12")
        #expect(data.terminal == "1")
        #expect(data.departureTime == "09:05")
        #expect(data.arrivalTime == "13:40")
        #expect(data.airline == "Oman Air")
        #expect(data.departureCity == "Muscat")
        #expect(data.arrivalCity == "Zurich")

        #expect(data.isValid)
    }

    @Test("With no printed airline name the carrier designator is used")
    func airlineFallsBackToCarrierCode() throws {
        let pass = try BCBPParser.parse(syntheticPayload(), referenceDate: day(2026, 6, 1))
        let data = BoardingPassBarcodeService.merge(barcode: pass, printed: BoardingPassPrintedFields())

        // `WY` is right. A name the OCR invented would not be.
        #expect(data.airline == "WY")
        #expect(data.gate == nil)
        #expect(data.departureTime == nil)
    }

    @Test("An arrival clock before the departure clock lands on the next day")
    func overnightArrival() throws {
        let pass = try BCBPParser.parse(syntheticPayload(), referenceDate: day(2026, 6, 1))
        var printed = BoardingPassPrintedFields()
        printed.departureTime = "22:40"
        printed.arrivalTime = "06:15"

        let data = BoardingPassBarcodeService.merge(barcode: pass, printed: printed)
        #expect(data.departureDate == day(2026, 6, 2))
        #expect(data.arrivalDate == day(2026, 6, 3))
    }

    @Test("No arrival date is invented when the times are not printed")
    func noArrivalDateWithoutTimes() throws {
        let pass = try BCBPParser.parse(syntheticPayload(), referenceDate: day(2026, 6, 1))
        let data = BoardingPassBarcodeService.merge(barcode: pass, printed: BoardingPassPrintedFields())
        #expect(data.arrivalDate == nil)
    }

    @Test("A language model may not overwrite a checksummed value")
    func barcodeOverridesModelOutput() throws {
        let pass = try BCBPParser.parse(syntheticPayload(), referenceDate: day(2026, 6, 1))
        let barcodeData = BoardingPassBarcodeService.merge(barcode: pass, printed: BoardingPassPrintedFields())

        // What a vision model produced from the same photo: plausible, and
        // wrong in every field the barcode already knows.
        var modelData = BoardingPassData()
        modelData.flightNumber = "WY1S3"
        modelData.departureCode = "MTC"
        modelData.arrivalCode = "ZHR"
        modelData.seat = "12B"
        modelData.confirmationCode = "A8C123"
        modelData.passengerName = "ALEC TESTER"
        modelData.gate = "A12"
        modelData.departureTime = "09:05"

        let merged = BoardingPassBarcodeService.overlay(barcode: barcodeData, onto: modelData)

        #expect(merged.flightNumber == "WY153")
        #expect(merged.departureCode == "MCT")
        #expect(merged.arrivalCode == "ZRH")
        #expect(merged.seat == "12A")
        #expect(merged.confirmationCode == "ABC123")
        #expect(merged.passengerName == "ALEX TESTER")
        // The model keeps the fields the barcode cannot carry.
        #expect(merged.gate == "A12")
        #expect(merged.departureTime == "09:05")
    }

    @Test("The best-ranked barcode in a photo is the one that is parsed")
    func symbologyRanking() {
        // A photo of a pass on a table can catch a Wi-Fi QR code, a loyalty
        // card and the boarding pass. Only one of them is a boarding pass.
        let candidates = [
            BoardingPassBarcodeService.DecodedBarcode(payload: "https://example.com/wifi", rank: 3),
            BoardingPassBarcodeService.DecodedBarcode(payload: syntheticPayload(), rank: 0)
        ]

        let (pass, rejections) = BoardingPassBarcodeService.firstBoardingPass(
            in: candidates,
            referenceDate: day(2026, 6, 1)
        )

        #expect(pass?.primaryLeg?.origin == "MCT")
        // The QR code was ranked below PDF417, so it was never even considered.
        #expect(rejections.isEmpty)
    }

    @Test("A photo with no boarding pass barcode reports why, without leaking the payload")
    func rejectionsExplainThemselves() {
        let candidates = [
            BoardingPassBarcodeService.DecodedBarcode(payload: "https://example.com/wifi", rank: 3)
        ]
        let (pass, rejections) = BoardingPassBarcodeService.firstBoardingPass(
            in: candidates,
            referenceDate: day(2026, 6, 1)
        )

        #expect(pass == nil)
        #expect(rejections.count == 1)
        // The reason names the shape, never the bytes: a real payload is a
        // passenger's name and record locator.
        #expect(rejections[0].contains("example.com") == false)
    }
}

// MARK: - End to end through Vision

@Suite("Barcode scanning through Vision")
struct BoardingPassBarcodeScanTests {

    /// Renders a payload as a real PDF417 symbol.
    ///
    /// This is the only way to prove the Vision half works rather than merely
    /// compiles: the generator and the detector are independent pieces of the
    /// OS, so a round trip through both is a genuine check.
    private func pdf417Image(from payload: String, scale: CGFloat = 8) -> UIImage? {
        guard let data = payload.data(using: .ascii),
              let filter = CIFilter(name: "CIPDF417BarcodeGenerator") else { return nil }
        filter.setValue(data, forKey: "inputMessage")
        guard let output = filter.outputImage else { return nil }

        // Vision needs the symbol at a usable size; the generator emits one
        // pixel per module.
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    @Test("A rendered PDF417 boarding pass round-trips through Vision")
    func pdf417RoundTrip() async throws {
        let image = try #require(pdf417Image(from: syntheticPayload()))

        let outcome = await BoardingPassBarcodeService.shared.scan(image, referenceDate: day(2026, 6, 1))

        // MEASURED, not assumed: on the iOS 26.0 Simulator every barcode
        // detector refuses to run. `DetectBarcodesRequest` throws
        // `operationFailed("Failed to create barcode detector.")`,
        // `VNDetectBarcodesRequest` throws "Could not create inference
        // context", and `RecognizeDocumentsRequest` returns a document with
        // zero barcodes for a symbol macOS decodes correctly. The same payload
        // and the same generator round-trip fine on macOS.
        //
        // So this assertion can only run on hardware. Skipping is honest;
        // asserting a decode that the platform cannot perform would be a
        // permanently red test that everybody learns to ignore.
        guard !outcome.detectorUnavailable else {
            #expect(outcome.boardingPass == nil)
            #expect(outcome.detectorErrors.isEmpty == false)
            return
        }

        #expect(outcome.barcodesFound >= 1)
        let pass = try #require(outcome.boardingPass, "Vision did not decode the generated PDF417")
        #expect(pass.primaryLeg?.flightDesignator == "WY153")
        #expect(pass.primaryLeg?.origin == "MCT")
        #expect(pass.primaryLeg?.destination == "ZRH")
        #expect(pass.primaryLeg?.seatNumber == "12A")
        #expect(pass.passengerName == "ALEX TESTER")
    }

    @Test("An image with no barcode reports that, rather than failing silently")
    func noBarcodeInImage() async throws {
        // A plain white rectangle: no barcode, no text.
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 400, height: 200))
        let blank = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 400, height: 200))
        }

        let outcome = await BoardingPassBarcodeService.shared.scan(blank, referenceDate: day(2026, 6, 1))

        // Whether the detector ran and found nothing or could not run at all,
        // the service reports no boarding pass rather than throwing or hanging.
        // The caller then falls back, which is the behaviour that matters.
        #expect(outcome.barcodesFound == 0)
        #expect(outcome.foundBoardingPass == false)
    }
}

// MARK: - Default configuration

@Suite("Boarding pass parsing defaults")
struct BoardingPassParsingDefaultTests {

    @Test("The remote parser is the fallback, never the first thing tried")
    func remoteIsSecond() {
        // The regression this guards: the app used to send EVERY scan to a
        // third party because `.openRouter` was first in the chain. It is still
        // in the chain - it is the only thing that can read a photo with no
        // barcode in it - but the barcode step runs ahead of it, outside this
        // order entirely, and short-circuits on success.
        let order = ParsingConfig.onDevice.fallbackOrder
        #expect(order.first == .openRouter)
        #expect(order.contains(.appleIntelligence))
        // On-device text recognition never runs before the remote parser: the
        // owner rejected it as an extraction engine.
        #expect(order.firstIndex(of: .appleIntelligence) == 1)
    }

    @Test("Enriching a decoded barcode does not require an upload")
    func enrichmentStaysOnDevice() {
        // If this ever becomes `.remote`, every scan is an upload again -
        // including the ones whose barcode read perfectly.
        #expect(UnifiedBoardingPassService.barcodeEnrichment == .onDeviceText)
        #expect(UnifiedBoardingPassService.remoteFallbackEnabled)
    }

    @Test("The barcode step has its own statistics key")
    func barcodeStatisticsKey() {
        #expect(BoardingPassParsingStep.barcode.key == "barcode")
        #expect(BoardingPassParsingStep.configured(.appleIntelligence).key == "apple_intelligence")
        #expect(BoardingPassParsingStep.barcode.method == nil)
    }
}

private extension BoardingPassParsingStep {
    /// Mirrors `ParsingResult.method` for the step itself, so the test can say
    /// "the barcode is not one of the model-backed methods" directly.
    var method: ParsingMethod? {
        if case .configured(let method) = self { return method }
        return nil
    }
}
