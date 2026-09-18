# device-screenshot-framer

`framer` is a macOS command-line tool that drops iOS and iPadOS screenshots into Apple device frames, optionally with a marketing title, subtitle and gradient background — the kind of image you upload to App Store Connect.

- Detects the device from the screenshot's pixel size (iPhone 5s → iPhone 17 Pro Max / Air, iPads), or force one with `--device`.
- Portrait and landscape (choose which side the notch / Dynamic Island ends up on).
- Output at any size up to the screenshot's native size, aspect-fit and centred.
- **Inset mode**: title + subtitle above or below the device on a linear gradient, rendered with CoreText (system SF font or any installed font).
- Batch rendering from a JSON config.
- No Ruby, ImageMagick or Node — just CoreGraphics, CoreText and ImageIO.

Device frames are downloaded on demand from [fastlane/frameit-frames](https://github.com/fastlane/frameit-frames) and cached in `~/Library/Caches/device-screenshot-framer`. They are not part of this repository.

## Install

Requires macOS 14+ and Xcode 16+ / Swift 6.

```sh
swift build -c release
cp .build/release/framer /usr/local/bin/   # or anywhere on your PATH
```

## Quick start

```sh
# Frame a screenshot at its native size (transparent padding, PNG)
framer frame shot.png -o framed/

# Several at once, scaled to 800px wide, in a specific colour
framer frame shots/*.png -o framed/ --width 800 --color "Deep Blue"

# Solid or gradient background behind the frame
framer frame shot.png -o framed/ --background "#1E3A8A,#9333EA" --angle 160

# What devices and colours are available?
framer list-devices
```

The framed device is scaled to fit inside the output canvas and centred. Output never exceeds the screenshot's native size (App Store Connect wants native dimensions; there is nothing to gain from upscaling).

## Inset mode: title, subtitle, gradient

```sh
framer init                 # writes framer.json
framer render               # renders every entry in framer.json
framer render --config marketing/en.json --only home detail
```

A config looks like this. Every key except `screenshots` is optional.

```json
{
  "outputDirectory": "framed",
  "output": { "width": 1290, "height": 2796, "format": "png", "jpegQuality": 0.9 },
  "mode": "inset",
  "device": null,
  "frameColor": null,
  "landscapeSide": "left",
  "background": { "colors": ["#1E3A8A", "#9333EA"], "angle": 160 },
  "text": {
    "position": "top",
    "title":    { "font": "system", "size": 96, "weight": "bold",    "color": "#FFFFFF" },
    "subtitle": { "font": "system", "size": 56, "weight": "regular", "color": "#FFFFFFCC" },
    "spacing": 24
  },
  "padding": 96,
  "gap": 64,
  "deviceScale": 1.0,
  "screenshots": [
    { "path": "raw/home.png",   "title": "Plan your day",     "subtitle": "Everything in one place" },
    { "path": "raw/detail.png", "title": "Dive into details", "device": "iPhone 17 Pro", "frameColor": "Silver", "output": "02-detail" }
  ]
}
```

| Key | Meaning |
|---|---|
| `outputDirectory` | Where files go. Relative paths are resolved against the config file. |
| `output.width` / `output.height` | Canvas size. Give one and the other follows the framed image's aspect; give none for the screenshot's native size. Capped at native. |
| `output.format` | `png` (keeps transparency) or `jpeg` (flattened onto white if there is no background). |
| `mode` | `simple` (frame only) or `inset` (frame + text + background). |
| `device` / `frameColor` | Defaults for every entry; each screenshot can override. |
| `landscapeSide` | `left` or `right`: where the notch / Dynamic Island goes for landscape screenshots. |
| `background.colors` | One colour for a solid fill, two or more for a linear gradient. Hex `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`. |
| `background.angle` | CSS convention: `0` bottom→top, `90` left→right, `180` top→bottom (default). |
| `background.locations` | Optional colour stops in `0…1`, one per colour. |
| `text.position` | `top` or `bottom`. The device is pushed to the opposite edge. |
| `text.title` / `text.subtitle` | `font` (`"system"` or an installed font name), `size` in px, `weight` (`ultraLight … black`), `color`. |
| `text.spacing` | Gap between title and subtitle. Default `0.4 × subtitle size`. |
| `padding` | Distance from the canvas edge to text and device. Default 5% of canvas width. |
| `gap` | Distance between the text block and the device. Default = `padding`. |
| `deviceScale` | Shrink the device inside its available area (`1` = fill). |
| `screenshots[].path` | Input file. `title`, `subtitle`, `device`, `frameColor`, `background`, `landscapeSide` override the defaults; `output` sets the file name (no extension). |

Text wraps and is centred. Newlines in `title`/`subtitle` are honoured.

## Devices

Detection is by exact pixel size. `framer list-devices` prints the table; `--device` accepts a name or alias (case-insensitive), e.g. `--device "iPhone 15 Pro"`.

Some current devices have no frame in frameit-frames. They borrow the closest one and the screenshot is aspect-filled into it (the tiny overflow disappears under the bezel):

| Screenshot | Frame used |
|---|---|
| iPhone 15 / 15 Pro (1179×2556) | iPhone 16 |
| iPhone 15 Plus / 15 Pro Max (1290×2796) | iPhone 16 Plus |
| iPhone 16e / 17e (1170×2532) | iPhone 14 |
| iPhone Air (1260×2736) | iPhone 17 |
| iPad Pro 13" M4, iPad Air 13" (2064×2752) | iPad Pro 12.9" (4th gen) |
| iPad Pro 11" M4 (1668×2420) | iPad Pro 11" |
| iPad Air 11" M2/M3, iPad 10th/11th gen (1640×2360) | iPad Air (2020) |

You can force any frame onto any screenshot with `--device`; the screenshot is scaled to fill the frame's screen and clipped, so a big aspect mismatch will crop.

## Frames cache

```sh
framer download-frames        # prefetch every Apple frame (~130 files)
framer frame … --offline      # never touch the network
FRAMER_CACHE_DIR=/path framer …   # or --cache-dir
```

The cache is versioned by the upstream release. If the network is unreachable the last cached version is used.

## Development

```sh
swift build
swift test          # 70+ tests; synthetic frames, no network
```

Layout: `Sources/FramerCore` (library: device table, frame store, geometry, rendering, config) and `Sources/framer` (the CLI). Everything renders through CoreGraphics in top-left pixel coordinates; the only place y is flipped is `CGRect.flipped(in:)`.
