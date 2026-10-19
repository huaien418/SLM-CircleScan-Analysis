# Stage 3 V2 workflow guide

This guide describes how the published functions connect. For an immediately runnable example, use the [synthetic demonstration](../../examples/README.md). It is distinct from the real-image workflow below.

## Paths

From the repository root:

```matlab
repositoryRoot = pwd;
sharedRoot = fullfile(repositoryRoot, 'Matlab_Code');
v2CodeFolder = fullfile(sharedRoot, 'STAGE3_V2');
addpath(sharedRoot, v2CodeFolder);
```

Retain this directory structure. `+stage3v2` is a required MATLAB package. The configuration field called `LegacyCodeRoot` points to the parent `Matlab_Code` folder containing the shared real detector; it does not mean the frozen legacy scripts are required. Those scripts are not included.

Do not recursively add the whole repository to the path: the test double has the same function name as the real detector. For production use, `which detect_circle_scan_interval -all` should select the file directly under `Matlab_Code`, not `tests/fake_detector`.

## Real-data preparation

Use a separate experiment directory containing real image folders with this layout:

```text
experiment-root/
  R01/40um_T01, 40um_T02, 40um_T03, 80um_T01, 80um_T02, 80um_T03
  R02/...
  ...
```

Default configuration uses R01–R05 and T01–T03, but parameters must match the actual study. The names alone do not establish independent preparations.

The following is a template for your own data; it cannot run until those folders and matched references exist:

```matlab
experimentRoot = fullfile('data', 'my-study');
overrides = struct;
overrides.DarkFolderBeginning = fullfile('data', 'my-study-dark-beginning');
overrides.DarkFolderEnd = '';
overrides.NakedBeginningFolder = '';
overrides.NakedEndFolder = '';
% Set CameraHz, ExposureUs, RadiusMm, VelocityMmS and other study conditions.
config = create_stage3_config_v2(experimentRoot, overrides);
```

The configuration creates an analysis/config folder in your supplied experiment root. It does not rewrite this source code. Beginning dark frames are required for brightness correction. End-dark and naked-bed references are optional by default and reported separately.

## Pipeline and ROI approval

```matlab
outputs = run_stage3_v2_pipeline(config, [], false);
```

The first call detects image activity and intentionally stops after creating a Global ROI candidate. Inspect it before approval:

```matlab
candidateFile = fullfile(config.AnalysisRoot, 'roi', ...
    'stage3_v2_global_roi_candidate.mat');
approve_global_roi_v2(candidateFile);
outputs = run_stage3_v2_pipeline(config, [], false);
```

The next call uses the approved ROI for image QC, brightness features and statistics. A completed brightness run with missing required motion/QC evidence is reported as `PIPELINE_COMPLETED_FORMAL_QC_INCOMPLETE`, not silently treated as a complete validation.

## Explicit log mapping

Supply a CSV with `DatasetID,LogFile` and a real log path per mapped capture through `overrides.LogMapFile`. Logs are not paired with images by guessing filenames. Missing mapping yields `LOG_NOT_MAPPED`; motion evidence is required by default for the configured formal-output audit.

## Selected rows and outputs

```matlab
manifest = build_stage3_manifest_v2(config);
run_stage3_interval_batch_v2(config, manifest, [1 4 7], false);
```

A scalar `5` means manifest row 5 only. Output folders below `config.AnalysisRoot` include config, interval, roi, qc, features, statistics, figures, audit and batch_status. Do not point a demonstration at your original experiment output directory unless you intend to analyze that data.

See [method](../../docs/METHOD.md), [validation](../../docs/VALIDATION.md) and [limitations](../../docs/LIMITATIONS.md) for definitions and the scope of the executed synthetic test.
