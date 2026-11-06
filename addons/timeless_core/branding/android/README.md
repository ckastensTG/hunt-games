# Launch screens: one Time Galleon splash, never the Godot logo

Every title shows the Time Galleon splash once, and never the Godot logo (Christopher, 2026-11-04: standard for all games).
- **iOS:** the phone's own launch screen draws it.
- **Android:** Godot's boot splash draws it, and the phone's launch screen is plain black (changed 2026-11-06, see below).

**Project settings:**
- `application/boot_splash/show_image` = **off**, with the feature override `show_image.android` = **on**.
- `image` = the line's **Square** splash: `../splash/TEX_Splash_TimelessGames_Square.png`, or `TEX_Splash_Boards_Square.png` for Galleon Boards titles.
- `bg_color` #000000.

## iOS
In the iOS export preset:
- `storyboard/custom_image@2x` and `storyboard/custom_image@3x`: `res://addons/timeless_core/branding/splash/TEX_Splash_TimelessGames_Square.png`
- `storyboard/image_scale_mode`: **Scale to Fit** (2). With "Same as Logo" (0), Godot 4.7.2 writes `contentMode="center"`, which shows the 2160 px image at full size.
- `storyboard/use_custom_bg_color` off: the background follows `boot_splash/bg_color` (black).

To check on the next iPhone run: the iOS launch screen may also go before Godot's first frame, leaving a black gap like Android's. If it does, add `boot_splash/show_image.ios=true`. Godot then shows the same Square image straight after the launch screen, so it still looks like one splash.

## Android
**Why Godot draws it here:** the phone's launch screen goes away as soon as the game's window opens, which is long before Godot's first frame. Godot builds its shaders before that frame. On a moto g(20) this takes about 6 s on a normal launch and about 25 s on the first launch after install. With `show_image` off, all of that time was black. Godot's boot splash stays up until the first frame, so it covers the whole wait.

**In both Android presets:**
- `splash_screen/icon` = `TEX_Android_SplashIcon_Blank.png`
- `splash_screen/branding_image` empty
- `splash_screen/background_color` black
- Leave `splash_screen/disable_godot_boot_splash` off.

The phone shows black for a moment, then the Time Galleon splash until the menu appears.

| File | Size | Use |
|---|---|---|
| `TEX_Android_SplashIcon_Blank.png` | 1024×1024, transparent | `splash_screen/icon`: a plain black launch screen (in use since 2026-11-06) |
| `TEX_Android_IconBackground_Black.png` | 432×432, black | `launcher_icons/adaptive_background_432x432`; Android also uses it as the launch screen's background |
| `TEX_Android_SplashIcon_TimeGalleon.png` | 1152×1152 (288 dp at 4×), the emblem inside the 192 dp circle Android keeps | Not used now. It was `splash_screen/icon` until 2026-11-06, but it only showed for a moment before the black wait |
| `TEX_Android_SplashBranding_TimelessGames.png` | 800×320 (200×80 dp at 4×), TIME GALLEON / TIMELESS GAMES | Not used now (was `splash_screen/branding_image`) |
| `TEX_Android_SplashBranding_Boards.png` | 800×320, TIME GALLEON / BOARDS, same layout | Not used now (was the Galleon Boards `branding_image`, added by the series thread, 2026-11-04) |

Keep the emblem and wordmark files: they'd come back if the phone's launch screen could ever be held until Godot's first frame.

## Desktop
No launch screen of its own: with `show_image` off, a desktop build starts on black. Revisit for the Steam launch: a feature override such as `boot_splash/show_image.pc=true` would bring the splash back there only.
