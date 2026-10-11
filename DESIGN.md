---
name: MindNative landing page
description: A bright software exhibition with real Mac app views, large type, and flat controls.
colors:
  stock: "#f5f6f3"
  ink: "#10272f"
  teal: "#086b7c"
  mint: "#bff1e3"
  muted: "#3c5961"
  line: "#9aaea9"
  hover-white: "#ffffff"
typography:
  display:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "clamp(54px, 6.53vw, 96px)"
    fontWeight: 700
    lineHeight: 1.13
    letterSpacing: "-0.04em"
  headline:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "clamp(38px, 4.3vw, 62px)"
    fontWeight: 700
    lineHeight: 1.1
    letterSpacing: "-0.04em"
  title:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "22px"
    fontWeight: 700
    lineHeight: 1.3
    letterSpacing: "-0.025em"
  step-title:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "19px"
    fontWeight: 700
    lineHeight: 1.4
  body:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "16px"
    fontWeight: 400
    lineHeight: 1.65
  intro:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "clamp(18px, 1.46vw, 22px)"
    fontWeight: 500
    lineHeight: 1.45
    letterSpacing: "-0.025em"
  large-copy:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "clamp(21px, 2vw, 28px)"
    fontWeight: 400
    lineHeight: 1.45
    letterSpacing: "-0.025em"
  action:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "14px"
    fontWeight: 700
    lineHeight: 1.4
  text-link:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "14px"
    fontWeight: 700
    lineHeight: 1.5
  label:
    fontFamily: "Manrope, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif"
    fontSize: "13px"
    fontWeight: 600
  code:
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
    fontSize: "12px"
    fontWeight: 400
    lineHeight: 1.8
rounded:
  flat: "0px"
  app-frame: "10px"
  app-frame-compact: "5px"
spacing:
  small: "12px"
  medium: "20px"
  open: "24px"
  wide: "32px"
  column: "40px"
  panel: "48px"
  section-column: "72px"
  page-gutter: "clamp(20px, 3.34vw, 64px)"
  section-space: "clamp(80px, 8vw, 120px)"
components:
  button-primary:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.stock}"
    typography: "{typography.action}"
    rounded: "{rounded.flat}"
    padding: "16px 19px"
  button-primary-hover:
    backgroundColor: "{colors.teal}"
    textColor: "{colors.hover-white}"
  button-line:
    textColor: "{colors.ink}"
    typography: "{typography.action}"
    rounded: "{rounded.flat}"
    padding: "16px 0"
  text-link:
    textColor: "{colors.ink}"
    typography: "{typography.text-link}"
    padding: "9px 0"
  navigation:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    padding: "14px 0"
  view-button:
    textColor: "{colors.ink}"
    typography: "{typography.label}"
    rounded: "{rounded.flat}"
    padding: "10px 16px"
  view-button-selected:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.stock}"
  feature-row:
    textColor: "{colors.muted}"
    typography: "{typography.body}"
    rounded: "{rounded.flat}"
    padding: "23px 0 26px"
  code-panel:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.stock}"
    typography: "{typography.code}"
    rounded: "{rounded.flat}"
    padding: "18px"
  faq-row:
    textColor: "{colors.ink}"
    rounded: "{rounded.flat}"
    padding: "23px 0"
---

# Design System: MindNative landing page

## Overview

**Creative North Star: "Exhibition poster"**

The landing page presents MindNative in a bright software gallery. Large geometric type, cool matte stock, precise rules, and broad mint fields give the app room. Real app screenshots provide the central visual evidence. Controls are flat, rectangular, and direct.

This system applies only to the static public site in `landing-page/`. Its source is `landing-page/index.html`, `landing-page/styles.css`, `landing-page/script.js`, and `landing-page/assets/`. Native SwiftUI app styles are outside this scope. The app shown inside screenshots retains its own native interface.

**Key Characteristics:**

- Large Manrope headings with tight tracking.
- Cool stock, blue-green ink, teal emphasis, and mint exhibit fields.
- Real app views framed by thin rules.
- Flat rectangular actions and open column spacing.
- Short copy and clear source and build routes.

## Colors

The palette is cool, clear, and restrained. The frontmatter records the exact source values.

### Primary

- **Exhibit Teal** (`teal`): the second part of the main headline, closing headline, link hover, focus outlines, selection, scrollbar thumb, and license status dot.

### Secondary

- **Gallery Mint** (`mint`): broad screenshot and build fields, the command-copy action, and the command panel's focus outline.

### Neutral

- **Matte Stock** (`stock`): the page ground and text on dark actions and command panels.
- **Blue-green Ink** (`ink`): main text, primary action fills, command panels, and strong dividing rules.
- **Muted Ink** (`muted`): descriptive feature text, supporting privacy copy, FAQ answers, and footer details.
- **Soft Rule** (`line`): the repeated separators between build steps.
- **Hover White** (`hover-white`): primary action and command-copy hover text.

**The Committed Field Rule.** Mint fills substantial exhibit and build regions. It is a field behind content, not a decorative glow.

