# Mouse revision 2

Published as CDN version `109b9d1eb391`, same test-only Mouse catalog item and existing Rohan ownership.

- `mouse_walk_right.png`: 1536×128 RGBA horizontal sheet; 12 frames of 128×128.
- `mouse_walk_right.aseprite`: editable 12-frame source; 60 ms/frame, matching the app's standard 720 ms preview loop.
- `mouse-walk-preview.gif`: animation on white.
- `contact-sheet.png`: white-background frame inspection.
- `mouse_thumb.png`: first frame.
- `prompts.txt`: refinement and motion-correction prompts; generated with the built-in image tool.
- `publication-verification.json`: live catalog/manifest/ownership verification.

Generated artwork was chroma-cleaned, cropped/aligned using a common scale and stable head anchor, and downsampled with Lanczos. No hand-drawn artwork or renderer changes were introduced. Previous CDN art is retained. The existing six-frame version remains separately saved in the sibling mouse directory.

Manual review: reopen TestFlight to refresh the manifest, inspect Mouse in Shop/wardrobe and Home for clipping and loop jumps, then check Rohan's race and leaderboard character slots. Tutorial fixtures do not include Mouse. Test-only visibility is based on the release channel, not an account ACL.
