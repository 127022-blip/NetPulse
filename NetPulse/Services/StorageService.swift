import Foundation

/// 存储服务 - 负责数据的持久化存储
final class StorageService: ObservableObject {
    // MARK: - 单例
    static let shared = StorageService()

    // MARK: - Published 属性
    @Published private(set) var todayTraffic = TrafficRecord.today
    @Published private(set) var trafficHistory: [TrafficRecord] = []

    // MARK: - 私有属性
    private let userDefaults = UserDefaults.standard
    private var saveTimer: Timer?

    // MARK: - 初始化
    private init() {
        loadTodayTraffic()
        loadTrafficHistory()
        checkAndResetForNewDay()
        startAutoSave()
    }

    deinit {
        saveTimer?.invalidate()
    }

    // MARK: - 公开方法

    /// 更新今日流量
    /// - Parameters:
    ///   - downloaded: 新增下载字节数
    ///   - uploaded: 新增上传字节数
    ///   - currentStats: 当前网络统计
    func updateTodayTraffic(downloaded: UInt64, uploaded: UInt64, currentStats: NetworkStats) {
        todayTraffic.downloadBytes += downloaded
        todayTraffic.uploadBytes += uploaded

        // 更新峰值速度
        if currentStats.downloadSpeed > todayTraffic.peakDownloadSpeed {
            todayTraffic.peakDownloadSpeed = currentStats.downloadSpeed
        }
        if currentStats.uploadSpeed > todayTraffic.peakUploadSpeed {
            todayTraffic.peakUploadSpeed = currentStats.uploadSpeed
        }

        // 标记更新时间
        todayTraffic.createdAt = ISO8601DateFormatter().string(from: Date())
    }

    /// 保存今日流量
    func saveTodayTraffic() {
        // 每次保存时检查是否需要跨日重置
        checkAndResetForNewDay()
        
        userDefaults.set(todayTraffic.downloadBytes, forKey: Constants.UserDefaultsKeys.todayDownloadBytes)
        userDefaults.set(todayTraffic.uploadBytes, forKey: Constants.UserDefaultsKeys.todayUploadBytes)
        userDefaults.set(DateFormatter.yearMonthDay.string(from: Date()), forKey: Constants.UserDefaultsKeys.lastResetDate)

        // 同时保存到历史记录
        saveToHistory(todayTraffic)
    }

    /// 重置今日流量
    func resetTodayTraffic() {
        todayTraffic = TrafficRecord.today
        saveTodayTraffic()
    }

    /// 清除所有历史记录
    func clearHistory() {
        trafficHistory.removeAll()
        userDefaults.removeObject(forKey: Constants.UserDefaultsKeys.trafficRecords)
    }

    /// 获取指定日期的流量记录
    /// - Parameter date: 日期字符串 (YYYY-MM-DD)
    /// - Returns: 流量记录，如果没有则返回 nil
    func getTrafficRecord(for date: String) -> TrafficRecord? {
        return trafficHistory.first { $0.date == date }
    }

    /// 获取最近几天的流量记录
    /// - Parameter days: 天数
    /// - Returns: 流量记录数组
    func getRecentTrafficRecords(days: Int) -> [TrafficRecord] {
        let sortedRecords = trafficHistory.sorted { $0.date > $1.date }
        return Array(sortedRecords.prefix(days))
    }

    // MARK: - 私有方法

    /// 加载今日流量
    private func loadTodayTraffic() {
        let lastResetDate = userDefaults.string(forKey: Constants.UserDefaultsKeys.lastResetDate)
        let today = DateFormatter.yearMonthDay.string(from: Date())

        // 如果不是今天，重置流量
        if lastResetDate != today {
            todayTraffic = TrafficRecord.today
            return
        }

        // 加载保存的流量
        let downloaded = UInt64(userDefaults.integer(forKey: Constants.UserDefaultsKeys.todayDownloadBytes))
        let uploaded = UInt64(userDefaults.integer(forKey: Constants.UserDefaultsKeys.todayUploadBytes))

        todayTraffic = TrafficRecord(
            date: today,
            downloadBytes: downloaded,
            uploadBytes: uploaded,
            createdAt: ISO8601DateFormatter().string(from: Date())
        )
    }

    /// 加载流量历史
    private func loadTrafficHistory() {
        guard let data = userDefaults.data(forKey: Constants.UserDefaultsKeys.trafficRecords),
              let records = try? JSONDecoder().decode([TrafficRecord].self, from: data) else {
            trafficHistory = []
            return
        }
        trafficHistory = records.sorted { $0.date > $1.date }
    }

    /// 保存到历史记录
    private func saveToHistory(_ record: TrafficRecord) {
        // 检查是否已存在该日期的记录
        if let index = trafficHistory.firstIndex(where: { $0.date == record.date }) {
            trafficHistory[index] = record
        } else {
            trafficHistory.append(record)
        }

        // 按日期排序
        trafficHistory.sort { $0.date > $1.date }

        // 只保留最近30天
        if trafficHistory.count > Constants.Storage.maxHistoryDays {
            trafficHistory = Array(trafficHistory.prefix(Constants.Storage.maxHistoryDays))
        }

        // 保存到 UserDefaults
        if let data = try? JSONEncoder().encode(trafficHistory) {
            userDefaults.set(data, forKey: Constants.UserDefaultsKeys.trafficRecords)
        }
    }

    /// 检查是否需要在新的一天重置流量
    private func checkAndResetForNewDay() {
        let lastResetDate = userDefaults.string(forKey: Constants.UserDefaultsKeys.lastResetDate)
        let today = DateFormatter.yearMonthDay.string(from: Date())

        if lastResetDate != today {
            // 保存昨天的流量到历史
            if lastResetDate != nil {
                saveToHistory(todayTraffic)
            }
            // 重置今日流量
            todayTraffic = TrafficRecord.today
        }
    }

    /// 开始自动保存定时器
    private func startAutoSave() {
        saveTimer = Timer.scheduledTimer(withTimeInterval: Constants.Storage.saveInterval, repeats: true) { [weak self] _ in
            self?.saveTodayTraffic()
        }
        RunLoop.main.add(saveTimer!, forMode: .common)
    }
}
