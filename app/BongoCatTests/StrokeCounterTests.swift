import Testing
import Foundation
@testable import BongoCat

@Suite("StrokeCounter")
struct StrokeCounterTests {

    // Use isolated UserDefaults keys so tests never touch production data.
    private func makeCounter() -> StrokeCounter {
        let counter = StrokeCounter(
            strokesKey:    "Test_BongoCatTotalStrokes",
            keystrokesKey: "Test_BongoCatKeystrokes",
            mouseClicksKey:"Test_BongoCatMouseClicks"
        )
        counter.reset()
        return counter
    }

    private func cleanup() {
        UserDefaults.standard.removeObject(forKey: "Test_BongoCatTotalStrokes")
        UserDefaults.standard.removeObject(forKey: "Test_BongoCatKeystrokes")
        UserDefaults.standard.removeObject(forKey: "Test_BongoCatMouseClicks")
    }

    // MARK: - Initial state

    @Test("starts at zero after reset")
    func test_initialState_afterReset_allCountsAreZero() {
        defer { cleanup() }
        let counter = makeCounter()

        #expect(counter.totalStrokes == 0)
        #expect(counter.keystrokes == 0)
        #expect(counter.mouseClicks == 0)
    }

    // MARK: - Keystroke counting

    @Test("incrementKeystrokes increments keystrokes and totalStrokes")
    func test_incrementKeystrokes_whenCalled_updatesAllCounts() {
        defer { cleanup() }
        let counter = makeCounter()

        counter.incrementKeystrokes()

        #expect(counter.keystrokes == 1)
        #expect(counter.totalStrokes == 1)
        #expect(counter.mouseClicks == 0)
    }

    @Test("incrementKeystrokes accumulates across multiple calls")
    func test_incrementKeystrokes_whenCalledMultipleTimes_accumulates() {
        defer { cleanup() }
        let counter = makeCounter()

        counter.incrementKeystrokes()
        counter.incrementKeystrokes()
        counter.incrementKeystrokes()

        #expect(counter.keystrokes == 3)
        #expect(counter.totalStrokes == 3)
    }

    // MARK: - Mouse click counting

    @Test("incrementMouseClicks increments mouseClicks and totalStrokes")
    func test_incrementMouseClicks_whenCalled_updatesAllCounts() {
        defer { cleanup() }
        let counter = makeCounter()

        counter.incrementMouseClicks()

        #expect(counter.mouseClicks == 1)
        #expect(counter.totalStrokes == 1)
        #expect(counter.keystrokes == 0)
    }

    @Test("mixed increments both contribute to totalStrokes")
    func test_mixedIncrements_bothContributeToTotal() {
        defer { cleanup() }
        let counter = makeCounter()

        counter.incrementKeystrokes()
        counter.incrementMouseClicks()
        counter.incrementKeystrokes()

        #expect(counter.keystrokes == 2)
        #expect(counter.mouseClicks == 1)
        #expect(counter.totalStrokes == 3)
    }

    // MARK: - Reset

    @Test("reset zeros all counts")
    func test_reset_whenCalled_zerosAllCounts() {
        defer { cleanup() }
        let counter = makeCounter()

        counter.incrementKeystrokes()
        counter.incrementMouseClicks()
        counter.reset()

        #expect(counter.totalStrokes == 0)
        #expect(counter.keystrokes == 0)
        #expect(counter.mouseClicks == 0)
    }

    // MARK: - Persistence

    @Test("counts persist across separate instances using the same keys")
    func test_persistence_whenNewInstanceCreated_loadsSavedCounts() {
        defer { cleanup() }
        let first = makeCounter()
        first.incrementKeystrokes()
        first.incrementKeystrokes()
        first.incrementMouseClicks()

        // Create a second instance with the same keys — should load persisted values.
        let second = StrokeCounter(
            strokesKey:    "Test_BongoCatTotalStrokes",
            keystrokesKey: "Test_BongoCatKeystrokes",
            mouseClicksKey:"Test_BongoCatMouseClicks"
        )

        #expect(second.keystrokes == 2)
        #expect(second.mouseClicks == 1)
        #expect(second.totalStrokes == 3)
    }

    // MARK: - onCountsUpdated callback

    @Test("onCountsUpdated fires after incrementKeystrokes with correct values")
    func test_onCountsUpdated_whenKeystrokeIncremented_callbackReceivesCorrectValues() {
        defer { cleanup() }
        let counter = makeCounter()

        var capturedKeystrokes = -1
        var capturedMouseClicks = -1
        var capturedTotal = -1
        counter.onCountsUpdated = { k, m, t in
            capturedKeystrokes = k
            capturedMouseClicks = m
            capturedTotal = t
        }

        counter.incrementKeystrokes()

        #expect(capturedKeystrokes == 1)
        #expect(capturedMouseClicks == 0)
        #expect(capturedTotal == 1)
    }

    @Test("onCountsUpdated fires after incrementMouseClicks with correct values")
    func test_onCountsUpdated_whenMouseClickIncremented_callbackReceivesCorrectValues() {
        defer { cleanup() }
        let counter = makeCounter()

        var capturedKeystrokes = -1
        var capturedMouseClicks = -1
        var capturedTotal = -1
        counter.onCountsUpdated = { k, m, t in
            capturedKeystrokes = k
            capturedMouseClicks = m
            capturedTotal = t
        }

        counter.incrementMouseClicks()

        #expect(capturedKeystrokes == 0)
        #expect(capturedMouseClicks == 1)
        #expect(capturedTotal == 1)
    }

    @Test("onCountsUpdated callback reflects accumulated counts on each call")
    func test_onCountsUpdated_whenCalledMultipleTimes_callbackReflectsAccumulatedCounts() {
        defer { cleanup() }
        let counter = makeCounter()

        var callCount = 0
        var lastTotal = 0
        counter.onCountsUpdated = { _, _, t in
            callCount += 1
            lastTotal = t
        }

        counter.incrementKeystrokes()
        counter.incrementKeystrokes()
        counter.incrementMouseClicks()

        #expect(callCount == 3)
        #expect(lastTotal == 3)
    }

    @Test("onCountsUpdated does not crash when callback is nil")
    func test_onCountsUpdated_whenCallbackIsNil_doesNotCrash() {
        defer { cleanup() }
        let counter = makeCounter()
        counter.onCountsUpdated = nil

        // Should not throw or crash.
        counter.incrementKeystrokes()
        counter.incrementMouseClicks()

        #expect(counter.totalStrokes == 2)
    }
}
