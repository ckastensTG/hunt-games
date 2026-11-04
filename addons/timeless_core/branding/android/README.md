# Launch screens: one Time Galleon splash, no Godot splash

Every title shows the Time Galleon splash once, drawn by the phone's own launch screen, and nothing from Godot (Christopher, 2026-11-04: standard for all games).

**Project setting:** `application/boot_splash/show_image` = **off** (Godot draws only black while it starts), `bg_color` #000000. The `image` setting can stay on the Square splash; nothing shows it while `show_image` is off.

## iOS
In the iOS export preset:
- `storyboard/custom_image@2x` and `storyboard/custom_image@3x`: `res://addons/timeless_core/branding/splash/TEX_Splash_TimelessGames_Square.png`
- `storyboard/image_scale_mode`: **Scale to Fit** (2). With "Same as Logo" (0), Godot 4.7.2 writes `contentMode="center"`, which shows the 2160 px image at full size.
- `storyboard/use_custom_bg_color` off: the background follows `boot_splash/bg_color` (black).

## Android
Android 12 and later draw their own launch screen: a round icon in the middle and an optional wordmark at the bottom, on a plain colour. A full-screen picture isn't possible there.

| File | Size | Preset option |
|---|---|---|
| `TEX_Android_SplashIcon_TimeGalleon.png` | 1152×1152 (288 dp at 4×), the emblem inside the 192 dp circle Android keeps | `splash_screen/icon` |
| `TEX_Android_SplashBranding_TimelessGames.png` | 800×320 (200×80 dp at 4×), TIME GALLEON / TIMELESS GAMES | `splash_screen/branding_image` |
| `TEX_Android_IconBackground_Black.png` | 432×432, black | `launcher_icons/adaptive_background_432x432`; Android also uses it as the launch screen's background |
| `TEX_Android_SplashIcon_Blank.png` | 1024×1024, transparent | Not used now: a plain black launch screen, if a title ever wants one |

Also: `splash_screen/background_color` black. Leave `splash_screen/disable_godot_boot_splash` off.

## Desktop
No launch screen of its own: with `show_image` off, a desktop build starts on black. Revisit for the Steam launch (a feature override such as `boot_splash/show_image.pc=true` would bring the splash back there only).
