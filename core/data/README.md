# WDTT whitelist seed

`wdtt-whitelist.txt` is the initial offline copy of
https://github.com/hxehex/russia-mobile-internet-whitelist/blob/main/whitelist.txt,
retrieved on 2026-11-19. The source license is in `wdtt-whitelist.LICENSE`.

The app downloads the current list every 24 hours while the Core runs, using
the active routing scheme. A valid cache takes priority over this seed. Empty,
oversized or malformed responses keep the previous copy. Entries match exact
domains; the app does not expand them to all subdomains, Russian domains or IPs.

This community list covers different operators and regions; an entry does not
guarantee that the user's operator currently permits the destination.
