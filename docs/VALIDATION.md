# Public-copy validation — 2026-10-19

Environment: Windows, MATLAB 25.2.0.2998904 (R2025b). All execution used the standalone publication copy. The original research directory was not used as an analysis target.

## Code and dependencies

- Code Analyzer inspected all 30 `.m` files: 27 production files, two existing test files and one new demo wrapper.
- Analyzer findings: 39 `MSNU` notices for stale Code Analyzer suppression comments. No other message IDs were reported. Notices were retained rather than changing unrelated production code.
- `matlab.codetools.requiredFilesAndProducts` examined the 27 production files and reported MATLAB 25.2 as the only required MathWorks product in this installation. No dependency pointed into the original desktop research project. Minimum-version and cross-platform support are not established by this result.
- All 27 original production files are byte-identical to their local sources. Among the 29 selected existing `.m` files, 28 are unchanged and only the smoke test received path-restoration handling. The additional demo wrapper is new.

## Observed synthetic results

| Check | Observed result |
| --- | --- |
| Synthetic manifest datasets | 30 |
| Capture-feature rows | 240 |
| Generated plots | 5 |
| Expected-direction agreement in constructed data | 5/5 |
| Synthetic endpoint separation S | 17.888544 |
| Intentional per-item detector failure isolation | Passed |
| Synthetic command geometry | Passed |
| Preflight SNR calculation contract | Passed |
| Constructed formal-output audit | Passed |
| Optional naked-reference handling | Passed |
| Smoke-test caller path restored | Passed |
| Demo caller path restored | Passed |
| Real detector selected after the smoke test | Passed |

The final execution marker was `PUBLIC_COPY_VERIFICATION_PASSED`. The intentional fake-detector failure warning is expected, not a failed overall test.

## Coverage boundary

The test mocks interval detection and injects cycle windows, synthetic ROI approval and some QC/status tables. Its constructed audit records are software fixtures. It does not execute the real activity detector, interactive approval, full real-image pipeline, camera synchronization or physical machine validation. Other functions receive static checks but are not all runtime-covered. All figure values are synthetic.

Machine-readable [results](validation/runtime-result.json), [dependency report](validation/dependencies.json), [Code Analyzer output](validation/code-analyzer.json), [redacted execution log](validation/runtime-log.txt) and [source hashes](validation/source-provenance.json) are included. The [historical report](validation-history/2026-10-13.md) remains separate from this publication run.
