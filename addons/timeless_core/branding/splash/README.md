# Splash screens and logo lockups

These are the shared boot splashes for both lines. Every title uses one of these files and never makes its own copy.

They follow the house template `TEX_Splash_TimeGalleon.png`: a white logo on black (#000000), at the same lockup size and position. The only change is the sub-line, which reads TIMELESS GAMES or BOARDS in place of VISUAL NOVELS.

| File | Size | Use |
|---|---|---|
| `TEX_Splash_TimelessGames_Landscape.png` | 3840×2160 | Timeless Games titles locked to landscape |
| `TEX_Splash_TimelessGames_Portrait.png` | 2160×3840 | Timeless Games titles locked to portrait |
| `TEX_Splash_TimelessGames_Square.png` | 2160×2160 | Timeless Games titles that rotate (`window/handheld/orientation` = sensor) |
| `TEX_Splash_Boards_Landscape.png` | 3840×2160 | Galleon Boards titles locked to landscape |
| `TEX_Splash_Boards_Portrait.png` | 2160×3840 | Galleon Boards titles locked to portrait |
| `TEX_Splash_Boards_Square.png` | 2160×2160 | Galleon Boards titles that rotate |
| `TEX_Logo_TimelessGames_White.png` | 2490×2218 | The lockup alone: white on transparent, for menus, credits and store art |
| `TEX_Logo_Boards_White.png` | 2490×2218 | The same lockup for Galleon Boards |

## Godot boot splash settings
- **`application/boot_splash/bg_color`:** set to `#000000`. Bars at any aspect ratio then blend into the image.
- **`application/boot_splash/image`:** pick by orientation.
  - A title that rotates (hunt-games currently uses `window/handheld/orientation=6`) uses the **Square** file.
  - A title locked to one orientation uses **Landscape** or **Portrait**.
- **`application/boot_splash/stretch_mode`:** set to `Keep`. This fits the whole image on screen and never crops the logo.
- **Per-title override:** use a feature tag where one engine-family project hosts both lines, for example `application/boot_splash/image.title_<id>`.
- **Before Godot starts:** set the native launch screens to black too, so nothing flashes white before Godot's splash. That means the iOS launch screen background and the Android splash background.

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
