import LoopKit

/// Glooko's unit names, mapped onto LoopKit's own units now that LoopKit samples carry
/// `LoopQuantity` rather than HealthKit's `HKQuantity`. File name kept for the Xcode project.
extension LoopUnit {

    static var gkMilligramsPerDeciliter: LoopUnit { .milligramsPerDeciliter }

    static var gkMillimolesPerLiter: LoopUnit { .millimolesPerLiter }

    static var gkInternationalUnitsPerHour: LoopUnit { .internationalUnitsPerHour }
}
