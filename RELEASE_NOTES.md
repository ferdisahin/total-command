# Total Command 0.2.4 — preview

- File splitting and combining with CRC32 verification; locked tabs.
- Two-way directory synchronization with optional SHA-256 content comparison.
- MD5, SHA-1, SHA-256, SHA-512 and CRC32/SFV checksum tools.
- Updated Total Commander-style in-window menus, action toolbar, command prompt and quick folder/history dropdown.
- Background folder-size calculation and expanded panel status information.
- FTPS now validates server certificates and uses explicit TLS on its default port 21.

Includes the existing FTP/FTPS/SFTP client, content diff, advanced multi-rename, quick search/filter, copy/move queue and English/Turkish interface. Remote connections remain preview functionality; live-server coverage is incomplete. Saved remote-site passwords currently use application preferences instead of Keychain.

Validation: the local test suite and arm64/x86_64 universal build passed on 2026-10-20. Live remote-server integration was not tested. Public artifacts require a new Developer ID signature and Apple notarization; the older root-level 0.2.3 ZIP is not this release.
