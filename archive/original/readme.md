# Silent Runner script (legacy headless)

This README describes the legacy May 2, 2025 release of the Silent Runner script. It fixes an issue where headless runners failed to play video and therefore did not appear in silent tests.

Key change: the script stops using an unsupported browser-hiding method and instead launches Chromium with the `--headless` argument.
