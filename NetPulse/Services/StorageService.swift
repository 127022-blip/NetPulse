import Foundation

/// 存储服务 - 负责数据的持久化存储
final class StorageService: ObservableObject {
    static let shared = StorageService()

    @Published private(set) var todayTraffic = TrafficRecord.today
    @Published private(set) var trafficHistory: [TrafficRecord] = []

    private let userDefaults = UserDefaults.standard
    private var saveTimer: Timer?

    private init() {
        loadTrafficHistory()
        loadTodayTraffic()
        checkAndResetForNewDay()
        startAutoSave()
    }

    deinit {
        saveTimer?.invalidate()
    }

    func updateTodayTraffic(downloaded: UInt64, uploaded: UInt64, currentStats: NetworkStats) {
        // 写入前再确认跨日，避免跨日后仍累加到旧日
        checkAndResetForNewDay()

        todayTraffic.downloadBytes += downloaded
        todayTraffic.uploadBytes += uploaded

        if currentStats.downloadSpeed > todayTraffic.peakDownloadSpeed {
            todayTraffic.peakDownloadSpeed = currentStats.downloadSpeed
        }
        if currentStats.uploadSpeed > todayTraffic.peakUploadSpeed {
            todayTraffic.peakUploadSpeed = currentStats.uploadSpeed
        }

        todayTraffic.createdAt = ISO8601DateFormatter().string(from: Date())
    }

    func saveTodayTraffic() {
        checkAndResetForNewDay()

        userDefaults.set(todayTraffic.downloadBytes, forKey: Constants.UserDefaultsKeys.todayDownloadBytes)
        userDefaults.set(todayTraffic.uploadBytes, forKey: Constants.UserDefaultsKeys.todayUploadBytes)
        userDefaults.set(DateFormatter.yearMonthDay.string(from: Date()), forKey: Constants.UserDefaultsKeys.lastResetDate)

        saveToHistory(todayTraffic)
    }

    func resetTodayTraffic() {
        todayTraffic = TrafficRecord.today
        saveTodayTraffic()
    }

