/// The name and version the running app reports about itself.
///
/// Read from the bundle's Info.plist, so the screen shows exactly what the build stamped in: the
/// version comes from the release tag and the build number from the commit count (ADR 0004),
/// never from a string in the source tree.
public struct AppInfo: Equatable, Sendable {
    /// What a missing Info.plist value is shown as.
    public static let unknown = "unknown"

    /// The name shown under the icon.
    public let name: String

    /// The marketing version, `CFBundleShortVersionString`.
    public let version: String

    /// The build number, `CFBundleVersion`.
    public let build: String

    /// The version as the About section shows it, such as `1.2.0 (345)`.
    public var displayVersion: String { "\(version) (\(build))" }

    /// Creates the info from explicit values.
    public init(name: String, version: String, build: String) {
        self.name = name
        self.version = version
        self.build = build
    }

    /// Reads the info from a bundle's Info.plist dictionary.
    ///
    /// A missing key falls back to `unknown` rather than an empty string, so a build that lost its
    /// version says so on screen instead of hiding it.
    public init(infoDictionary: [String: Any]?) {
        let info = infoDictionary ?? [:]
        let displayName = info["CFBundleDisplayName"] as? String
        let bundleName = info["CFBundleName"] as? String
        self.init(
            name: displayName ?? bundleName ?? AppInfo.unknown,
            version: (info["CFBundleShortVersionString"] as? String) ?? AppInfo.unknown,
            build: (info["CFBundleVersion"] as? String) ?? AppInfo.unknown
        )
    }
}
