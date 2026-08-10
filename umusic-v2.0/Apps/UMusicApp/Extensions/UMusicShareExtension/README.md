# uMusic Share Extension Target

Sprint 15 implements this boundary. The extension links `UMusicImportClient` only and
must not link `UMusicCore`, playback, location, motion, HealthKit, Core Data, telemetry,
or ML modules.

Host and extension targets require the App Group
`group.uk.muzammilpeer.umusic.v2` and shared Keychain group
`$(AppIdentifierPrefix)uk.muzammilpeer.umusic.v2.shared`. The containing target must
publish the resolved full Keychain group in its Info property
`UMusicSharedKeychainAccessGroup`. Never place the team prefix, token, or server
credentials in source.

The UI shows one normalized supported URL, authorization/provider availability copy,
and one **Send to Server** action. It queues an idempotent request in the App Group;
the signed-in containing app copies the current access token to the shared Keychain,
submits pending work on foreground activation, and leaves offline failures queued for
retry. Neither the App Group payload nor logs contain the access token or user context.
