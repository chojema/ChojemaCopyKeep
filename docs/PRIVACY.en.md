# Privacy and Local Storage

[한국어](PRIVACY.ko.md) / [Home](../README.en.md)

Developer: Park Chulwoo

## Collection and Retention

While running, the app stores supported text or images locally when the clipboard changes. It does not record source app names, window titles, or every key you type. It does not automatically import clipboard content that existed before launch.

History and settings are stored in `%LOCALAPPDATA%\ChojemaCopyKeep\history.db`, or the separate folder selected for development. The app does not encrypt its database. Manage access through your device account and folder permissions.

## Transmission

The app has no clipboard upload feature, account service, cloud synchronization, telemetry, or automatic updates. GitHub is used for source and distribution files, not actual clipboard history.

## Controls

Pause collection from the notification area menu. Delete individual items or confirm Clear all to remove stored history. Clear all does not erase the current system clipboard or content already pasted into another app. It does not guarantee forensic erasure of storage media.

The app skips content marked for exclusion by supported source apps. It cannot identify every password or personal detail automatically. Pause collection before copying sensitive content.

## Development and Publication

Exclude stored content, personal settings, credentials, logs, internal work records, private email addresses, and personal paths from the repository and distributed files. Use synthetic examples in public issues and screenshots.
