# Privacy and Local Storage

[한국어](PRIVACY.ko.md) | [README](../README.en.md)

## Collection and Retention

The app stores text and images copied while it is running in a local database. Source app names, window titles, and keystrokes are not logged. Clipboard content from before launch is not imported automatically.

History and settings are stored in `%LOCALAPPDATA%\ChojemaCopyKeep\history.db`, or the separate folder selected for development. The app does not encrypt its database. Access to stored files is managed through Windows accounts and folder permissions.

## Transmission

The app has no clipboard upload feature, account login, cloud synchronization, usage collection, or automatic updates. The GitHub repository and releases contain source and distribution files only.

## Pausing Collection and Deleting History

Collection can be paused from the notification area menu. Individual items can be deleted, and clearing all history requires confirmation. Clearing history removes the app's stored records; the current system clipboard and content pasted into other apps remain unchanged. Secure erasure of storage media is not guaranteed.

The app skips items marked for exclusion by their source apps. It does not automatically classify passwords or personal information by content. Collection can be paused before copying sensitive content.

## Development and Publication

Exclude stored content, personal settings, credentials, logs, internal work records, private email addresses, and personal paths from the repository and distributed files. Use synthetic examples in public issues and screenshots.
