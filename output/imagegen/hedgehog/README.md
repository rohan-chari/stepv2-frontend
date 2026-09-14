# Hedgehog character art

Built-in imagegen produced six complete connected hedgehog walk poses. Exact generation prompt: `prompt.txt`. Background cleanup used a second built-in edit requesting unchanged complete characters on solid #00FF00, followed by chroma removal. No anatomy was drawn or animated separately.

Deliverables: `hedgehog_walk_right.png` (576×96; six 96×96 poses), `hedgehog_thumb.png`, `hedgehog-walk-preview.gif` (120 ms/frame), `contact-sheet.png`, and `hedgehog_walk_right.aseprite`.

White-background contact sheet inspected; six distinct frames, transparent margins and foot boundary at 78/96 verified by `assemble.py`. Candidate baseline offset is -0.03125, aligning that boundary to 50/64. Human playback review remains necessary for gait and loop quality.

Local art proposal only. No CDN publication, catalog creation, ownership grant, price, power, app code or backend policy changes. No app builds/tests run for these standalone artwork files.