Selection reverses stock text onto teal. Focus uses a teal outline; the copy action uses mint on its dark panel. The source also contains local frame and command-divider colors. Those local values do not form an additional accent palette.

## Typography

**Display Font:** self-hosted Manrope, with the fallback stack in the frontmatter.

**Body Font:** Manrope, from the same variable font file at `landing-page/assets/fonts/manrope.ttf` (weights 200–800; `font-display: swap`). The source uses weights 400, 500, 600, 700, and 800.

**Code Font:** the system monospace stack in `typography.code`.

**Character:** geometric and substantial in headings, clear and open in body text. There is no fixed mathematical type ratio. The scale combines fluid display roles with fixed text and control sizes. Numbers use tabular figures. Headings use balanced wrapping.

### Hierarchy

- **Display:** `typography.display` governs the hero. At widths of 760px or less, use `clamp(48px, 9.3vw, 70px)` with line height 1.06. Its teal span becomes a separate line. At 1680px or more, size is fixed at 96px.
- **Headline:** `typography.headline` governs section headings. The FAQ heading uses `clamp(36px, 3.2vw, 46px)` and becomes 38px at 760px or less. The closing heading uses `clamp(40px, 5vw, 72px)`.
- **Title:** `typography.title` governs feature headings. Feature titles become 21px at 760px or less. Ownership detail headings use 18px. The build content title uses 28px and becomes 25px on compact layouts.
- **Step title:** `typography.step-title` governs build step headings.
- **Body:** `typography.body` is the base. Feature prose has a maximum line length of 65ch. Supporting ownership and build text uses 15px; privacy and footer text use 13px and 12px. FAQ answers have a maximum line length of 70ch.
- **Intro and large copy:** their frontmatter roles use tighter leading than ordinary paragraphs. The introduction has a 650px maximum width and becomes 18px with a 480px maximum width on compact layouts. Large ownership copy has a 650px maximum width and becomes 23px on compact layouts.
- **Actions and labels:** actions use `typography.action`; underlined text actions use `typography.text-link`; navigation and view controls use `typography.label`. Facts and captions use 12px. Use sentence case.
- **Code:** `typography.code` governs selectable build commands. Inline file names use the same monospace family at 0.88em.

**The Two-line Compact Rule.** Keep the main headline on one line above the compact breakpoint. At compact widths, put the teal phrase on its own line and retain its display scale.

## Layout

The page has a maximum width of 1680px, centered with the fluid `page-gutter`. The main spacing rhythm is recorded in frontmatter. Section gaps use `section-space`. Thin ruled divisions and column alignment organize the page.

The full header uses three equal columns and an 82px minimum height. The introductory row uses columns of 7fr, 2.5fr, and 2.5fr with a 24px gap. The fact strip uses 1.2fr, 1fr, and 1fr columns. Capability content uses two equal columns. Ownership, build, and FAQ regions use 1fr and 1.55fr columns with 72px gaps. The build field has 48px padding. The closing block uses a wide heading beside a 330px action region.

### Responsive behavior

| Query | Built behavior |
| --- | --- |
| `max-width: 1100px` | Header becomes two columns and hides its platform phrase. Intro columns become 1.6fr, 1fr, 1fr with a 20px gap. Actions use 13px type and 14px inline padding. Main column gaps become 40px. Build padding becomes 36px and its columns become 1fr and 1.65fr. |
| `max-width: 760px` | Header minimum height becomes 76px; the build link leaves the header while GitHub remains. Main headline wraps deliberately. Intro copy spans both columns above paired actions. Facts wrap; availability takes its own row. Capability, ownership, build, and FAQ regions become one column with 32px gaps. Ownership details stack. Build padding becomes 28px vertically and 20px horizontally. Closing content stacks. Footer wraps. |
| `min-width: 1680px` | Hero type is fixed at 96px. The centered page retains its maximum width. |

At compact widths, the screenshot field uses 10px horizontal padding instead of 24px. View controls take a full row, with the functions link below. Commands remain on their own lines and scroll horizontally inside the code region. The compact command region extends left by the build step's 28px indent so its text has more room.

The page uses smooth anchor scrolling, a 24px scroll offset, and a skip link that appears on keyboard focus. Reduced motion changes anchor scrolling to `auto`.

## Elevation & Depth

The public site uses no box shadows. Mint and ink fields, thin borders, clipped app views, and open stock space convey separation. The displayed native app may contain its own interface depth; do not extract those screenshot pixels into landing-page tokens.

**The Flat Exhibit Rule.** Keep page controls and content fields flat. Use a rule or a tonal field to establish their edge.

The one view-change effect is a 420ms frame reveal with `cubic-bezier(.16, 1, .3, 1)`. It changes image clipping from `inset(0 0 10% 0)` to `inset(0)`. There is no looping animation. `prefers-reduced-motion: reduce` disables the reveal. Color and FAQ icon state changes are immediate.

## Shapes

