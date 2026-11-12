# PartySync Flutter starter

This is the first UI prototype for the PartySync Android/iOS concept.

## Run on a computer
1. Install Flutter SDK and Android Studio (for Android) or Xcode (for iOS).
2. Create a Flutter project or place these files in a Flutter project.
3. Run `flutter pub get`.
4. Run `flutter run`.

## Current status
This starter includes the home screen, create/join demo flow, room screen, member count placeholder,
host/guest UI, playback controls UI, and local volume slider.

It does NOT yet implement real hotspot management, device discovery, file transfer, audio playback,
multi-device clock synchronization, or drift correction. Those require native platform integration
and real-device testing. Android apps cannot silently enable another phone's hotspot, and iOS has
additional local-network and hotspot restrictions.

## Recommended next engineering milestones
1. Android local-network transport and room discovery (Wi-Fi Direct / local Wi-Fi approach).
2. Host-to-guest audio file transfer and local caching.
3. Audio engine with scheduled playback and device clock-offset measurement.
4. Drift correction and real-device latency tests.
5. iOS transport and permission implementation.
