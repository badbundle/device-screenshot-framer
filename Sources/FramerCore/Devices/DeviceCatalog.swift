/// Every device we can frame. Screen sizes are native portrait screenshot pixels; corner radii are the
/// real display corner radius (points × scale). Frames come from fastlane/frameit-frames; devices that
/// repo does not cover borrow the closest frame via `frameScreenSize` and are aspect-filled into it.
public enum DeviceCatalog {
    public static let all: [Device] = iPhones + iPads

    /// Highest-priority device whose native size matches `size` in either orientation.
    public static func detect(_ size: PixelSize) -> (device: Device, orientation: Orientation)? {
        if let d = best(matching: size) { return (d, .portrait) }
        if let d = best(matching: size.swapped) { return (d, .landscape) }
        return nil
    }

    /// Case-insensitive lookup by canonical name or alias.
    public static func named(_ name: String) -> Device? {
        let needle = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let exact = all.first(where: { $0.name.lowercased() == needle }) { return exact }
        return all
            .filter { $0.aliases.contains { $0.lowercased() == needle } }
            .max { $0.priority < $1.priority }
    }

    private static func best(matching portrait: PixelSize) -> Device? {
        all.filter { $0.screenSize == portrait }.max { $0.priority < $1.priority }
    }

    // MARK: - iPhone

    private static let titanium = ["Black Titanium", "Desert Titanium", "Natural Titanium", "White Titanium"]

