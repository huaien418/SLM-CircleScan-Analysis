function result = test_stage3_v2_smoke()
%TEST_STAGE3_V2_SMOKE Runtime smoke test using a synthetic 30-dataset study.
%
% This test writes only to a unique temporary folder. It does not read or
% modify the user's experiment images or any legacy Stage 3 result.

% Keep the test double isolated even when an assertion throws an error.
originalPath = path;
pathCleanup = onCleanup(@() path(originalPath)); %#ok<NASGU>
codeRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(codeRoot);

testRoot = string(tempname);
mkdir(testRoot);
darkBeginning = fullfile(testRoot, 'dark_beginning');
darkEnd = fullfile(testRoot, 'dark_end');
nakedBeginning = fullfile(testRoot, 'naked_beginning');
nakedEnd = fullfile(testRoot, 'naked_end');
mkdir(darkBeginning); mkdir(darkEnd);
mkdir(nakedBeginning); mkdir(nakedEnd);

for frameIndex = 1:3
    imwrite(uint8((3 + frameIndex) * ones(16, 16)), ...
        fullfile(darkBeginning, sprintf('dark_%03d.png', frameIndex)));
    imwrite(uint8(6 * ones(16, 16)), ...
        fullfile(darkEnd, sprintf('dark_%03d.png', frameIndex)));
    nakedA = uint8(20 * ones(16, 16));
    nakedB = uint8(20 * ones(16, 16));
    nakedA(6:10, 6:10) = uint8(145 + frameIndex);
    nakedB(6:10, 6:10) = uint8(141 + frameIndex);
    imwrite(nakedA, fullfile(nakedBeginning, sprintf('naked_%03d.png', frameIndex)));
    imwrite(nakedB, fullfile(nakedEnd, sprintf('naked_%03d.png', frameIndex)));
end

repeatIDs = ["R01" "R02" "R03" "R04" "R05"];
technicalIDs = ["T01" "T02" "T03"];
thicknesses = [40 80];
for repeatIndex = 1:numel(repeatIDs)
    for thicknessIndex = 1:numel(thicknesses)
        thickness = thicknesses(thicknessIndex);
        for technicalIndex = 1:numel(technicalIDs)
            folder = fullfile(testRoot, repeatIDs(repeatIndex), ...
                sprintf('%dum_%s', thickness, technicalIDs(technicalIndex)));
            mkdir(folder);
            repeatOffset = repeatIndex - 3;
            technicalOffset = technicalIndex - 2;
            if thickness == 40
                signal = 125 + repeatOffset + 0.3 * technicalOffset;
            else
                signal = 85 + repeatOffset + 0.3 * technicalOffset;
            end
            for frameIndex = 1:10
                image = uint8(12 * ones(16, 16));
                cycleOffset = 0.2 * (ceil(frameIndex / 2) - 3);
                image(6:10, 6:10) = uint8(round(signal + cycleOffset));
                imwrite(image, fullfile(folder, sprintf('frame_%04d.png', frameIndex)));
            end
        end
    end
end

overrides = struct;
overrides.DarkFolderBeginning = string(darkBeginning);
overrides.DarkFolderEnd = string(darkEnd);
overrides.NakedBeginningFolder = string(nakedBeginning);
overrides.NakedEndFolder = string(nakedEnd);
overrides.MakeFigures = true;
overrides.RerunExisting = true;
config = create_stage3_config_v2(testRoot, overrides);
manifest = build_stage3_manifest_v2(config);
assert(height(manifest) == 30, 'Manifest should contain 30 datasets.');
assert(all(manifest.ImageCount == 10), 'Every synthetic dataset should contain 10 images.');
assert(numel(unique(manifest.DatasetID)) == 30, 'DatasetID must be unique.');

% Verify that a detector failure in one selected dataset does not stop the
% remaining batch contract or erase the successful row.
fakeDetectorRoot = fullfile(codeRoot, 'tests', 'fake_detector');
intervalTestConfig = config;
intervalTestConfig.LegacyCodeRoot = string(fakeDetectorRoot);
intervalTestConfig.AnalysisRoot = string(fullfile(testRoot, ...
    '00_INTERVAL_ISOLATION_TEST'));
intervalTestConfig.ConfirmAutoRoi = false;
intervalTestConfig.MakeFigures = false;
intervalTestStatus = run_stage3_interval_batch_v2( ...
    intervalTestConfig, manifest, [1 2], true);
assert(intervalTestStatus.BatchStatus(1) == "COMPLETED", ...
    'First synthetic detector row should complete.');
assert(intervalTestStatus.BatchStatus(2) == "FAILED", ...
    'Second synthetic detector row should fail without aborting the batch.');
[preflightSummary, ~] = check_stage3_acquisition_preflight( ...
    manifest.ImageFolder(1), intervalTestConfig, []);
expectedSnr = preflightSummary.MeanTop1MeanDN / ...
    preflightSummary.DarkTemporalNoiseSdDN;
