import Foundation

extension Doctor.Facts {
    /// Sync through iCloud as the app last saw it (`ICloudSyncEngine`): whether it is on, iCloud Drive is there, when it
    /// last synced, the last error, and the values from iCloud not applied here.
    public struct ICloudSyncFacts: Equatable, Sendable {
        public var enabled = false
        /// iCloud Drive is there and can be written.
        public var available = true
        public var lastSync: Date?
        public var lastError: String?
        /// What another Mac wrote is still coming down from iCloud.
        public var waiting = false
        /// Values from iCloud not applied on this Mac, by key, and why.
        public var refused: [String: ICloudSync.Problem] = [:]
        /// When these were gathered ("2 minutes ago" is counted from it); nil: now.
        public var checked: Date?

        public init() {}
    }
}

extension Doctor {
    static func iCloudSync(_ facts: Facts, _ t: Words) -> [Finding] {
        let sync = facts.iCloudSync
        guard sync.enabled else {
            return [Finding(area: .iCloudSync, status: .ok, title: t.tr("没有开「通过 iCloud 同步」", "Sync through iCloud is off"),
                            detail: t.tr("在设置 → 通用里打开", "Settings → General turns it on"))]
        }
        guard sync.available else {
            return [Finding(area: .iCloudSync, status: .problem, title: t.tr("iCloud 云盘不可用", "iCloud Drive isn't available"),
                            detail: ICloudSync.turnOnDrive(chinese: t.chinese))]
        }
        var out: [Finding] = []
        let last = sync.lastSync.map { t.tr("上次同步：", "last synced ") + ICloudSync.ago($0, now: sync.checked ?? Date(), chinese: t.chinese) }
        if let error = sync.lastError {
            out.append(Finding(area: .iCloudSync, status: .warning, title: t.tr("通过 iCloud 同步出错了", "Sync through iCloud failed"),
                               detail: [error, last].compactMap { $0 }.joined(separator: t.tr("；", "; "))))
        } else if sync.waiting {
            out.append(Finding(area: .iCloudSync, status: .warning, title: t.tr("正在等 iCloud…", "Waiting for iCloud…"),
                               detail: [t.tr("别的 Mac 同步的文件还在下载", "files another Mac synced are still downloading"), last]
                                   .compactMap { $0 }.joined(separator: t.tr("；", "; "))))
        } else if let lastSync = sync.lastSync {
            out.append(Finding(area: .iCloudSync, status: .ok,
                               title: t.tr("已通过 iCloud 同步（", "Synced through iCloud ")
                                   + ICloudSync.ago(lastSync, now: sync.checked ?? Date(), chinese: t.chinese) + t.tr("）", "")))
        } else {
            out.append(Finding(area: .iCloudSync, status: .warning, title: t.tr("还没有通过 iCloud 同步过", "Not synced through iCloud yet"),
                               detail: t.tr("在设置 → 通用里点「立即同步」", "Settings → General → Sync Now")))
        }
        if !sync.refused.isEmpty {
            let list = sync.refused.sorted { $0.key < $1.key }.map { "\($0.key) (\($0.value.text(chinese: t.chinese)))" }
            out.append(Finding(area: .iCloudSync, status: .warning,
                               title: t.tr("iCloud 里的 \(list.count) 项设置没有用在这台 Mac 上",
                                           list.count == 1 ? "1 setting from iCloud isn't used on this Mac" : "\(list.count) settings from iCloud aren't used on this Mac"),
                               detail: list.joined(separator: t.tr("、", ", "))))
        }
        return out
    }
}

extension ICloudSync {
    /// What to do when iCloud Drive isn't there.
    public static func turnOnDrive(chinese: Bool) -> String {
        chinese ? "在系统设置 → Apple 账户 → iCloud 里打开 iCloud 云盘" : "Turn on iCloud Drive in System Settings → Apple Account → iCloud"
    }

    /// "just now", "2 min ago", "3 h ago", or the day.
    public static func ago(_ date: Date, now: Date, chinese: Bool) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        switch seconds {
        case ..<60: return chinese ? "刚刚" : "just now"
        case ..<3600: return chinese ? "\(Int(seconds / 60)) 分钟前" : "\(Int(seconds / 60)) min ago"
        case ..<86400: return chinese ? "\(Int(seconds / 3600)) 小时前" : "\(Int(seconds / 3600)) h ago"
        default:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: chinese ? "zh_CN" : "en_US")
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }
}

extension AIConfig {
    /// `@config` turning sync through iCloud on or off: on only with iCloud Drive there. What syncs (the hidden words and
    /// recent questions above all, which need the user's own choice) is never set here (`syncOnlyInSettings`).
    static func checkICloudSync(_ value: JSONValue, in config: Config, env: Environment, text: Text) -> Row? {
        let label = text.iCloudSyncLabel, path = Key.iCloudSync.path
        guard case let .bool(on) = value else { return Row(key: path, label: label, status: .refused(text.notValid)) }
        guard on != config.iCloudSync.enabled else { return nil }
        if on, !env.iCloudDriveAvailable() { return Row(key: path, label: label, status: .refused(ICloudSync.turnOnDrive(chinese: env.chinese))) }
        return Row(key: path, label: label, old: text.onOff(config.iCloudSync.enabled), new: text.onOff(on), status: .change, edit: .iCloudSync(on))
    }
}

extension AIConfig.Text {
    public var iCloudSyncLabel: String { tr("通过 iCloud 同步", "Sync through iCloud") }
    /// What syncs is only chosen in Settings: hidden words and recent questions need the user's own informed choice.
    var syncOnlyInSettings: String { tr("只能在设置 → 通用里选", "only chosen in Settings → General") }
}