    static let iPhones: [Device] = [
        // 1320x2868
        Device(name: "iPhone 17 Pro Max", screenSize: PixelSize(1320, 2868), cornerRadius: 186, priority: 100,
               framePrefix: "Apple iPhone 17 Pro Max", colors: ["Cosmic Orange", "Deep Blue", "Silver"], defaultColor: "Silver"),
        Device(name: "iPhone 16 Pro Max", screenSize: PixelSize(1320, 2868), cornerRadius: 186, priority: 90,
               framePrefix: "Apple iPhone 16 Pro Max", colors: titanium, defaultColor: "Natural Titanium"),

        // 1206x2622
        Device(name: "iPhone 17 Pro", screenSize: PixelSize(1206, 2622), cornerRadius: 186, priority: 100,
               framePrefix: "Apple iPhone 17 Pro", colors: ["Cosmic Orange", "Deep Blue", "Silver"], defaultColor: "Silver"),
        Device(name: "iPhone 17", screenSize: PixelSize(1206, 2622), cornerRadius: 186, priority: 95,
               framePrefix: "Apple iPhone 17", colors: ["Black", "Lavender", "Mist Blue", "Sage", "White"], defaultColor: "Black"),
        Device(name: "iPhone 16 Pro", screenSize: PixelSize(1206, 2622), cornerRadius: 186, priority: 90,
               framePrefix: "Apple iPhone 16 Pro", colors: titanium, defaultColor: "Natural Titanium"),

        // 1290x2796
        Device(name: "iPhone 16 Plus", aliases: ["iPhone 15 Plus", "iPhone 15 Pro Max"],
               screenSize: PixelSize(1290, 2796), cornerRadius: 165, priority: 100,
               framePrefix: "Apple iPhone 16 Plus", colors: ["Black", "Pink", "Teal", "Ultramarine", "White"], defaultColor: "Black"),
        Device(name: "iPhone 14 Pro Max", screenSize: PixelSize(1290, 2796), cornerRadius: 165, priority: 90,
               framePrefix: "Apple iPhone 14 Pro Max", colors: ["Black", "Gold", "Purple", "Silver"], defaultColor: "Black"),

        // 1179x2556
        Device(name: "iPhone 16", aliases: ["iPhone 15", "iPhone 15 Pro"],
               screenSize: PixelSize(1179, 2556), cornerRadius: 165, priority: 100,
               framePrefix: "Apple iPhone 16", colors: ["Black", "Pink", "Teal", "Ultramarine", "White"], defaultColor: "Black"),
        Device(name: "iPhone 14 Pro", screenSize: PixelSize(1179, 2556), cornerRadius: 165, priority: 90,
               framePrefix: "Apple iPhone 14 Pro", colors: ["Black", "Gold", "Purple", "Silver"], defaultColor: "Black"),

        // 1170x2532
        Device(name: "iPhone 14", aliases: ["iPhone 16e", "iPhone 17e"],
               screenSize: PixelSize(1170, 2532), cornerRadius: 142, priority: 100,
               framePrefix: "Apple iPhone 14", colors: ["Blue", "Midnight", "Purple", "Red", "Starlight"], defaultColor: "Midnight"),
        Device(name: "iPhone 13 Pro", screenSize: PixelSize(1170, 2532), cornerRadius: 142, priority: 90,
               framePrefix: "Apple iPhone 13 Pro", colors: ["Gold", "Graphite", "Sierra Blue", "Silver"], defaultColor: "Graphite"),
        Device(name: "iPhone 13", screenSize: PixelSize(1170, 2532), cornerRadius: 142, priority: 85,
               framePrefix: "Apple iPhone 13", colors: ["Blue", "Midnight", "Pink", "Red", "Starlight"], defaultColor: "Midnight"),
        Device(name: "iPhone 12 Pro", screenSize: PixelSize(1170, 2532), cornerRadius: 142, priority: 80,
               framePrefix: "Apple iPhone 12 Pro", colors: ["Gold", "Graphite", "Pacific Blue", "Silver"], defaultColor: "Graphite"),
        Device(name: "iPhone 12", screenSize: PixelSize(1170, 2532), cornerRadius: 142, priority: 75,
               framePrefix: "Apple iPhone 12", colors: ["Black", "Blue", "Green", "Red", "White"], defaultColor: "Black"),

        // 1284x2778
        Device(name: "iPhone 14 Plus", screenSize: PixelSize(1284, 2778), cornerRadius: 160, priority: 100,
               framePrefix: "Apple iPhone 14 Plus", colors: ["Blue", "Midnight", "Purple", "Red", "Starlight"], defaultColor: "Midnight"),
        Device(name: "iPhone 13 Pro Max", screenSize: PixelSize(1284, 2778), cornerRadius: 160, priority: 90,
               framePrefix: "Apple iPhone 13 Pro Max", colors: ["Gold", "Graphite", "Sierra Blue", "Silver"], defaultColor: "Graphite"),
        Device(name: "iPhone 12 Pro Max", screenSize: PixelSize(1284, 2778), cornerRadius: 160, priority: 80,
               framePrefix: "Apple iPhone 12 Pro Max", colors: ["Gold", "Graphite", "Pacific Blue", "Silver"], defaultColor: "Graphite"),

        // 1080x2340
        Device(name: "iPhone 13 Mini", screenSize: PixelSize(1080, 2340), cornerRadius: 132, priority: 100,
               framePrefix: "Apple iPhone 13 Mini", colors: ["Blue", "Midnight", "Pink", "Red", "Starlight"], defaultColor: "Midnight"),
        Device(name: "iPhone 12 Mini", screenSize: PixelSize(1080, 2340), cornerRadius: 132, priority: 90,
               framePrefix: "Apple iPhone 12 Mini", colors: ["Black", "Blue", "Green", "Red", "White"], defaultColor: "Black"),

        // 1242x2688
        Device(name: "iPhone 11 Pro Max", screenSize: PixelSize(1242, 2688), cornerRadius: 117, priority: 100,
               framePrefix: "Apple iPhone 11 Pro Max", colors: ["Gold", "Midnight Green", "Silver", "Space Gray"], defaultColor: "Space Gray"),
        Device(name: "iPhone XS Max", screenSize: PixelSize(1242, 2688), cornerRadius: 117, priority: 90,
               framePrefix: "Apple iPhone XS Max", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 1125x2436
        Device(name: "iPhone 11 Pro", screenSize: PixelSize(1125, 2436), cornerRadius: 117, priority: 100,
               framePrefix: "Apple iPhone 11 Pro", colors: ["Gold", "Midnight Green", "Silver", "Space Gray"], defaultColor: "Space Gray"),
        Device(name: "iPhone XS", screenSize: PixelSize(1125, 2436), cornerRadius: 117, priority: 90,
               framePrefix: "Apple iPhone XS", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),
        Device(name: "iPhone X", screenSize: PixelSize(1125, 2436), cornerRadius: 117, priority: 80,
               framePrefix: "Apple iPhone X", colors: ["Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 828x1792
        Device(name: "iPhone 11", screenSize: PixelSize(828, 1792), cornerRadius: 83, priority: 100,
               framePrefix: "Apple iPhone 11", colors: ["Black", "Green", "Purple", "Red", "White", "Yellow"], defaultColor: "Black"),
        Device(name: "iPhone XR", screenSize: PixelSize(828, 1792), cornerRadius: 83, priority: 90,
               framePrefix: "Apple iPhone XR", colors: ["Blue", "Coral", "Red", "Silver", "Space Gray", "Yellow"], defaultColor: "Space Gray"),

        // 1242x2208
        Device(name: "iPhone 8 Plus", screenSize: PixelSize(1242, 2208), cornerRadius: 0, priority: 100,
               framePrefix: "Apple iPhone 8 Plus", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),
        Device(name: "iPhone 7 Plus", screenSize: PixelSize(1242, 2208), cornerRadius: 0, priority: 90,
               framePrefix: "Apple iPhone 7 Plus", colors: ["Gold", "Jet Black", "Matte Black", "Rose Gold", "Silver"], defaultColor: "Matte Black"),
        Device(name: "iPhone 6s Plus", screenSize: PixelSize(1242, 2208), cornerRadius: 0, priority: 80,
               framePrefix: "Apple iPhone 6s Plus", colors: ["Gold", "Rose Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 750x1334
        Device(name: "iPhone SE", aliases: ["iPhone SE (2nd generation)", "iPhone SE (3rd generation)"],
               screenSize: PixelSize(750, 1334), cornerRadius: 0, priority: 100,
               framePrefix: "Apple iPhone SE", colors: ["Black", "Red", "White"], defaultColor: "Black"),
        Device(name: "iPhone 8", screenSize: PixelSize(750, 1334), cornerRadius: 0, priority: 90,
               framePrefix: "Apple iPhone 8", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),
        Device(name: "iPhone 7", screenSize: PixelSize(750, 1334), cornerRadius: 0, priority: 80,
               framePrefix: "Apple iPhone 7", colors: ["Gold", "Jet Black", "Matte Black", "Rose Gold", "Silver"], defaultColor: "Matte Black"),
        Device(name: "iPhone 6s", screenSize: PixelSize(750, 1334), cornerRadius: 0, priority: 70,
               framePrefix: "Apple iPhone 6s", colors: ["Gold", "Rose Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 640x1136
        Device(name: "iPhone 5s", screenSize: PixelSize(640, 1136), cornerRadius: 0, priority: 100,
               framePrefix: "Apple iPhone 5s", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),
        Device(name: "iPhone 5c", screenSize: PixelSize(640, 1136), cornerRadius: 0, priority: 90,
               framePrefix: "Apple iPhone 5c", colors: ["Blue", "Green", "Red", "White", "Yellow"], defaultColor: "White"),

        // 1260x2736 — no upstream frame; borrows iPhone 17 (near-identical aspect, ~1px crop).
        Device(name: "iPhone Air", screenSize: PixelSize(1260, 2736), cornerRadius: 186, priority: 100,
               framePrefix: "Apple iPhone 17", frameScreenSize: PixelSize(1206, 2622),
               colors: ["Black", "Lavender", "Mist Blue", "Sage", "White"], defaultColor: "Black"),
    ]

    // MARK: - iPad

    static let iPads: [Device] = [
        // 2048x2732
        Device(name: "iPad Pro (12.9-inch) (4th generation)", aliases: ["iPad Pro 12.9", "iPad Pro (12.9-inch)"],
               screenSize: PixelSize(2048, 2732), cornerRadius: 36, priority: 100,
               framePrefix: "Apple iPad Pro (12.9-inch) (4th generation)", colors: ["Silver", "Space Gray"], defaultColor: "Space Gray"),
        Device(name: "iPad Pro", screenSize: PixelSize(2048, 2732), cornerRadius: 0, priority: 50,
               framePrefix: "Apple iPad Pro", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 2064x2752 — no upstream frame; borrows iPad Pro 12.9 4th gen (~0.7% crop).
        Device(name: "iPad Pro 13-inch (M4)", aliases: ["iPad Pro 13", "iPad Air 13-inch", "iPad Air 13"],
               screenSize: PixelSize(2064, 2752), cornerRadius: 36, priority: 100,
               framePrefix: "Apple iPad Pro (12.9-inch) (4th generation)", frameScreenSize: PixelSize(2048, 2732),
               colors: ["Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 1668x2388
        Device(name: "iPad Pro (11-inch)", aliases: ["iPad Pro 11"],
               screenSize: PixelSize(1668, 2388), cornerRadius: 36, priority: 100,
               framePrefix: "Apple iPad Pro (11-inch)", colors: ["Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 1668x2420 — no upstream frame; borrows iPad Pro 11 (crops 16px top/bottom).
        Device(name: "iPad Pro 11-inch (M4)", aliases: ["iPad Pro 11 (M4)"],
               screenSize: PixelSize(1668, 2420), cornerRadius: 36, priority: 100,
               framePrefix: "Apple iPad Pro (11-inch)", frameScreenSize: PixelSize(1668, 2388),
               colors: ["Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 1640x2360
        Device(name: "iPad Air (2020)", aliases: ["iPad Air 4", "iPad Air 5", "iPad Air 11-inch", "iPad Air 11", "iPad (10th generation)", "iPad (A16)"],
               screenSize: PixelSize(1640, 2360), cornerRadius: 36, priority: 100,
               framePrefix: "Apple iPad Air (2019) 2020", frameSuffix: " Portrait",
               colors: ["Green", "Rose Gold", "Silver", "Sky Blue", "Space Gray"], defaultColor: "Space Gray"),

        // 1620x2160
        Device(name: "iPad 10.2", aliases: ["iPad (7th generation)", "iPad (8th generation)", "iPad (9th generation)"],
               screenSize: PixelSize(1620, 2160), cornerRadius: 0, priority: 100,
               framePrefix: "Apple iPad 10.2", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),

        // 1536x2048
        Device(name: "iPad Mini (2019)", aliases: ["iPad Mini 5"],
               screenSize: PixelSize(1536, 2048), cornerRadius: 0, priority: 100,
               framePrefix: "Apple iPad Mini (2019)", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),
        Device(name: "iPad Air 2", screenSize: PixelSize(1536, 2048), cornerRadius: 0, priority: 90,
               framePrefix: "Apple iPad Air (2019) 2", colors: ["Gold", "Silver", "Space Gray"], defaultColor: "Space Gray"),
    ]
}
