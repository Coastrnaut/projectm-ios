# Quickstart: OUT-007 Corner-Pin Warp

A. Simulator: launch with `-uitestExternalDisplay`, tap `ext+`, open Settings › External Display › Corner pin…; the hidden `externalCornerPin` probe reads `card=shown`; nudge the top-left corner right; the probe's corners change; Reset reads `pin=identity`; Done hides the card. `CornerPinUITests` automates this; `CornerPinTests` (package) and `CornerPinAppTests` prove the mapping, the foldover rules, the layer projection and the device/recording isolation.

B. `{device}` (D1 with a real projector, OUT-007-T12): aim the projector off-axis at a wall, open Corner pin…, drag the four handles until the test card's outline matches the screen, Done; the live visual fills the corrected shape, straight lines stay straight, the phone's own picture and a short recording are unwarped; relaunch keeps the correction.
