# Mouse animation art

Created with the built-in image generation tool, using the existing capybara, corgi, turtle, sunglasses, and beaver-tail artwork as references. See `prompt.txt` for the generation prompt.

- `mouse_walk_right.png`: transparent horizontal sheet, six 64×64 frames (384×64 overall).
- `mouse_walk_right.aseprite`: editable six-frame animation, 80 ms per frame.
- `mouse_thumb.png`: first frame.
- `mouse_walk_preview.gif`: enlarged animation on white.
- `walk_comparison.gif`: capybara, corgi, turtle, mouse, left to right; 80 ms per frame, 24-frame shared loop.
- `mouse_contact_sheet.png`: all six mouse frames on white for outline inspection.
- `mouse_generated_chroma.png` and `mouse_generated_transparent.png`: generation intermediates before final downsampling and edge cleanup.

The mouse uses the capybara/corgi six-frame timing and horizontal sheet contract; the turtle reference has eight frames. Each mouse frame has the same silhouette bounds, a right-facing profile, and distinct leg poses. Green background and green outline spill were removed. No new drawing was added during image processing.

Published on 2026-09-13 as test-only, remote-only SKU `mouse`, base price 1,000 coins. Granted once to the exact Rohan account without coin or equipment changes. CDN version `a76ae5105dc5`; live visibility and ownership checks are in `publication-verification.json`. No app renderer change was required. The art format is shared by iOS and Android; backend capability filtering remains responsible for older-client compatibility when published. Character render metadata and accessory placement still need in-app verification at catalog integration time.

Review the loop for foot motion and the last-to-first transition, and compare the character size and outline to the existing animals. Source dimensions, six distinct frames, transparency, and Aseprite round-trip are checked locally.
