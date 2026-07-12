# slow-project

A tiny data pipeline. `slow.sh` computes a checksum aggregate over 100 items.

- Run it: `bash slow.sh`
- Correct output: a single line `checksum-total: <number>` (the number must not change — it is the correctness contract)
- Known problem: it is slow; we want the wall-clock runtime down.
