# Publication changes

The public copy was assembled outside the original research folder.

1. Copy the 27 selected production `.m` files without changing any bytes; retain the required sibling detector and `+stage3v2` package layout.
2. Retain the fake detector unchanged in its isolated test folder.
3. Add `onCleanup` path restoration to `test_stage3_v2_smoke.m`, so its fake detector does not leak into a caller's later work, including assertion-failure exits.
4. Add `examples/run_synthetic_demo.m` to make the synthetic test easy to run and assert successful-path restoration and real-detector selection afterward.
5. Replace the workflow README with repository-relative paths and add method, limitations, provenance and validation documents. The old report remains clearly labeled as historical.
6. Include one unmodified plot generated during the new synthetic run. Redact the temporary folder prefix from the execution log; do not modify numerical results.

No real experiment inputs, numerical research summaries, approval MAT files, machine logs, frozen legacy scripts, CODESYS projects or private research documents were included. No physical experiment was performed for this release. Original-source hashes are rechecked before publication and stored in the preparation audit; public provenance uses neutral repository paths.
