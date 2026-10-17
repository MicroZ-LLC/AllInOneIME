import Foundation

/// What `@open` finds by every name it goes by: the apps in the folders apps are installed in, Finder (访达),
/// and the folders Finder names in its sidebar (`places`: 下载 is the Downloads folder). Spotlight knows them
/// by their file names and their names in the system language only: on an English system 计算器 doesn't find
/// Calculator.app, nor 下载 the Downloads folder. Built when first asked for (off the main thread: it reads
/// every app's Info.plist and localized names), then kept, and built again when one of the folders changed
/// (by their modification dates, compared at most every `recheckInterval`).
public final class AppIndex: @unchecked Sendable {
    public struct App: Equatable, Sendable {
        public var path: String
        /// Its name in a Chinese interface (计算器, 下载; nil: none known). An English one shows it as Finder
        /// does (`FileManager.displayName`): the bundle's English name may be another ("Playground" for
        /// Image Playground).
        public var chinese: String?
        /// Every name it goes by, to match what is typed: an app's file name without ".app", the bundle's
        /// names, its English and Chinese (simplified and traditional) ones; a place's names in Finder.
        public var names: [String]
        /// One of the folders of `places`, not an app: listed like one.
        public var isPlace: Bool

        public init(path: String, chinese: String? = nil, names: [String], isPlace: Bool = false) {
            self.path = path
            self.chinese = chinese
            self.names = names
            self.isPlace = isPlace
        }
    }

    /// Where apps are installed. The folders directly inside these are looked in too ("Chrome Apps.localized").
    public static let standardFolders = ["/Applications", "/Applications/Utilities", "/System/Applications",
                                         "/System/Applications/Utilities", "~/Applications"]
    /// Apps opened by name from elsewhere: Finder (in /System/Library/CoreServices, which `@open` doesn't search).
    public static let standardApps = ["/System/Library/CoreServices/Finder.app"]

    public static let shared = AppIndex()

    private let folders: [String]
    private let extraApps: [String]
    private let home: String?
    private let finderNames: @Sendable (_ language: String) -> [String: String]
    private let recheckInterval: TimeInterval
    private let lock = NSLock()
    /// The apps; every folder looked in, with its modification date then (nil: it didn't exist); when
    /// those dates were last compared.
    private var built: (apps: [App], folders: [String: Date?], checked: Date)?

    /// `apps`: single apps, besides those in `folders`. `home`: whose folders `places` lists (nil: none).
    /// `finderNames`: what Finder calls them in a language (`systemFinderNames`).
    public init(folders: [String] = standardFolders, apps: [String] = standardApps, home: String? = NSHomeDirectory(),
                finderNames: @escaping @Sendable (_ language: String) -> [String: String] = AppIndex.systemFinderNames,
                recheckInterval: TimeInterval = 30) {
        self.folders = folders.map { ($0 as NSString).expandingTildeInPath }
        self.extraApps = apps
        self.home = home
        self.finderNames = finderNames
        self.recheckInterval = recheckInterval
    }

    /// The apps and places as of `now`: built again first when one of the folders changed.
    public func apps(now: Date = Date()) -> [App] {
        // Held while building (a fraction of a second): a second search waits for the same index.
        lock.withLock {
            if let built {
                if now.timeIntervalSince(built.checked) < recheckInterval { return built.apps }
                if built.folders.allSatisfy({ Self.modificationDate($0.key) == $0.value }) {
                    self.built?.checked = now
                    return built.apps
                }
            }
            let scan = Self.scan(folders)
            let scanned = Set(scan.apps.map(\.path))
            let extra = extraApps.filter { !scanned.contains($0) && Self.isDirectory($0) }.map(Self.app(at:))
            let all = scan.apps + extra + (home.map { Self.places(home: $0, finderNames: finderNames) } ?? [])
            built = (all, scan.folders, now)
            return all
        }
    }

