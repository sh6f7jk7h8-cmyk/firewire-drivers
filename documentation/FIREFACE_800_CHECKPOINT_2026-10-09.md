# Fireface 800 working checkpoint — 2026-10-09

## Frozen implementation

- Branch: `codex/fireface-studio`.
- Last audio fix before this checkpoint: `2ae0953` (`Enable FF800 PCM fetching after streams start`).
- Local app/driver artifact: `dist/FirefaceStudio-Dev-build16.app`, version `0.5.0`, driver build `16`.
- App executable SHA-256: `295970199da0319968cf5f0d1c4f482094721b01aa6b3d882e0541f6e99ced0b`.
- Driver executable SHA-256: `99c95053e988d052b25214dae4d43cada9ae93d20be8d31c7a55f18e470cbdc5`.
- `codesign --verify --deep --strict` passes for this local artifact. It is **ad-hoc signed**, without an Apple team identity; this is a development build, not a SIP-enabled release.

## Verified on the owner's Mac

- macOS `27.0.1` on Apple Silicon. SIP was disabled during this test.
- `systemextensionsctl list` showed `com.marsproo.firefacestudio.driver` build `16` activated and enabled.
- Core Audio published `RME Fireface 800`, 28 input and 28 output channels at 48 kHz, and selected it as the default and system output.
- With monitors connected to physical outputs 1/2, the owner heard the same 3-second 440 Hz signal from the Mac twice. The first successful test occurred before launching Fireface Studio, so playback does not require the mixer UI to remain open.
- The saved matrix initially displayed playback 1 -> output 1 and playback 2 -> output 2 at 0 dB. Both were returned to approximately 0 dB after a temporary mixer check, and the 440 Hz sound was heard again.

## Not yet established

- The HOST LED remained red even while Mac playback was audible.
- Input/capture, long-duration reliability, reconnect/reboot recovery, all 28 channels, and non-48-kHz operation are unverified.
- A stereo test during a temporary mixer fader change was silent. The mixer must not be treated as hardware-validated; no further mixer changes are part of this checkpoint.
- The ad-hoc driver has not been tested with SIP enabled and is not expected to pass normal DriverKit signature/entitlement validation.

## Next release gate

The owner intends to re-enable SIP and pursue an Apple-authorized, signed DriverKit build before resuming full application and mixer work. A direct Developer ID release does not require App Store review, but it still requires the restricted DriverKit entitlements, provisioning, signing, and notarization. Keep this checkpoint and the archived build until a signed replacement is independently verified with SIP enabled.
