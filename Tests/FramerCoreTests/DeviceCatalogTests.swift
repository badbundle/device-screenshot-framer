import Testing
@testable import FramerCore

@Suite struct DeviceCatalogTests {
    @Test(arguments: [
        (PixelSize(1320, 2868), "iPhone 17 Pro Max"),
        (PixelSize(1206, 2622), "iPhone 17 Pro"),
        (PixelSize(1290, 2796), "iPhone 16 Plus"),
        (PixelSize(1179, 2556), "iPhone 16"),
        (PixelSize(1170, 2532), "iPhone 14"),
        (PixelSize(1284, 2778), "iPhone 14 Plus"),
        (PixelSize(1080, 2340), "iPhone 13 Mini"),
        (PixelSize(1242, 2688), "iPhone 11 Pro Max"),
        (PixelSize(1125, 2436), "iPhone 11 Pro"),
        (PixelSize(828, 1792), "iPhone 11"),
        (PixelSize(750, 1334), "iPhone SE"),
        (PixelSize(1260, 2736), "iPhone Air"),
        (PixelSize(2048, 2732), "iPad Pro (12.9-inch) (4th generation)"),
        (PixelSize(2064, 2752), "iPad Pro 13-inch (M4)"),
        (PixelSize(1668, 2388), "iPad Pro (11-inch)"),
        (PixelSize(1668, 2420), "iPad Pro 11-inch (M4)"),
        (PixelSize(1640, 2360), "iPad Air (2020)"),
        (PixelSize(1536, 2048), "iPad Mini (2019)"),
    ])
    func detectsPortrait(_ size: PixelSize, _ expected: String) {
        let result = DeviceCatalog.detect(size)
        #expect(result?.device.name == expected)
        #expect(result?.orientation == .portrait)
    }

    @Test func detectsLandscape() {
        let result = DeviceCatalog.detect(PixelSize(2622, 1206))
        #expect(result?.device.name == "iPhone 17 Pro")
        #expect(result?.orientation == .landscape)
    }

    @Test func unknownSizeIsNil() {
        #expect(DeviceCatalog.detect(PixelSize(1000, 1000)) == nil)
        #expect(DeviceCatalog.detect(PixelSize(1488, 2266)) == nil) // iPad mini 6/7: deliberately unsupported
    }

    @Test func namedLookupIsCaseInsensitiveAndSupportsAliases() {
        #expect(DeviceCatalog.named("iphone 16 pro")?.name == "iPhone 16 Pro")
        #expect(DeviceCatalog.named("iPhone 15 Pro")?.name == "iPhone 16")
        #expect(DeviceCatalog.named("iPad Pro 13")?.name == "iPad Pro 13-inch (M4)")
        #expect(DeviceCatalog.named("Nokia") == nil)
    }

    @Test func tableIsConsistent() {
        var seen: Set<String> = []
        for device in DeviceCatalog.all {
            #expect(device.colors.contains(device.defaultColor), "\(device.name) default colour not in colours")
            #expect(!seen.contains(device.name), "duplicate device \(device.name)")
            seen.insert(device.name)
            #expect(device.screenSize.width < device.screenSize.height, "\(device.name) screen size must be portrait")
            if let frameScreen = device.frameScreenSize {
                // Borrowed frames must be close in aspect so aspect-fill crops little.
                let ratio = device.screenSize.aspect / frameScreen.aspect
                #expect(abs(ratio - 1) < 0.02, "\(device.name) borrowed frame aspect differs by \(ratio)")
            }
        }

        // Priorities must be unique within a size group so detection is deterministic.
        let groups = Dictionary(grouping: DeviceCatalog.all, by: \.screenSize)
        for (size, devices) in groups {
            let priorities = devices.map(\.priority)
            #expect(Set(priorities).count == priorities.count, "duplicate priority in \(size) group")
        }
    }

    @Test func frameFilename() {
        let air = DeviceCatalog.named("iPad Air (2020)")!
        #expect(air.frameFilename(color: "Sky Blue") == "Apple iPad Air (2019) 2020 Sky Blue Portrait.png")
        let pro = DeviceCatalog.named("iPhone 17 Pro")!
        #expect(pro.frameFilename(color: "Deep Blue") == "Apple iPhone 17 Pro Deep Blue.png")
    }
}