    /// The apps in `roots` and in the folders directly inside them, each once, and the folders looked in.
    static func scan(_ roots: [String]) -> (apps: [App], folders: [String: Date?]) {
        var apps: [App] = [], seen = Set<String>(), looked: [String: Date?] = [:], inside: [String] = []
        func look(in folder: String, isRoot: Bool) {
            guard looked[folder] == nil else { return }
            looked[folder] = .some(modificationDate(folder))
            let entries = (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? []
            for entry in entries.sorted() where !entry.hasPrefix(".") {
                let path = (folder as NSString).appendingPathComponent(entry)
                guard isDirectory(path) else { continue }
                if (entry as NSString).pathExtension.lowercased() == "app" {
                    if seen.insert(path).inserted { apps.append(app(at: path)) }
                } else if isRoot {
                    inside.append(path)
                }
            }
        }
        for root in roots { look(in: root, isRoot: true) }
        for folder in inside { look(in: folder, isRoot: false) }
        return (apps, looked)
    }

    /// What the app at `path` is called: its Info.plist, and its localized InfoPlist strings
    /// (`<language>.lproj/InfoPlist.strings`, or the `InfoPlist.loctable` that newer system apps have
    /// instead). An iPhone or iPad app installed on a Mac keeps them in its wrapped bundle.
    static func app(at path: String) -> App {
        let fileName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var contents = path + "/Contents", resources = contents + "/Resources"
        let wrapped = path + "/WrappedBundle"
        if !FileManager.default.fileExists(atPath: contents + "/Info.plist"),
           FileManager.default.fileExists(atPath: wrapped + "/Info.plist") {
            contents = wrapped
            resources = wrapped
        }
        let info = bundleNames(dictionary(at: contents + "/Info.plist"))
        let table = dictionary(at: resources + "/InfoPlist.loctable")
        func names(_ languages: [String]) -> [String] {
            languages.flatMap { language in
                bundleNames(table[language] as? [String: Any] ?? dictionary(at: resources + "/\(language).lproj/InfoPlist.strings"))
            }
        }
        let english = names(["en", "English", "en_US", "en-US"])
        let simplified = names(["zh-Hans", "zh_CN", "zh-CN", "zh"])
        let traditional = names(["zh-Hant", "zh_TW", "zh-TW", "zh_HK", "zh-HK"])
        let base = names(["Base"])
        // An app made for China may have its Chinese name in Info.plist itself, and no Chinese strings.
        let chinese = simplified.first ?? (info + base).first(where: \.containsHan)
        var seen = Set<String>()
        let all = ([fileName] + info + english + simplified + traditional + base).filter { seen.insert(folded($0)).inserted }
        return App(path: path, chinese: chinese, names: all)
    }

    /// The folders Finder names in its sidebar and Go menu, each with the English name macOS's localizations
    /// know it by: the home folder, its Desktop, Documents, Downloads, Pictures, Movies, Music, Public and
    /// Applications, and /Applications.
    static func placePaths(home: String) -> [(path: String, key: String)] {
        let inHome = ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music", "Public", "Applications"]
        return [(home, "Home")] + inHome.map { ((home as NSString).appendingPathComponent($0), $0) }
            + [("/Applications", "Applications")]
    }

    /// The places of `placePaths` that are there, each under its names in Finder: its file name, as Finder
    /// shows it (`FileManager.displayName`, in the system language), and what Finder calls it in English and
    /// in Chinese, simplified and traditional (`finderNames` for a language, else `fallbackNames`): 下载,
    /// 下載項目 and "downloads" all find the Downloads folder. A Chinese interface shows the simplified name.
    /// The home folder keeps its own (the user's short name, as in Finder's sidebar); "Home" and 个人
    /// (Finder's Go menu) find it.
    public static func places(home: String, finderNames: (_ language: String) -> [String: String]) -> [App] {
        let english = finderNames("en"), simplified = finderNames("zh_CN")
        let traditional = [finderNames("zh_TW"), finderNames("zh_HK")]
        return placePaths(home: home).filter { isDirectory($0.path) }.map { place in
            let chinese = simplified[place.key] ?? fallbackNames[place.key]
            let localized = [english[place.key] ?? place.key, chinese] + traditional.map { $0[place.key] }
            var seen = Set<String>()
            let names = ([(place.path as NSString).lastPathComponent, FileManager.default.displayName(atPath: place.path)]
                         + localized.compactMap { $0 }).filter { !$0.isEmpty && seen.insert(folded($0)).inserted }
            return App(path: place.path, chinese: place.key == "Home" ? nil : chinese, names: names, isPlace: true)
        }
    }

    /// Finder's Chinese names for the places, for when macOS's own can't be read (in English they are the keys).
    static let fallbackNames = ["Home": "个人", "Desktop": "桌面", "Documents": "文稿", "Downloads": "下载", "Pictures": "图片",
                                "Movies": "影片", "Music": "音乐", "Public": "公共", "Applications": "应用程序"]

    /// What Finder calls the places in `language` (an .lproj name: "en", "zh_CN"), by their English names
    /// ("Downloads" = "下载"): macOS's names for its standard folders, and Finder's own for the home folder
    /// ("Home" = "个人", in its Go menu). Empty where they can't be read.
    public static func systemFinderNames(_ language: String) -> [String: String] {
        let folders = "/System/Library/CoreServices/SystemFolderLocalizations/\(language).lproj/SystemFolderLocalizations.strings"
        let finder = "/System/Library/CoreServices/Finder.app/Contents/Resources/\(language).lproj/Localizable.strings"
        var names = dictionary(at: folders).compactMapValues { $0 as? String }
        names["Home"] = dictionary(at: finder)["Home"] as? String
        return names
    }

    static func folded(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// CFBundleDisplayName and CFBundleName, those that are there.
    static func bundleNames(_ strings: [String: Any]) -> [String] {
        ["CFBundleDisplayName", "CFBundleName"].compactMap {
            (strings[$0] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    /// A property list or strings file (binary, XML, text; UTF-8 or UTF-16) as a dictionary; empty if
    /// there is none.
    static func dictionary(at path: String) -> [String: Any] {
        guard let data = FileManager.default.contents(atPath: path),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    static func modificationDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    static func isDirectory(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}
