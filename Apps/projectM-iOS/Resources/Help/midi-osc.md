# MIDI and OSC

Both let a controller change settings. Both are off until you turn them on, and both work only while the app is open.

## MIDI

1. Settings › MIDI: turn on **Listen for MIDI devices**. Devices connected to this device and MIDI apps running on it are used; the network is never used.
2. Open **MIDI Mappings** and tap **Learn** next to a setting, then move a knob or fader within 30 seconds.
3. Options per mapping: **Invert**, a curve, **14-bit control**, and **Send feedback** so lights or motor faders follow changes.

**MIDI Monitor** shows the newest messages while it is open and saves nothing. A program change or note can select a scene, and **Follow MIDI clock** can set the tempo.

## OSC

OSC messages come over your own local network, never the internet.

1. Turn on **OSC receiver**. iOS asks for Local Network access the first time.
2. Send **/projectm/test** with a number from 0 to 1 to check the connection.
3. **OSC Routes** lists the addresses you can control; **Learn** adds your own.

- **Only approved devices** ignores every device you have not approved.
- **Send OSC** sends short messages, such as scene changes, beats and status, to the one local device you enter by its numeric address.
- **Find nearby devices** and **Let nearby devices find this one** use Bonjour on your local network.

## Good to know

Nothing received is kept, and device names are not stored. Mappings and routes are saved with your settings on this device.
