import Foundation

enum TemperatureSourceKind: String {
    case smc = "AppleSMC"
    case hid = "IOKit HID"
    case unavailable = "不可用"
}

struct TemperatureReading: Equatable {
    let celsius: Double?
    let sourceKind: TemperatureSourceKind
    let sourceDetail: String
    let sampledAt: Date

    static func unavailable(detail: String, at date: Date = Date()) -> TemperatureReading {
        TemperatureReading(celsius: nil, sourceKind: .unavailable, sourceDetail: detail, sampledAt: date)
    }

    var menuBarTitle: String {
        guard let celsius else { return "--°" }
        return String(format: "%.0f°", celsius)
    }

    var detailText: String {
        guard let celsius else {
            return "当前无法读取 CPU 温度（\(sourceDetail)）"
        }
        return String(format: "CPU %.1f℃ · 来源 %@ · %@", celsius, sourceKind.rawValue, sourceDetail)
    }
}

enum ChipFamily: String {
    case intel
    case m1
    case m2
    case m3
    case m4
    case m5
    case m6
    case appleUnknown
    case unknown

    var displayName: String {
        switch self {
        case .intel: return "Intel"
        case .m1: return "Apple M1 系列"
        case .m2: return "Apple M2 系列"
        case .m3: return "Apple M3 系列"
        case .m4: return "Apple M4 系列"
        case .m5: return "Apple M5 系列"
        case .m6: return "Apple M6 系列"
        case .appleUnknown: return "Apple Silicon（未识别代数）"
        case .unknown: return "未知芯片"
        }
    }

    /// Priority-ordered SMC temperature keys for CPU-like sensors on this chip family.
    /// Drawn from public Stats / VirtualSMC key tables; battery keys intentionally omitted.
    var preferredSMCKeys: [String] {
        switch self {
        case .intel:
            return ["TC0P", "TC0D", "TC0E", "TC0F", "TC0H", "TCAD"]
        case .m1:
            return ["Tp01", "Tp05", "Tp0D", "Tp0H", "Tp0L", "Tp0P", "Tp0X", "Tp0b", "Tp09", "Tp0T"]
        case .m2:
            return ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0X", "Tp0b", "Tp0f", "Tp0j", "Tp1h", "Tp1t", "Tp1p", "Tp1l"]
        case .m3:
            return ["Tf04", "Tf09", "Tf0A", "Tf0B", "Tf0D", "Tf0E", "Tf44", "Tf49", "Tf4A", "Tf4B", "Tf4D", "Tf4E",
                    "Te05", "Te0L", "Te0P", "Te0S"]
        case .m4:
            return ["Tp01", "Tp05", "Tp09", "Tp0D", "Tp0V", "Tp0Y", "Tp0b", "Tp0e",
                    "Te05", "Te0S", "Te09", "Te0H"]
        case .m5:
            return ["Tp00", "Tp04", "Tp08", "Tp0C", "Tp0G", "Tp0K",
                    "Tp0O", "Tp0R", "Tp0U", "Tp0X", "Tp0a", "Tp0d", "Tp0g", "Tp0j", "Tp0m", "Tp0p", "Tp0u", "Tp0y"]
        case .m6:
            return ["Tp0j", "Tp0g", "Tp09", "Tp07",
                    "Tp0m", "Tp0L", "Tp0I", "Tp0d", "Tp0E", "Tp0G", "Tp0b", "Tp05",
                    "Te07", "Te08", "Te09", "Te0c", "Te0h", "Te0i"]
        case .appleUnknown:
            // Broad probe order: M5 → M4 → M3 → M2 → M1 cores, then Intel-legacy names.
            return ChipFamily.m5.preferredSMCKeys
                + ChipFamily.m4.preferredSMCKeys
                + ChipFamily.m3.preferredSMCKeys
                + ChipFamily.m2.preferredSMCKeys
                + ChipFamily.m1.preferredSMCKeys
                + ChipFamily.intel.preferredSMCKeys
        case .unknown:
            return ChipFamily.appleUnknown.preferredSMCKeys
        }
    }

    static func detect() -> ChipFamily {
        var brandSize = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &brandSize, nil, 0)
        var brand = [CChar](repeating: 0, count: max(brandSize, 1))
        if brandSize > 0 {
            sysctlbyname("machdep.cpu.brand_string", &brand, &brandSize, nil, 0)
        }
        let brandString = String(cString: brand)

        var modelSize = 0
        sysctlbyname("hw.model", nil, &modelSize, nil, 0)
        var model = [CChar](repeating: 0, count: max(modelSize, 1))
        if modelSize > 0 {
            sysctlbyname("hw.model", &model, &modelSize, nil, 0)
        }
        let modelString = String(cString: model)

        let haystack = (brandString + " " + modelString).uppercased()
        if haystack.contains("INTEL") { return .intel }
        if haystack.contains("M6") { return .m6 }
        if haystack.contains("M5") { return .m5 }
        if haystack.contains("M4") { return .m4 }
        if haystack.contains("M3") { return .m3 }
        if haystack.contains("M2") { return .m2 }
        if haystack.contains("M1") { return .m1 }

        var arm64: Int32 = 0
        var armSize = MemoryLayout<Int32>.size
        sysctlbyname("hw.optional.arm64", &arm64, &armSize, nil, 0)
        if arm64 == 1 { return .appleUnknown }
        return .unknown
    }
}