    func clearHistory() {
        trafficHistory.removeAll()
        userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.trafficRecords)
    }

    func getTrafficRecord(for date: String) -> TrafficRecord? {
        return trafficHistory.first { $0.date == date }
    }

    func getRecentTrafficRecords(days: Int) -> [TrafficRecord] {
        let sortedRecords = trafficHistory.sorted { $0.date > $1.date }
        return Array(sortedRecords.prefix(days))
    }

    /// 加载今日流量：日期变化时先把 UD 中昨日字节归档进 history，再清零今日
    private func loadTodayTraffic() {
        let lastResetDate = userDefaults.string(forKey: Constants.UserDefaultsKeys.lastResetDate)
        let today = DateFormatter.yearMonthDay.string(from: Date())

        let downloaded = UInt64(userDefaults.integer(forKey: Constants.UserDefaultsKeys.todayDownloadBytes))
        let uploaded = UInt64(userDefaults.integer(forKey: Constants.UserDefaultsKeys.todayUploadBytes))

        if let lastResetDate = lastResetDate, lastResetDate != today {
            // 归档昨日 UD 数据到历史（与 checkAndResetForNewDay 口径一致）
            let yesterdayRecord = TrafficRecord(
                date: lastResetDate,
                downloadBytes: downloaded,
                uploadBytes: uploaded,
                createdAt: ISO8601DateFormatter().string(from: Date())
            )
            if downloaded > 0 || uploaded > 0 {
                saveToHistory(yesterdayRecord)
            }
            // 清零今日
            todayTraffic = TrafficRecord.today
            userDefaults.set(0, forKey: Constants.UserDefaultsKeys.todayDownloadBytes)
            userDefaults.set(0, forKey: Constants.UserDefaultsKeys.todayUploadBytes)
            userDefaults.set(today, forKey: Constants.UserDefaultsKeys.lastResetDate)
            return
        }

        if lastResetDate == nil {
            todayTraffic = TrafficRecord.today
            return
        }

        todayTraffic = TrafficRecord(
            date: today,
            downloadBytes: downloaded,
            uploadBytes: uploaded,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    private func loadTrafficHistory() {
        guard let data = userDefaults.data(forKey: Constants.UserDefaultsKeys.trafficRecords),
              let records = try? JSONDecoder().decode([TrafficRecord].self, from: data) else {
            trafficHistory = []
            return
        }
        trafficHistory = records.sorted { $0.date > $1.date }
    }

    private func saveToHistory(_ record: TrafficRecord) {
        if let index = trafficHistory.firstIndex(where: { $0.date == record.date }) {
            // 保留更大的累计值，避免被空记录覆盖
            let existing = trafficHistory[index]
            var merged = record
            merged.downloadBytes = max(existing.downloadBytes, record.downloadBytes)
            merged.uploadBytes = max(existing.uploadBytes, record.uploadBytes)
            merged.peakDownloadSpeed = max(existing.peakDownloadSpeed, record.peakDownloadSpeed)
            merged.peakUploadSpeed = max(existing.peakUploadSpeed, record.peakUploadSpeed)
            trafficHistory[index] = merged
        } else {
            trafficHistory.append(record)
        }

        trafficHistory.sort { $0.date > $1.date }

        if trafficHistory.count > Constants.Storage.maxHistoryDays {
            trafficHistory = Array(trafficHistory.prefix(Constants.Storage.maxHistoryDays))
        }

        if let data = try? JSONEncoder().encode(trafficHistory) {
            userDefaults.set(data, forKey: Constants.UserDefaultsKeys.trafficRecords)
        }
    }

    private func checkAndResetForNewDay() {
        let lastResetDate = userDefaults.string(forKey: Constants.UserDefaultsKeys.lastResetDate)
        let today = DateFormatter.yearMonthDay.string(from: Date())

        if lastResetDate != today {
            if let lastResetDate = lastResetDate {
                // 用内存中的今日（实为昨日）或 UD 归档
                var archive = todayTraffic
                if archive.date != lastResetDate {
                    archive = TrafficRecord(
                        date: lastResetDate,
                        downloadBytes: UInt64(userDefaults.integer(forKey: Constants.UserDefaultsKeys.todayDownloadBytes)),
                        uploadBytes: UInt64(userDefaults.integer(forKey: Constants.UserDefaultsKeys.todayUploadBytes)),
                        peakDownloadSpeed: todayTraffic.peakDownloadSpeed,
                        peakUploadSpeed: todayTraffic.peakUploadSpeed,
                        createdAt: ISO8601DateFormatter().string(from: Date())
                    )
                } else {
                    archive = TrafficRecord(
                        date: lastResetDate,
                        downloadBytes: todayTraffic.downloadBytes,
                        uploadBytes: todayTraffic.uploadBytes,
                        peakDownloadSpeed: todayTraffic.peakDownloadSpeed,
                        peakUploadSpeed: todayTraffic.peakUploadSpeed,
                        createdAt: todayTraffic.createdAt
                    )
                }
                if archive.downloadBytes > 0 || archive.uploadBytes > 0 {
                    saveToHistory(archive)
                }
            }
            todayTraffic = TrafficRecord.today
            userDefaults.set(0, forKey: Constants.UserDefaultsKeys.todayDownloadBytes)
            userDefaults.set(0, forKey: Constants.UserDefaultsKeys.todayUploadBytes)
            userDefaults.set(today, forKey: Constants.UserDefaultsKeys.lastResetDate)
        }
    }

    private func startAutoSave() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: Constants.Storage.saveInterval, repeats: true) { [weak self] _ in
            self?.saveTodayTraffic()
        }
        RunLoop.main.add(saveTimer!, forMode: .common)
    }
}
