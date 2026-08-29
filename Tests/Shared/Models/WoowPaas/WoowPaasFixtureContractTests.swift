#if CLOUD_EDITION
import Foundation
@testable import Shared
import Testing

/// Cross-platform wire contract tests for the WOOW PaaS DTOs (PRD §6).
///
/// The mock responses are never written by hand: they are the `paas-fixtures` recorded from real
/// traffic by the Android Layer 2 tests, and each fixture ships with a `*.expected.json` sidecar
/// carrying the canonical value of every semantic field after decoding. Both platforms assert each
/// decoded field against the sidecar, which closes the gap between kotlinx.serialization and Codable
/// defaults (unknown/missing field handling, snake_case mapping, fractional seconds) that a
/// "decoding did not crash" test would let drift apart.
@Suite("WoowPaas fixture contract")
struct WoowPaasFixtureContractTests {
    @Test(.disabled("waiting for recorded paas-fixtures from Android Layer 2 PR"))
    func decodedValuesMatchExpectationsSidecar() throws {
        // TODO: implement once the recorded `paas-fixtures` land (PRD §6 sidecar mechanism):
        // 1. Copy the recorded fixtures and their `*.expected.json` sidecars from the Android
        //    Layer 2 PR into a `paas-fixtures` resource folder of this test target — verbatim,
        //    never edited or hand-written.
        // 2. Turn this into a parameterized `@Test(arguments:)` over every fixture file.
        // 3. Decode each fixture with `WoowPaasJSONMapper.decoder` into its DTO
        //    (DeviceCodeResponseDto / TokenResponseDto / ProvisionResponseDto / StatusResponseDto).
        // 4. Assert every semantic field against the sidecar values — field by field, including
        //    absent-field expectations; "decodes without throwing" alone is not a passing criterion.
    }
}
#endif
