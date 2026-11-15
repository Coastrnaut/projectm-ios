# Quickstart: OUT-006 Output Mirroring Toggle

A. Simulator: launch with `-uitestExternalDisplay`, Settings › External Display › Output › Clean output; Done; tap `ext+`. The hidden `externalOutputMode` probe reads `mode=clean target=external overlays=hidden externalViews=1`; `ExternalOutputModeUITests` automates this. `ExternalOutputModeAppTests` proves the routing and the single capture.

B. `{device}` (D1 with a real external display, OUT-006-T10): set a logo and the Photo visual, connect a display; Same scene shows the logo on the display; switch to Clean output: the logo disappears from the display at once, the music keeps playing without a gap; disconnect: the phone shows the logo again.
