function batchStatus = run_stage3_interval_batch_v2(config, manifest, selectedK, rerunExisting)
%RUN_STAGE3_INTERVAL_BATCH_V2 Detect activity and five complete cycles.
%
% selectedK is always a manifest row index:
%   run_stage3_interval_batch_v2(config, manifest, 1:height(manifest))
%   run_stage3_interval_batch_v2(config, manifest, [1 4 7])
%   run_stage3_interval_batch_v2(config, manifest, 5)
%
% When automatic ROI selection is enabled, MATLAB pauses for each selected
% dataset so the proposed detector ROI can be reviewed.

if nargin < 3 || isempty(selectedK)
    selectedK = 1:height(manifest);
end
if nargin < 4 || isempty(rerunExisting)
    rerunExisting = logical(config.RerunExisting);
end
selectedK = stage3v2.validateSelection(selectedK, height(manifest));
preflightLocal(config, manifest, selectedK);

addpath(char(config.LegacyCodeRoot));
if exist('detect_circle_scan_interval', 'file') ~= 2
    error('detect_circle_scan_interval.m is not available on the MATLAB path.');
end

intervalRoot = fullfile(config.AnalysisRoot, 'interval');
perRunRoot = fullfile(intervalRoot, 'per_run');
statusFolder = fullfile(config.AnalysisRoot, 'batch_status');
if ~isfolder(perRunRoot), mkdir(perRunRoot); end
if ~isfolder(statusFolder), mkdir(statusFolder); end
statusFile = fullfile(statusFolder, 'stage3_v2_interval_status.csv');

fprintf('\n=== Stage 3 V2 interval batch ===\n');
displayTable = manifest(selectedK, {'DatasetID','RepeatID','ThicknessUm', ...
    'TechnicalID','ImageCount','RadiusMm','VelocityMmS'});
displayTable.K = selectedK(:);
displayTable = movevars(displayTable, 'K', 'Before', 1);
disp(displayTable);

rows = cell(numel(selectedK), 1);
for position = 1:numel(selectedK)
    k = selectedK(position);
    run = manifest(k, :);
    outputFolder = fullfile(perRunRoot, char(run.DatasetID));
    summaryFile = fullfile(outputFolder, 'detection_summary.csv');
    cycleFile = fullfile(outputFolder, 'detected_cycle_windows.csv');
    fprintf('\n[%d/%d] K=%d %s\n', position, numel(selectedK), ...
        k, run.DatasetID);

    if isfile(summaryFile) && isfile(cycleFile) && ~rerunExisting
        summary = readtable(summaryFile, 'TextType', 'string');
        rows{position} = statusFromSummaryLocal(k, run, ...
            "SKIPPED_EXISTING", "Existing V2 interval result preserved.", ...
            outputFolder, summary);
        fprintf('Skipped existing result.\n');
        writePartialLocal(rows, position, statusFile);
        continue;
    end

    try
        opts = struct;
        opts.WriteOutputs = true;
        opts.ConfirmAutoRoi = logical(config.ConfirmAutoRoi);
        opts.OutputFolder = outputFolder;
        opts.MakeDiagnosticPlot = logical(config.MakeFigures);
        roiSource = config.IntervalRoiSource;
        [summary, cyclesLegacy, ~] = detect_circle_scan_interval( ...
            char(run.ImageFolder), roiSource, char(run.DarkFolder), ...
            double(run.CameraHz), double(run.RadiusMm), ...
            double(run.VelocityMmS), double(run.RequestedCycleCount), opts);

        cycles = cyclesLegacy;
        if ismember('CircleIndex', cycles.Properties.VariableNames)
            cycles = renamevars(cycles, 'CircleIndex', 'CycleIndex');
        end
        writetable(cycles, cycleFile);

        summary = addV2SummaryFieldsLocal(summary, run, config);
        writetable(summary, summaryFile);
        rows{position} = statusFromSummaryLocal(k, run, "COMPLETED", ...
            string(summary.Reason(1)), outputFolder, summary);
        fprintf('Cycles=%g, effective range=[%g %g], period error=%.3f%%\n', ...
            summary.CompleteCycleCount(1), summary.RecommendedStartFrame(1), ...
            summary.RecommendedEndFrame(1), ...
            summary.ImagePeriodConsistencyErrorPercent(1));
    catch ME
        rows{position} = statusRowLocal(k, run, "FAILED", "", NaN, ...
            NaN, NaN, NaN, string(ME.message), outputFolder);
        warning('Stage3V2:IntervalFailed', 'K=%d %s failed: %s', ...
            k, run.DatasetID, ME.message);
    end
    writePartialLocal(rows, position, statusFile);
