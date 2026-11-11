# ZIFburn 0.1

Native macOS front-end for minipro, with a searchable chip database, hex buffer,
checksums, socket placement diagrams and per-chip programming options.

- Read, write, verify, blank-check and erase supported devices through minipro.
- Burn ROM sets, duplicate chips and write batches with insertion prompts.
- Inspect stability reads and compare, trim or pad image buffers.
- Work through bank-switched 27C160/322/400/800 adapter jobs.
- Choose from 13 appearance themes.
- Confirm Burn operations and destructive retries before programming.
- Validate Intel HEX imports and report when verification is disabled.

Requires macOS 14 or later and a separately installed minipro. The universal
application includes Apple silicon and Intel executables. S-record files use
the direct Write File / Verify Against File workflows.
