# Fireface Studio: permanent macOS installation

The product is a separate macOS app with an embedded DriverKit extension.
It must remain launchable with SIP enabled after reboot. The existing
`/Applications/ASFW.app` and its `net.asfw.driver` extension are left installed
until this bundle has passed a live replacement test.

The owner wants to try TestFlight for Mac after local hardware validation.
That route needs App Store Connect and matching App Store distribution profiles.
A direct Developer ID release is a separate route and requires notarization.
Neither route replaces a signed development build tested on the physical
Fireface 800 with SIP enabled.

## Identifiers and permissions

- Apple Developer team currently selected for this fork: `4GX52GBB7Z`.
- App bundle: `com.marsproo.firefacestudio`.
- Driver bundle: `com.marsproo.firefacestudio.driver`.
- App: System Extension install and DriverKit user-client access to its driver.
- Driver: DriverKit, PCIDriverKit transport for the Agere/LSI OHCI controller
  (`pci11c1,5901`), and AudioDriverKit. This device branch does not publish
  the inherited SCSI controller personality or request its entitlement.
- A matching DriverKit provisioning profile must cover the restricted
  entitlements for the app and driver. Both components must use the same team.
- Direct distribution additionally needs a Developer ID certificate and
  notarization. App Store review is not part of this route.

Apple's 2026-10-10 approval email lists DriverKit PCI (PrimaryMatch), DriverKit
UserClient Access, DriverKit, and DriverKit Family Audio. As of this date, the
local profiles for this team still contain no DriverKit rights; matching app
and driver profiles must be created or downloaded. A prior signed probe requesting only
`com.apple.developer.driverkit.userclient-access` was killed by AMFI with
`No matching profile found`. An otherwise identical signed probe launched but
`IOServiceOpen` returned `0xE00002E2` against the installed ASFireWire driver.

References:

- https://developer.apple.com/documentation/DriverKit/requesting-entitlements-for-driverkit-development
- https://developer.apple.com/system-extensions/
- https://developer.apple.com/documentation/systemextensions

## Required acceptance before replacing the installed driver

1. Compile and run protocol and app tests.
2. Sign both app and driver with matching approved development profiles.
3. Verify the app opens with SIP enabled and the extension activates.
4. Verify the Fireface 800 is detected, starts duplex audio, and survives a
   reboot and reconnect.
5. Verify all mixer channels and supported sample-rate changes against the
   physical card, including readback and recovery from FireWire bus reset.
6. Prepare the chosen distribution signing and review path only after those
   hardware checks pass.
