# Menu bar icon brief

Reference drawing: `design/volcaclock-icon.svg` (18 x 18 viewBox, 1 unit = 1 pt).

## What to build

Replace the current menu bar icon with this metronome: a solid trapezoid body, the needle and its pivot knocked out in negative space, the needle continuing in positive outside the body on the upper left, and the current tempo knocked out in the lower part of the body.

One single icon, two states:

- Running (the clock is synced and sending): the body shows the current BPM, rounded to an integer, for example 120.
- Idle (nothing syncing, no tempo): the same icon with the number area left empty. Keep the empty body as default; add one constant so the idle label can be switched to `--` later.

No second outline icon. The appearing number is the running signal.

## How to draw it

Do not load the SVG at runtime: NSImage support for SVG `<text>` and `<mask>` is unreliable, and the number changes live. Redraw the icon in code from the geometry below, into an 18 x 18 pt NSImage with `isTemplate = true`, so macOS tints it for light and dark menu bars. Redraw only when the displayed integer BPM changes or the state switches, not on every beat.

Geometry (y axis pointing down, as in the SVG; flip or use a flipped image context):

- Body path: M6.6 1.5 H11.4 L16.5 15.1 Q16.9 16.5 15.45 16.5 H2.55 Q1.1 16.5 1.5 15.1 Z. Fill it and also stroke it at 1.5 pt with round joins (the stroke is part of the silhouette).
- Needle: line from (9, 7.7) to (1.6, 1.5), 1.2 pt, round caps. Knocked out inside the body, drawn in positive outside it.
- Pivot: circle centered (9, 7.7), radius 1.25, knocked out.
- Counterweight: rounded rect 2.6 x 1.6, corner radius 0.4, centered at (3.25, 2.9), rotated -50 degrees, drawn in positive (it sits fully outside the body).
- Tempo: system font, bold, 6.2 pt, monospaced digits (`NSFont.monospacedDigitSystemFont(ofSize: 6.2, weight: .bold)`), centered horizontally on x = 9, baseline at y = 15.2. Knocked out.

Knockout technique: draw the body, then draw needle, pivot and digits with `NSGraphicsContext.current?.compositingOperation = .destinationOut` (or `.clear`). Then, back in normal compositing, draw the needle clipped to the area outside the body, and the counterweight.

## Checks

- At 18 pt on a Retina display, a 3 digit tempo stays clear of the slanted sides. Check 60, 120, 188 and 200.
- Check the icon in both light and dark menu bars, and that the idle state shows an empty body.
- Do not change anything else in the app.
