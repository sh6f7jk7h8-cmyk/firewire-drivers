# Fireface Studio: permanent macOS installation

The product is a separate macOS app with an embedded DriverKit extension.
The app is distributed directly, without App Store Connect. It must remain
launchable with SIP enabled after reboot. The existing `/Applications/ASFW.app`
and its `net.asfw.driver` extension are left installed until this bundle has
passed a live replacement test.

## Identifiers and permissions

- Apple Developer team currently selected for this fork: `4GX52GBB7Z`.
- App bundle: `com.marsproo.firefacestudio`.
- Driver bundle: `com.marsproo.firefacestudio.driver`.
- App: System Extension install and DriverKit user-client access to its driver.
- Driver: DriverKit, PCIDriverKit transport for the Agere/LSI OHCI controller
  (`pci11c1,5901`), AudioDriverKit, and SCSIControllerDriverKit (because this
  inherited ASFireWire driver includes its SCSI bridge).
- A matching DriverKit provisioning profile must cover the restricted
  entitlements for the app and driver. Both components must use the same team.
- Direct distribution additionally needs a Developer ID certificate and
  notarization. App Store review is not part of this route.

Apple requires a DriverKit entitlement request for the team before the
provisioning profiles can be created. At 2026-10-09, the local profiles for
this team contain no DriverKit rights. A signed probe requesting only
`com.apple.developer.driverkit.userclient-access` was killed by AMFI with
`No matching profile found`. An otherwise identical signed probe launched but
`IOServiceOpen` returned `0xE00002E2` against the installed ASFireWire driver.

References:

- https://developer.apple.com/documentation/DriverKit/requesting-entitlements-for-driverkit-development
- https://developer.apple.com/system-extensions/
- https://developer.apple.com/documentation/systemextensions

## Required acceptance before replacing the installed driver

1. Compile and run protocol and app tests.
2. Sign both app and driver with approved profiles; notarize the app.
3. Verify the app opens with SIP enabled and the extension activates.
4. Verify the Fireface 800 is detected, starts duplex audio, and survives a
   reboot and reconnect.
5. Verify all mixer channels and supported sample-rate changes against the
   physical card, including readback and recovery from FireWire bus reset.
