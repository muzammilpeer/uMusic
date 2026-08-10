# uMusic 2.0 Beta 1 Release Notes

uMusic 2.0 is a ground-up, local-first Apple client for a private uMusic server. Start Listening builds a queue immediately and improves locally from listening behavior and user-enabled context. It supports offline-first playback, resumable queues, manual and automatically growing playlists, privacy controls, research exports, themes, adaptive iPad/macOS navigation, and the share-extension import handoff.

This beta adds a frozen schema/API release manifest, optional aggregate-only diagnostics, verified backup/restore tooling, and the copy-first v1 migration package adapter.

Migration is not exposed as a finished user workflow: the adapter validates a package but does not yet commit it into live stores. See Known Limitations before installing. Back up existing data and do not replace a production v1 installation with this beta.