assert(abs(preflightSummary.Top1Snr - expectedSnr) < 1e-10, ...
    'Preflight Top1 SNR must not subtract the dark mean twice.');
assert(preflightSummary.DarkFrameCount == 3, ...
    'Preflight must report the temporal dark-frame count.');

roiFolder = fullfile(config.AnalysisRoot, 'roi');
mkdir(roiFolder);
roiDefinition = struct;
roiDefinition.roiRect = [5 5 6 6];
roiDefinition.approvalStatus = "APPROVED_BY_USER_VISUAL_REVIEW";
roiDefinition.approvedAt = string(datetime('now'));
roiDefinition.sourceCandidateFile = "SYNTHETIC_SMOKE_TEST";
roiDefinition.actualPixelCount = 49;
roiDefinition.version = "STAGE3_V2_SMOKE_TEST";
roiFile = fullfile(roiFolder, 'stage3_v2_global_roi_approved.mat');
save(roiFile, 'roiDefinition');

intervalRoot = fullfile(config.AnalysisRoot, 'interval');
mkdir(intervalRoot);
intervalK = (1:height(manifest)).';
outputFolders = strings(height(manifest), 1);
for k = intervalK.'
    outputFolder = fullfile(intervalRoot, char(manifest.DatasetID(k)));
    mkdir(outputFolder);
    outputFolders(k) = string(outputFolder);
    cycleWindows = table((1:5).', (1:2:9).', (2:2:10).', ...
        'VariableNames', {'CycleIndex','StartFrame','EndFrame'});
    writetable(cycleWindows, fullfile(outputFolder, 'detected_cycle_windows.csv'));
end
intervalStatus = table(intervalK, outputFolders, ...
    'VariableNames', {'K','OutputFolder'});
imageQc = table(intervalK, true(height(manifest), 1), ...
    ones(height(manifest), 1), 10 * ones(height(manifest), 1), ...
    'VariableNames', {'K','BrightnessAnalysisEligible', ...
    'EffectiveStartFrame','EffectiveEndFrame'});

features = extract_stage3_brightness_features_v2(config, manifest, ...
    intervalStatus, imageQc, roiFile, 1:height(manifest), true);
assert(all(features.BatchStatus.BatchStatus == "COMPLETED"), ...
    'Every feature extraction must complete.');
assert(height(features.RunFeatures) == 30 * 8, ...
    'Expected 8 run-level features for each of 30 datasets.');
primaryRows = features.RunFeatures.FeatureID == config.PrimaryFeature;
assert(sum(primaryRows) == 30, 'Expected one primary-feature row per dataset.');

statistics = analyze_stage3_repeatability_v2(config, features.RunFeatures);
primarySeparation = statistics.SeparationSummary( ...
    statistics.SeparationSummary.FeatureID == config.PrimaryFeature, :);
assert(height(primarySeparation) == 1, 'Primary separation row is missing.');
assert(primarySeparation.DirectionAgreementCount == 5, ...
    'All five independent preparations should have the expected direction.');
assert(primarySeparation.CompletePairCount == 5, ...
    'All five independent preparation pairs should be complete.');
assert(primarySeparation.EndpointValidationPassed, ...
    'Synthetic primary endpoint should pass all configured gates.');

referenceQc = analyze_reference_drift_v2(config, roiFile);
assert(all(referenceQc.ReferenceQcStatus ~= "FAILED"), ...
    'Reference drift analysis must complete.');
nakedRow = referenceQc(referenceQc.ReferenceType == "NAKED", :);
assert(nakedRow.CorrectionMode == "PAIRED_DARK_CORRECTED", ...
    'Naked references must use their matching beginning/end dark frames.');
assert(nakedRow.BeginningTop1MeanDN < 147 && nakedRow.EndTop1MeanDN < 143, ...
    'Naked-reference features should be dark corrected.');
plotFiles = plot_stage3_results_v2(config, statistics, referenceQc);
assert(height(plotFiles) >= 4 && all(isfile(plotFiles.PlotFile)), ...
    'Expected Stage 3 V2 figures were not written.');

