import Foundation
import UIKit

/// 双通道存储：App Group 为主，/var/mobile/Media 兜底（TrollStore 下保证小组件也能读到）
public final class SharedStore {
    public static let shared = SharedStore()
    public static let appGroupID = "group.com.agent.idcode"
    public static let fallbackDir = "/var/mobile/Media/Mayfly"
    static let fileName = "state.json"

    private let lock = NSRecursiveLock()
    private let fm = FileManager.default

    public var groupURL: URL? {
        fm.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID)?
            .appendingPathComponent(Self.fileName)
    }
    public var fallbackURL: URL {
        try? fm.createDirectory(atPath: Self.fallbackDir, withIntermediateDirectories: true)
        return URL(fileURLWithPath: Self.fallbackDir + "/" + Self.fileName)
    }

    private var primaryURL: URL { groupURL ?? fallbackURL }

    /// 实际生效的状态文件路径（诊断页使用）
    public var fileURL: URL { primaryURL }

    public func load() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        var best = Snapshot()
        var bestTime: Double = -1
        for url in [primaryURL, fallbackURL] {
            if let data = try? Data(contentsOf: url),
               let snap = try? JSONDecoder().decode(Snapshot.self, from: data),
               snap.updatedAt > bestTime {
                best = snap
                bestTime = snap.updatedAt
            }
        }
        return best
    }

    public func save(_ snap: Snapshot) {
        lock.lock(); defer { lock.unlock() }
        guard let data = try? JSONEncoder().encode(snap) else { return }
        for url in [primaryURL, fallbackURL] {
            do {
                try data.write(to: url, options: .atomic)
            } catch {
                NSLog("[Mayfly] save failed %@ -> %@", url.path, error.localizedDescription)
            }
        }
    }

    public func writeJSON(_ obj: Any, name: String) {
        lock.lock(); defer { lock.unlock() }
        guard JSONSerialization.isValidJSONObject(obj),
              let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return }
        for url in [primaryURL, fallbackURL] {
            try? data.write(to: url.deletingLastPathComponent().appendingPathComponent(name), options: .atomic)
        }
    }
}

/// 偏好设置（App Group UserDefaults，读不到就退回标准库）
public final class Pref {
    public static let shared = Pref()
    private let ud: UserDefaults

    public enum ThemeMode: String { case system, light, dark, scheduled }
    public enum WhaleMode: String { case on, off }

    private init() {
        ud = UserDefaults(suiteName: SharedStore.appGroupID) ?? .standard
    }

    public var themeMode: ThemeMode {
        get { ThemeMode(rawValue: ud.string(forKey: "themeMode") ?? "system") ?? .system }
        set { ud.set(newValue.rawValue, forKey: "themeMode") }
    }
    public var darkStart: String {
        get { ud.string(forKey: "darkStart") ?? "22:00" }
        set { ud.set(newValue, forKey: "darkStart") }
    }
    public var darkEnd: String {
        get { ud.string(forKey: "darkEnd") ?? "07:00" }
        set { ud.set(newValue, forKey: "darkEnd") }
    }
    public var whalePick: String {
        get { ud.string(forKey: "whalePick") ?? "" }
        set { ud.set(newValue, forKey: "whalePick") }
    }

    public var whaleArt: String {
        get { ud.string(forKey: "whaleArt") ?? "HE" }
        set { ud.set(newValue, forKey: "whaleArt") }
    }
    public var whaleSpeech: Bool {
        get { ud.object(forKey: "whaleSpeech") == nil ? true : ud.bool(forKey: "whaleSpeech") }
        set { ud.set(newValue, forKey: "whaleSpeech") }
    }
    public var notifyArrival: Bool {
        get { ud.object(forKey: "notifyArrival") == nil ? true : ud.bool(forKey: "notifyArrival") }
        set { ud.set(newValue, forKey: "notifyArrival") }
    }
    public var liveIsland: Bool {
        get { ud.object(forKey: "liveIsland") == nil ? true : ud.bool(forKey: "liveIsland") }
        set { ud.set(newValue, forKey: "liveIsland") }
    }
    public var kd100Key: String {
        get { ud.string(forKey: "kd100Key") ?? "" }
        set { ud.set(newValue, forKey: "kd100Key") }
    }
    public var kd100Customer: String {
        get { ud.string(forKey: "kd100Customer") ?? "" }
        set { ud.set(newValue, forKey: "kd100Customer") }
    }
    public var lastFetch: Double {
        get { ud.double(forKey: "lastFetch") }
        set { ud.set(newValue, forKey: "lastFetch") }
    }
    /// 各平台最近一次账号元信息（uid / 昵称）
    public func account(_ p: Platform) -> AccountInfo? {
        guard let s = ud.string(forKey: "acct.\(p.rawValue)") else { return nil }
        return try? JSONDecoder().decode(AccountInfo.self, from: Data(s.utf8))
    }
    public func setAccount(_ p: Platform, _ info: AccountInfo?) {
        guard let info = info, let s = try? String(data: JSONEncoder().encode(info), encoding: .utf8) else {
            ud.removeObject(forKey: "acct.\(p.rawValue)")
            return
        }
        ud.set(s, forKey: "acct.\(p.rawValue)")
    }
}
