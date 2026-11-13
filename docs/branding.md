# Brand assets

RubyFunk uses the original Punktfunk mark and lettering with Rubylight colors.
The palette covers the README logo, web logos, favicons and packaged app artwork.

## Palette

Colors come from the [Rubylight banner](https://github.com/RamazanKara/Rubylight/blob/main/docs/media/banner.svg).

| Role | Color |
| --- | --- |
| Ruby | `#C41242` |
| Pink circle | `#FF477B` |
| Pale overlap and dark-surface lettering | `#ECE8EC` |
| Dark icon background | `#210E18` |

Apple's rendered materials and gradients shade these colors. Monochrome launcher icons
follow the OS tint; tray status dots keep their status colors.

## Build inputs

Run commands below from the repository root. PNG and ICO assets are checked in;
normal builds consume them without running the generators. Xcode compiles the
Icon Composer document for macOS and iOS.

| Surface | Sources consumed by the build or package |
| --- | --- |
| README | `assets/rubyfunk-logo.svg` |
| Web | `web/src/components/{brand-mark,wordmark,logo}.tsx`, `web/public/favicon.svg` |
| Docs site | `docs-site/public/favicon.svg` |
| macOS and iOS | `clients/apple/App/rubyfunk_Logo.icon/` |
| tvOS and visionOS | Icon stacks and About images in `clients/apple/App/Assets.xcassets/` |
| Windows executables and installers | `packaging/windows/branding/rubyfunk.ico` |
| Windows MSIX | `clients/windows/packaging/assets/*.png` |
| Windows tray | `packaging/windows/branding/rubyfunk-tray-*.ico` |
| Linux packages and tray | `packaging/linux/icons/hicolor/` |
| Android launcher | `clients/android/app/src/main/res/drawable/ic_launcher_foreground.xml`, `values/colors.xml` under the same `res/` directory |
| Android TV | `clients/android/app/src/main/res/drawable-*/tv_banner.png` |
| Steam Deck shortcuts | `clients/decky/assets/{icon,logo,grid,gridwide,hero}.png` |

## Regenerate artwork

For the Windows executable icon, run on Windows with PowerShell and System.Drawing:

```powershell
pwsh -File packaging/windows/branding/gen-branding.ps1
```

For Windows and Linux tray icons, use Python 3:

```sh
python3 scripts/gen-tray-icons.py
```

For tvOS layers, Top Shelf and tvOS About images, use macOS with Xcode's Icon Composer:

```sh
ICTOOL="/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool" \
  swift scripts/render-tvos-icon.swift \
  "$PWD/clients/apple/App/rubyfunk_Logo.icon" \
  "$PWD/clients/apple/App/Assets.xcassets/App Icon & Top Shelf Image.brandassets"
```

Set `ICTOOL` to the executable in your Icon Composer installation if it lives elsewhere.
Keep generator palettes and checked-in outputs together. MSIX PNGs, visionOS layers,
Android TV banners and Steam artwork also need their checked-in images updated.

## Verify a color change

Preserve vector paths, image dimensions, transparency and ICO frame sizes. Inspect small
icons and light/dark appearances. Build and inspect the target package before distributing it.

## App identity

All platforms use the RubyFunk name and the `io.github.gunu3371.rubyfunk` namespace.
See [identifiers](identifiers.md) before installing over an existing Punktfunk setup.

## Interface accents

Light controls use ruby `#C41242` with white text; dark controls use pink `#FF477B`
with dark text. Apple widgets and Live Activities share these semantic accents.
The default gamepad backdrop uses the existing Ruby palette. Saved palette selections,
Android Material You and desktop/custom web accents keep their existing behavior.
