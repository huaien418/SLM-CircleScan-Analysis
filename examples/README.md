# Synthetic software demonstration

From the repository root in MATLAB:

```matlab
addpath(fullfile(pwd, 'examples'));
result = run_synthetic_demo();
```

The wrapper selects the real shared detector before the test, runs the synthetic smoke test, and verifies that the test restores its caller's path and that the real detector is selected afterward. An `onCleanup` in the smoke test also restores paths if an assertion fails. The wrapper restores its own caller's path on return.

## What is generated

- Thirty synthetic capture folders: five fictional preparation IDs, two nominal endpoint labels and three captures per state.
- Tiny 16x16 PNG sequences, dark images, optional beginning/end reference controls, and a synthetic motion log.
- Frame/cycle/capture features, repeatability tables, plots, and audit/status files in a unique system temporary folder. The demo prints that folder and returns it as `result.TestRoot`.

## What is mocked or supplied

The batch-isolation/preflight portion uses `tests/fake_detector/detect_circle_scan_interval.m`, with one intentional failure. The feature/statistics section supplies five two-frame cycle windows per ten-frame capture, a synthetic fixed ROI and eligibility/status records. The formal audit also receives constructed status tables and a replicated synthetic motion-QC row.

Thus, this is a focused software-contract demonstration. It does not establish real-detector timing, real image QC, interactive ROI approval or full-pipeline behavior. The real detector requires at least 12 images; the test's ten-frame captures are not inputs for that detector.

The expected intentional warning tests whether one failed batch item leaves the other successful item intact. A successful overall run ends with `STAGE3 V2 SMOKE TEST PASSED` and a path-restoration message. It does not change machine scheduling, connect to instruments or operate a laser.

## Temporary output

Generated output is left in the returned temporary folder for inspection. It is not a permanent research dataset and is not written into the source tree. No automatic recursive deletion is performed.
