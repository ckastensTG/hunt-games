# Splash screens and logo lockups

These are the shared boot splashes for both lines. Every title uses one of these files and never makes its own copy.

They follow the house template `TEX_Splash_TimeGalleon.png`: a white logo on black (#000000), at the same lockup size and position. The only change is the sub-line, which reads TIMELESS GAMES or BOARDS in place of VISUAL NOVELS.

| File | Size | Use |
|---|---|---|
| `TEX_Splash_TimelessGames_Landscape.png` | 3840×2160 | Desktop builds (Steam, later), trailers, store art |
| `TEX_Splash_TimelessGames_Portrait.png` | 2160×3840 | Store art, or a title locked to portrait |
| `TEX_Splash_TimelessGames_Square.png` | 2160×2160 | **iOS launch screen** (works in both orientations) |
| `TEX_Splash_Boards_Landscape.png` | 3840×2160 | The same uses, for Galleon Boards titles |
| `TEX_Splash_Boards_Portrait.png` | 2160×3840 | The same uses, for Galleon Boards titles |
| `TEX_Splash_Boards_Square.png` | 2160×2160 | **iOS launch screen** for Galleon Boards titles |
| `TEX_Logo_TimelessGames_White.png` | 2490×2218 | The lockup alone: white on transparent, for menus, credits and store art |
| `TEX_Logo_Boards_White.png` | 2490×2218 | The same lockup for Galleon Boards |

## Standard for every game: no Godot splash (Christopher, 2026-11-04)
The player sees **one** splash: the Time Galleon splash for the title's line, drawn by the device's own launch screen. Never the Godot logo, and never a second splash. Full settings are in `../android/README.md`, which covers iOS and desktop as well as Android.
- **Project:**
  - `application/boot_splash/show_image` **off**, so Godot draws only black while it starts.
  - `bg_color` #000000.
- **iOS launch screen:**
  - `storyboard/custom_image@2x` and `@3x` = the line's **Square** file (both orientations).
  - `image_scale_mode` Scale to Fit (2).
  - The background follows `bg_color`.
- **Android 12+ launch screen:**
  - `splash_screen/icon` = `../android/TEX_Android_SplashIcon_TimeGalleon.png`.
  - `branding_image` = `../android/TEX_Android_SplashBranding_TimelessGames.png` or `…_Boards.png`.
  - Black background. Android can't show a full-screen picture.
- **Desktop (Steam, later):**
  - Desktop has no launch screen of its own, so use a feature override, e.g. `boot_splash/show_image.pc=true`.
  - Point it at the line's **Landscape** file, with `stretch_mode` Keep.
- **Export filters:** ship only the files a preset uses, i.e. leave out the other line and the other orientations.

## Recreating the lockup for a new imprint
1. Take `Time Galleon logo branco vertical 300dpi.png` from the logos folder on Drive and erase the sub-line.
2. Set the new sub-line in **Michroma Regular** (OFL; it's in that Drive folder under Imprints) at these values, measured on the 300 dpi logo:
   - **Size:** 178.7 px (cap height 134 px)
   - **Weight:** about +1 px stroke, to match the original render
   - **Tracking:** −2.5 px
   - **Word space:** +40 px
   - **Baseline:** y = 2215
   - **Position:** centred horizontally, in white
3. Scale the whole lockup the same way as the files above:
   - **Landscape:** 1800 px tall, centred.
   - **Portrait and Square:** 75 % of the frame width, centred.
