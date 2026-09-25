# LYLLTH repository rules

LYLLTH is a native macOS NIGHTSHAPE instrument and workstation. Preserve the established DrumKit visual language and the existing behavior unless a request explicitly changes it.

## Permanent in-app menu rule

- Generic Apple product menus are prohibited inside the LYLLTH interface.
- Do not use SwiftUI `Menu`, `.contextMenu`, menu-styled `Picker`, `confirmationDialog`, or a stock `.popover` as the presentation for a LYLLTH product control.
- Every in-app dropdown, submenu, contextual action surface, selector, and option panel must use the shared NIGHTSHAPE implementation: `LYNightshapeMenuOverlay`, `LYNightshapeMenuHeader`, `LYNightshapeMenuDivider`, `LYNightshapeMenuRow`, and `lyNightshapeMenuChrome`.
- NIGHTSHAPE menu surfaces stay matte, square, sharply bordered, high-contrast, and restrained. Use Adam for labels, the approved thin numeric face for numbers, and cyan/indigo/purple only for meaningful state.
- Preserve keyboard access, VoiceOver labels, outside-click dismissal, current selection state, and the original action behavior when replacing a menu.
- System-owned macOS surfaces are allowed only when the operating system must own the workflow, such as Open/Save panels, permissions, authentication, and the standard application menu bar.
- Before handing off UI work, audit the Swift source for forbidden product-menu APIs and visually inspect every custom menu affected by the change.

## General constraints

- Native SwiftUI and AppKit integration only; no WebView wrappers.
- Keep the near-black matte chassis, crisp one-pixel boundaries, and restrained NIGHTSHAPE accents.
- The LYLLTH wordmark always uses `NIGHTSHAPE-Bold`; interface labels use Adam; numeric readouts do not use NIGHTSHAPE.
- Prefer small, focused changes and preserve unrelated work in the shared checkout.
