import Foundation

/// Shares Eave's read-only SMC connection with Stats readers.
public enum HardwareAccess {
    public static var temperatureUnit: String {
        get { Store.shared.string(key: "temperature_units", defaultValue: "system") }
        set { Store.shared.set(key: "temperature_units", value: ["celsius", "fahrenheit"].contains(newValue) ? newValue : "system") }
    }
    public static var smcKeys: () -> [String] = { [] }
    public static var smcString: (String) -> String? = { _ in nil }
    public static var smcValue: (String) -> Double? = { _ in nil }
}
