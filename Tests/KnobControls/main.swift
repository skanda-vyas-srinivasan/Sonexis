import Foundation
@testable import Sonexis

func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
}
func close(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.00000001 }
var normal = KnobDragAdjustment(value: 0.5)
var fine = KnobDragAdjustment(value: 0.5)
expect(close(normal.update(translation: 18, range: 0...1, fine: false), 0.6), "Normal drag changed sensitivity")
expect(close(fine.update(translation: 18, range: 0...1, fine: true), 0.51), "Fine drag is not ten times slower")
// Changing modifiers without moving the pointer must not jump the value.
expect(close(normal.update(translation: 18, range: 0...1, fine: true), 0.6), "Pressing Shift jumped value")
expect(close(normal.update(translation: 36, range: 0...1, fine: true), 0.61), "Fine motion after modifier change incorrect")
expect(close(normal.update(translation: 36, range: 0...1, fine: false), 0.61), "Releasing Shift jumped value")
expect(close(normal.update(translation: 18, range: 0...1, fine: false), 0.51), "Drag reversal incorrect")
expect(normal.update(translation: 1000, range: 0...1, fine: false) == 1, "Drag exceeded upper bound")
expect(normal.update(translation: 999, range: 0...1, fine: false) < 1, "Drag stuck at boundary")
expect(normal.update(translation: -1000, range: 0...1, fine: false) == 0, "Drag exceeded lower bound")
// Fine integer drags accumulate sub-integer movement rather than stalling.
var integer = KnobDragAdjustment(value: 8)
for tick in 1...100 { _ = integer.update(translation: Double(tick), range: 4...16, fine: true) }
expect(CompactSlider.ValueFormat.integer.clampedValue(integer.value, range: 4...16) == 9, "Fine integer drag stalled")
let formats: [CompactSlider.ValueFormat] = [.percent, .db, .dbValue, .ms, .hz, .ratio, .semitones, .msValue]
for format in formats {
    expect(close(format.adjustmentStep(fine: false), format.adjustmentStep(fine: true) * 10), "Keyboard fine-step ratio wrong")
    expect(format.clampedValue(.nan, range: 0...1) == nil, "NaN accepted")
    expect(format.clampedValue(.infinity, range: 0...1) == nil, "Infinity accepted")
    expect(format.clampedValue(-99, range: 0...1) == 0, "Lower clamp failed")
    expect(format.clampedValue(99, range: 0...1) == 1, "Upper clamp failed")
    // Smallest key step remains visible and round-trips through exact entry.
    let increment = format.adjustmentStep(fine: true)
    let displayed = Double(format.editText(for: increment))!
    expect(close(format.value(fromDisplayed: displayed)!, increment), "Fine step is invisible or loses precision")
}
expect(CompactSlider.ValueFormat.integer.adjustmentStep(fine: true) == 1, "Integer keys should use whole steps")
expect(close(CompactSlider.ValueFormat.db.adjustmentStep(fine: false) * 12, 0.1), "Normalized EQ step is not 0.1 dB")
expect(close(CompactSlider.ValueFormat.ms.adjustmentStep(fine: false) * 1000, 1), "Delay step is not 1 ms")
print("PASS: fine drag, mid-drag Shift changes, bounds/reversal, integer accumulation, keyboard steps, typed precision, non-finite rejection")
