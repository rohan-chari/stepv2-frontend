# Gold locked-item artwork

Locked character cards and wardrobe accessory tiles now use the existing gold button color for their lock. A 16% black overlay sits above the artwork and below the lock. Owned artwork is unchanged, and the overlay ignores pointer input. Main Shop accessory cards that display only prices do not gain a new lock indicator.

Validation: two new visual expectations failed before the change; all 59 focused Shop/wardrobe tests passed afterward. Flutter analysis is clean. Independent review approved the change. The known 36 baseline admin test failures from build 19 were not rerun for this localized styling change.

Release target: iOS 2.3.13 (20), matching Android 203150. Build/upload and replacement App Review submission are pending. Backend unchanged; no API or ownership-policy changes. Existing supported-content behavior remains compatible with older clients.

## Manual checklist

- Shop → Characters: locked avatars show one centered gold lock over slightly darkened artwork; owned avatars remain clear. Artwork taps and owned Edit buttons still work.
- Character Edit → wardrobe: locked accessories have the same layering within their artwork bounds; owned accessories and the character preview stay clear. Selecting a locked accessory still opens its preview.
- Settings → Shop tutorial: verify character/wardrobe locks and spotlight alignment. Repeat Shop in the offline billing preview.
- Check small iPhone and Android screens in day/night themes: no clipping, overlay beyond the artwork, or blocked controls.

No manual device pass is claimed; automated widget coverage verifies presentation and interaction. Race sprites, powerup cards and general race/tab tutorials do not use this widget.
