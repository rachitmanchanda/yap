# Yap UI quality specification

Yap's interface is built on a four-point layout grid, semantic typography, restrained
materials, and causal feedback. New UI should be composed from design-system primitives rather
than styled independently inside feature views.

## Foundations

- Spacing: `4, 8, 12, 16, 20, 24, 32, 40`.
- App horizontal margin: `20`; keyboard horizontal margin: `16`.
- Content begins `12` points below the safe area or navigation row.
- Sections are separated by `16` points.
- Touch targets are at least `44 × 44` points.
- Radii: `12` chips, `18` inputs, `24` cards, `30` sheets and docks.
- Icon sizes: `16`, `20`, and `24`.
- Typography uses `YapType` roles. Fixed font sizes are reserved for the Yap mark, waveform
  annotations, and intentional onboarding display moments.

## Screen anatomy

Pushed screens use the following order:

1. system safe area;
2. `YapNavigationHeader`;
3. 12-point gap;
4. `YapScreenHeading`;
5. 16-point section rhythm;
6. scrolling content;
7. `YapBottomDock` when persistent actions are required.

Sheets use `YapSheetSurfaceModifier`. Large translucent surfaces must not be stacked on another
light translucent surface. Scroll content fades beneath fixed chrome rather than ending at a hard
divider.

## Interaction quality

- Press feedback starts immediately and uses `YapMotion.press`.
- Haptics fire only when an action commits or a meaningful state changes.
- Gesture-driven movement must be interruptible.
- Reduce Motion removes ambient travel and overshoot while retaining state feedback.
- Reduce Transparency replaces layered glass with a more opaque surface.
- Loading work must not block cancellation or add latency to dictation.

## Definition of done

- App, keyboard, share extension, and Live Activity schemes build.
- No content collides with a safe area, dock, sheet edge, or keyboard host.
- Every interactive control has a meaningful accessibility label and a 44-point hit target.
- Dynamic Type does not clip primary content.
- Empty, loading, error, denied-permission, offline, and populated states are intentional.
- `python3 Tools/UIAudit/ui_audit.py --strict` passes.
- UI screenshot tests pass on small, standard, and large iPhones.
- Recording startup and speak-to-insert latency do not regress.

Run the executable gate before review:

```sh
Tools/UIAudit/run_ui_quality_gate.sh
```

Pass a custom Xcode destination as the first argument when needed. Physical-device review remains
required for Messages and WhatsApp keyboard hosting, microphone handoff, Reduce Transparency,
Increase Contrast, Reduce Motion, and paste-permission behavior because Simulator does not model
those paths faithfully.

## Documented exceptions

The audit allows numeric geometry inside `WaveformView.swift`, ambient onboarding physics,
the animated stream identity metric, target palette declarations, and the design-system foundation
itself. Palette values are centralized by target because the keyboard extension has a separate
launch and memory budget. Any new exception must be added here with a product reason before it is
added to the audit allowlist.