end

batchStatus = vertcat(rows{:});
writetable(batchStatus, statusFile);
fprintf('\n=== Stage 3 V2 interval batch finished ===\n');
fprintf('COMPLETED: %d\n', sum(batchStatus.BatchStatus == "COMPLETED"));
fprintf('SKIPPED_EXISTING: %d\n', ...
    sum(batchStatus.BatchStatus == "SKIPPED_EXISTING"));
fprintf('FAILED: %d\n', sum(batchStatus.BatchStatus == "FAILED"));
fprintf('Status CSV: %s\n', statusFile);
end

function summary = addV2SummaryFieldsLocal(summary, run, config)
if ismember('CompleteCircleCount', summary.Properties.VariableNames)
    summary = renamevars(summary, 'CompleteCircleCount', 'CompleteCycleCount');
end
estimated = double(summary.EstimatedPeriodFrames(1));
expected = double(summary.ExpectedPeriodFrames(1));
if isfinite(estimated) && isfinite(expected) && expected > 0
    periodError = 100 * abs(estimated - expected) / expected;
else
    periodError = NaN;
end
summary.DatasetID = string(run.DatasetID);
summary.ImagePeriodConsistencyErrorPercent = periodError;
summary.ImagePeriodQcPassed = isfinite(periodError) && ...
    periodError <= double(config.MaximumImagePeriodErrorPercent);
summary.InterpretationBoundary = ...
    "Image activity/period evidence only; geometric XY circle path is not proven.";
end

function row = statusFromSummaryLocal(k, run, batchState, message, outputFolder, summary)
required = ["Status" "CompleteCycleCount" "RecommendedStartFrame" ...
    "RecommendedEndFrame" "ImagePeriodConsistencyErrorPercent"];
stage3v2.requireVariables(summary, required, 'V2 interval summary');
row = statusRowLocal(k, run, batchState, string(summary.Status(1)), ...
    double(summary.CompleteCycleCount(1)), ...
    double(summary.RecommendedStartFrame(1)), ...
    double(summary.RecommendedEndFrame(1)), ...
    double(summary.ImagePeriodConsistencyErrorPercent(1)), ...
    message, outputFolder);
end

function row = statusRowLocal(k, run, batchState, detectorState, cycleCount, ...
        startFrame, endFrame, periodError, message, outputFolder)
row = table(k, string(run.DatasetID), string(run.RepeatID), ...
    double(run.ThicknessUm), string(run.TechnicalID), ...
    string(batchState), string(detectorState), cycleCount, startFrame, ...
    endFrame, periodError, string(message), string(outputFolder), ...
    'VariableNames', {'K','DatasetID','RepeatID','ThicknessUm', ...
    'TechnicalID','BatchStatus','DetectorStatus','CompleteCycleCount', ...
    'RecommendedStartFrame','RecommendedEndFrame', ...
    'ImagePeriodConsistencyErrorPercent','Message','OutputFolder'});
end

function writePartialLocal(rows, position, statusFile)
available = rows(1:position);
available = available(~cellfun(@isempty, available));
if ~isempty(available)
    writetable(vertcat(available{:}), statusFile);
end
end

function preflightLocal(config, manifest, selectedK)
required = ["DatasetID" "ImageFolder" "DarkFolder" "CameraHz" ...
    "RadiusMm" "VelocityMmS" "RequestedCycleCount"];
stage3v2.requireVariables(manifest, required, 'Stage 3 V2 manifest');
problems = strings(0, 1);
for k = selectedK
    if ~isfolder(manifest.ImageFolder(k))
        problems(end+1) = sprintf('K=%d image folder missing', k); %#ok<AGROW>
    end
    if ~isfolder(manifest.DarkFolder(k))
        problems(end+1) = sprintf('K=%d dark folder missing', k); %#ok<AGROW>
    end
end
if strlength(string(config.AnalysisRoot)) == 0
    problems(end+1) = "config.AnalysisRoot is empty"; %#ok<AGROW>
end
if ~isempty(problems)
    error('Interval preflight failed:\n - %s', strjoin(problems, '\n - '));
end
end