Actions, content fields, and command panels have square corners. The actual app view is the exception: its clipped frame uses `app-frame`, then `app-frame-compact` at 760px or less. It preserves the screenshot ratio of 1440:900 with `object-fit: contain`.

Most boundaries are 1px rules. The exhibit and build field have an ink border. The app frame uses its local border color. The small license status marker is a circle (7px). SVG icons use open strokes with round caps and joins; their standard size is 21px with 1.6px strokes. Navigation, text links, and copy controls use smaller versions of the same authored icons.

## Components

### Buttons and text actions

Actions are flat rectangles with a clear label and an inline SVG arrow.

- **Primary:** use `button-primary`, with a 59px minimum height and a 14px gap between label and icon. Hover changes its fill to teal and its text to white.
- **Line action:** use `button-line`, with a 1px ink bottom rule. Hover changes the text and rule to teal.
- **Text action:** use `text-link`, with a 1px bottom rule in the current text color and an 18px SVG icon.
- **Compact:** primary and line actions have a 56px minimum height and 13px text. Primary padding becomes 14px; line actions retain zero horizontal padding.
- **Focus:** interactive elements use a 3px teal outline with a 5px offset. Do not remove it. Disabled buttons use opacity 0.6 and a wait cursor.

### Navigation

The ruled header pairs the existing app icon with the MindNative name. The name uses 23px type, weight 800, and tracking of -0.035em. Compact type is 20px. The app icon is 36px, then 32px on compact layouts.

Header links are plain, un-underlined, and use `navigation`. Their gap is 32px, then 18px on compact layouts. Hover turns a link teal. Footer navigation follows the same plain-link treatment. Keep the inline SVG external arrow. Use visible link text to explain the destination.

### App specimen and view controls

The specimen is a real app screenshot in a mint field with a caption, a framed image, and controls. Its caption has a 44px minimum height. Its control footer has a 72px minimum height on larger layouts. The caption names the active view and gives one short description.

View buttons have a 44px minimum height, a transparent background, and a 1px transparent border at rest. Hover shows a teal border. The selected button reverses stock text onto ink and uses `aria-pressed="true"`. The three views are Editor, Radial layout, and Presentation. These buttons form a named group, not a tab interface.

The script reveals the controls only when JavaScript runs. It decodes the requested image before replacing the source, alt text, and caption. The latest request wins if visitors switch quickly. During loading, the frame has `aria-busy="true"` and a polite status message. Failure keeps the existing screenshot and tells the visitor to try again. Without JavaScript, the editor screenshot and caption remain visible.

### Feature rows and content fields

Feature rows are text-led, with an ink top rule and open vertical padding from `feature-row`. The final row closes the list with a bottom rule. Feature headings use ink; descriptions use muted ink. They have no raised card treatment.

The build region is a mint field with an ink border. Numbered build steps use meaningful sequential numbers and soft rules. Each step uses a 40px left indent, then 28px on compact layouts.

### Commands and copy

The command region uses `code-panel`. Commands remain selectable and preserve line breaks. Keep the command text readable before adding any copy interaction.

The copy button is a mint text action inside the ink panel. It has a top divider, a 40px minimum height, and 12px bold text. Hover turns its text white. Focus uses a mint outline. The script shows the button only when the Clipboard API exists in a secure context. While writing to the clipboard, it disables the button. A polite status region reports success or asks the visitor to copy manually. The ZIP alternative remains a visible link.

### FAQs

FAQs use native `details` and `summary` elements. They work with a keyboard and with JavaScript disabled. Each row has an ink top rule; the last row also has a bottom rule. Summaries use 17px bold text and 23px vertical padding, then 16px type and 22px padding on compact layouts.

Hover turns the summary teal. Focus keeps the common visible outline. Opening a row rotates its SVG plus by 45 degrees. Answers use muted ink, 15px text, a maximum line length of 70ch, and 24px bottom padding. Multiple answers can stay open.

### Copy

Use short sentences and direct instructions, following the user's ASD-STE100 preference. Preserve the difference between getting source and downloading a packaged app. Source actions and build instructions must remain clear for Mac users and developers. Use real screenshots, current availability, and supported-system facts. Describe local files and optional Apple Intelligence without erasing the stated network requests. Product facts live in `PRODUCT.md`; update that evidence before changing claims.

## Do's and Don'ts

### Do:

- **Do** use the frontmatter tokens and the source CSS as the landing-page system.
- **Do** retain the existing MindNative name, app icon, and real app screenshots.
- **Do** use broad mint fields, thin rules, and flat rectangular controls.
- **Do** preserve visible focus, honest loading and copy feedback, and reduced-motion behavior.
- **Do** write short sentences with clear source and build actions.

### Don't:

- **Don't** apply this landing-page system to the native SwiftUI app.
- **Don't** replace the real app exhibit with invented product visuals or proof claims.
- **Don't** add raised cards, decorative gradients, or offset shadows to this flat gallery world.
- **Don't** hide essential content behind JavaScript-only interactions.
- **Don't** label a source link as an app download or remove the network details from privacy copy.