% Verify command geometry and keep response evidence explicitly separate.
sampleCountPerCycle = 20;
expectedPeriodMs = 1000 * 2 * pi * config.RadiusMm / config.VelocityMmS;
state = repmat("CIRCLE_SCAN", 5 * sampleCountPerCycle, 1);
circleIndex = repelem((1:5).', sampleCountPerCycle);
cmdX = nan(size(circleIndex)); cmdY = cmdX; elapsedMs = cmdX;
for circleNumber = 1:5
    rows = (circleNumber-1) * sampleCountPerCycle + (1:sampleCountPerCycle);
    theta = linspace(0, 2*pi, sampleCountPerCycle).';
    cmdX(rows) = config.CenterXmm + config.RadiusMm * cos(theta);
    cmdY(rows) = config.CenterYmm + config.RadiusMm * sin(theta);
    elapsedMs(rows) = (circleNumber-1) * expectedPeriodMs + ...
        linspace(0, expectedPeriodMs, sampleCountPerCycle).';
end
actX = cmdX; actY = cmdY;
motionLog = table(state, circleIndex, elapsedMs, cmdX, cmdY, actX, actY, ...
    'VariableNames', {'state','circle_index','elapsed_ms', ...
    'cmd_x_mm','cmd_y_mm','act_x_mm','act_y_mm'});
motionLogFile = fullfile(testRoot, 'synthetic_motion_log.csv');
writetable(motionLog, motionLogFile);
motionManifest = manifest(1, :);
motionManifest.LogFile = string(motionLogFile);
motionQc = validate_circlescan_motion_log_v2(config, motionManifest, 1);
assert(motionQc.CommandPathValid, 'Synthetic command circle should be valid.');
assert(motionQc.ResponsePathEvidence == "TIME_SERIES_AVAILABLE", ...
    'Synthetic response time-series evidence should be available.');

% Build the minimum full-study status files needed by the formal audit.
batchRoot = fullfile(config.AnalysisRoot, 'batch_status');
if ~isfolder(batchRoot), mkdir(batchRoot); end
auditInterval = table(manifest.K, ...
    config.RequestedCycleCount * ones(height(manifest), 1), ...
    'VariableNames', {'K','CompleteCycleCount'});
writetable(auditInterval, fullfile(batchRoot, 'stage3_v2_interval_status.csv'));
auditImageQc = table(manifest.K, 5 * ones(height(manifest), 1), ...
    5 * ones(height(manifest), 1), 6 * ones(height(manifest), 1), ...
    6 * ones(height(manifest), 1), ...
    'VariableNames', {'K','RoiX','RoiY','RoiWidth','RoiHeight'});
writetable(auditImageQc, fullfile(batchRoot, 'stage3_v2_image_qc_status.csv'));
motionQcFull = repmat(motionQc, height(manifest), 1);
motionQcFull.K = manifest.K;
motionQcFull.DatasetID = manifest.DatasetID;
motionQcFull.RepeatID = manifest.RepeatID;
motionQcFull.ThicknessUm = manifest.ThicknessUm;
motionQcFull.TechnicalID = manifest.TechnicalID;
writetable(motionQcFull, fullfile(config.AnalysisRoot, 'qc', ...
    'stage3_v2_motion_qc.csv'));
audit = audit_stage3_outputs_v2(config);
assert(~any(audit.Required & audit.Status ~= "PASS"), ...
    'All required synthetic formal-QC checks should pass.');
optionalNaked = audit.CheckID == "NAKED_REFERENCE_AVAILABLE";
assert(any(optionalNaked) && ~audit.Required(optionalNaked), ...
    'Naked reference must remain optional by default.');
configNoNaked = config;
configNoNaked.NakedBeginningFolder = "";
configNoNaked.NakedEndFolder = "";
referenceWithoutNaked = analyze_reference_drift_v2(configNoNaked, roiFile);
nakedWithoutInput = referenceWithoutNaked.ReferenceType == "NAKED";
assert(referenceWithoutNaked.ReferenceQcStatus(nakedWithoutInput) == ...
    "NOT_AVAILABLE", 'Missing naked references should be reported, not failed.');
auditWithoutNaked = audit_stage3_outputs_v2(configNoNaked);
assert(~any(auditWithoutNaked.Required & ...
    auditWithoutNaked.Status ~= "PASS"), ...
    'Missing optional naked references must not fail formal QC.');

result = struct;
result.TestRoot = testRoot;
result.ManifestRows = height(manifest);
result.RunFeatureRows = height(features.RunFeatures);
result.PrimaryDirectionAgreement = primarySeparation.DirectionAgreementCount;
result.PrimarySeparationS = primarySeparation.SeparationS;
result.PrimaryPassed = primarySeparation.EndpointValidationPassed;
result.PlotCount = height(plotFiles);
result.IntervalIsolationPassed = ...
    intervalTestStatus.BatchStatus(1) == "COMPLETED" && ...
    intervalTestStatus.BatchStatus(2) == "FAILED";
result.MotionCommandPassed = motionQc.CommandPathValid;
result.PreflightSnrPassed = preflightSummary.SignalQcPassed;
result.FormalAuditPassed = ~any(audit.Required & audit.Status ~= "PASS");
result.NakedOptionalPassed = ~any(auditWithoutNaked.Required & ...
    auditWithoutNaked.Status ~= "PASS");

fprintf('\n=== STAGE3 V2 SMOKE TEST PASSED ===\n');
fprintf('Temporary root: %s\n', testRoot);
fprintf('Manifest rows: %d\n', result.ManifestRows);
fprintf('Run feature rows: %d\n', result.RunFeatureRows);
fprintf('Primary direction agreement: %d/5\n', result.PrimaryDirectionAgreement);
fprintf('Primary separation S: %.4f\n', result.PrimarySeparationS);
fprintf('Figures written: %d\n', result.PlotCount);
end
