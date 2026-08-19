//
//  CountryLocatorTests.swift
//  SkyLineTests
//
//  Country grouping is the default organisation of the place log, so a wrong
//  or missing country is visible on the first screen of the app.
//

import Testing
import Foundation
import CoreLocation
@testable import SkyLine

@Suite("Country lookup")
struct CountryLocatorTests {

    let locator = CountryLocator.shared

    @Test("Resolves well-known coordinates to the right country", arguments: [
        (35.6762, 139.6503, "JP"),   // Tokyo
        (48.8566, 2.3522, "FR"),     // Paris
        (40.7128, -74.0060, "US"),   // New York
        (-33.8688, 151.2093, "AU"),  // Sydney
        (64.8378, -147.7164, "US"),  // Fairbanks
        (25.2048, 55.2708, "AE"),    // Dubai
        (-22.9068, -43.1729, "BR"),  // Rio de Janeiro
    ])
    func knownCities(lat: Double, lon: Double, expected: String) {
        let country = locator.country(latitude: lat, longitude: lon)
        #expect(country?.code == expected,
                "expected \(expected) at (\(lat), \(lon)), got \(country?.code ?? "nil")")
    }

    @Test("Open ocean resolves to no country rather than the nearest land")
    func openOceanIsNil() {
        // Point Nemo, the oceanic pole of inaccessibility.
        #expect(locator.country(latitude: -48.876, longitude: -123.393) == nil)
    }

    @Test("Invalid or out-of-range coordinates return nil instead of trapping")
    func invalidCoordinates() {
        #expect(locator.country(latitude: 200, longitude: 0) == nil)
        #expect(locator.country(latitude: 0, longitude: 999) == nil)
        #expect(locator.country(latitude: .nan, longitude: .nan) == nil)
        #expect(locator.country(latitude: .infinity, longitude: 0) == nil)
    }

    @Test("Returns an English display name, not the formal long form")
    func usesEnglishExonym() {
        // ADMIN would give "United Republic of Tanzania"; a place list wants
        // the short name.
        let tanzania = locator.country(latitude: -6.369, longitude: 34.888)
        #expect(tanzania?.code == "TZ")
        #expect(tanzania?.name == "Tanzania")
    }

    @Test("An enclave wins over the country surrounding it")
    func enclaveBeatsSurroundingCountry() {
        // Lesotho is entirely inside South Africa. Smallest-bounding-box-first
        // ordering is what makes this resolve correctly.
        let lesotho = locator.country(latitude: -29.6100, longitude: 28.2336)
        #expect(lesotho?.code == "LS")
    }

    @Test("The CLLocationCoordinate2D overload agrees with the scalar one")
    func coordinateOverloadMatches() {
        let coordinate = CLLocationCoordinate2D(latitude: 51.5074, longitude: -0.1278)
        #expect(locator.country(at: coordinate)?.code
                == locator.country(latitude: 51.5074, longitude: -0.1278)?.code)
    }

    @Test("Repeated lookups are consistent")
    func repeatedLookupsStable() {
        let first = locator.country(latitude: 35.6762, longitude: 139.6503)
        let second = locator.country(latitude: 35.6762, longitude: 139.6503)
        #expect(first == second)
    }
}

@Suite("Blank-string coalescing")
struct NilIfBlankTests {

    @Test("Blank strings become nil so coalescing reaches the fallback")
    func blankBecomesNil() {
        // This is the exact bug that made every place show as "Unknown":
        // trip.country was "" rather than nil, so `trip.country ?? resolved`
        // kept the empty string and discarded a correctly resolved country.
        #expect("".nilIfBlank == nil)
        #expect("   ".nilIfBlank == nil)
        #expect("\n\t ".nilIfBlank == nil)
    }

    @Test("Real values survive, trimmed")
    func realValuesSurvive() {
        #expect("Japan".nilIfBlank == "Japan")
        #expect("  Japan  ".nilIfBlank == "Japan")
    }

    @Test("Coalescing now reaches the resolved country")
    func coalescingReachesFallback() {
        let blankStored: String? = ""
        #expect((blankStored?.nilIfBlank ?? "Japan") == "Japan")

        let realStored: String? = "France"
        #expect((realStored?.nilIfBlank ?? "Japan") == "France")
    }
}
