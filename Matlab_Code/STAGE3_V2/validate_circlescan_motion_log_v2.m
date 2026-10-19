function motionQc = validate_circlescan_motion_log_v2(config, manifest, selectedK)
%VALIDATE_CIRCLESCAN_MOTION_LOG_V2 Validate command geometry from CSV logs.
%
% Command validity and response evidence are reported separately. Response
% time-series availability is not automatically interpreted as a proven
% one-command-to-one-response mapping.

if nargin < 3 || isempty(selectedK)
    selectedK = 1:height(manifest);
end
selectedK = stage3v2.validateSelection(selectedK, height(manifest));
stage3v2.requireVariables(manifest, ...
    ["K" "DatasetID" "LogFile" "RadiusMm" "VelocityMmS"], 'manifest');

qcRoot = fullfile(config.AnalysisRoot, 'qc');
plotRoot = fullfile(qcRoot, 'motion_plots');
if ~isfolder(plotRoot), mkdir(plotRoot); end
rows = repmat(emptyMotionRowLocal(), 0, 1);

fprintf('\n=== Stage 3 V2 motion-log validation ===\n');
for position = 1:numel(selectedK)
    k = selectedK(position);
    run = manifest(k, :);
    row = baseMotionRowLocal(k, run);
    if strlength(string(run.LogFile)) == 0 || ~isfile(run.LogFile)
        row.MotionLogAvailable = false;
        row.CommandPathValid = false;
        row.ResponsePathEvidence = "NOT_AVAILABLE";
        row.MotionQcStatus = "LOG_NOT_MAPPED";
        row.Message = "No verified DatasetID-to-LogFile mapping was supplied.";
        rows(end+1, 1) = row; %#ok<AGROW>
        continue;
    end

    try
        logTable = readtable(run.LogFile, 'TextType', 'string', ...
            'VariableNamingRule', 'preserve');
        scan = selectScanRowsLocal(logTable);
        [cmdX, nameCmdX] = numericColumnLocal(scan, ...
            ["cmd_x_mm" "dataTarPosX" "tarPosX" "cmdX"]);
        [cmdY, nameCmdY] = numericColumnLocal(scan, ...
            ["cmd_y_mm" "dataTarPosY" "tarPosY" "cmdY"]);
        [centerX, ~] = optionalNumericColumnLocal(scan, ...
            ["center_x_mm" "centerX"], double(config.CenterXmm));
        [centerY, ~] = optionalNumericColumnLocal(scan, ...
            ["center_y_mm" "centerY"], double(config.CenterYmm));
        commandRadius = hypot(cmdX - centerX, cmdY - centerY);
        expectedRadius = double(run.RadiusMm);
        row.MotionLogAvailable = true;
        row.CommandSampleCount = numel(commandRadius);
        row.CommandRadiusMeanMm = mean(commandRadius, 'omitnan');
        row.CommandRadiusStandardDeviationMm = std(commandRadius, 0, 'omitnan');
        row.CommandRadiusCvPercent = stage3v2.cvPercent(commandRadius);
        row.CommandRadiusErrorPercent = 100 * ...
            abs(row.CommandRadiusMeanMm - expectedRadius) / expectedRadius;
        row.CycleCountFromLog = cycleCountLocal(scan);
        row.MotionPeriodErrorPercent = periodErrorLocal(scan, run);
        row.CommandPathValid = row.CommandRadiusErrorPercent <= ...
            config.MaximumCommandRadiusErrorPercent && ...
            row.CommandRadiusCvPercent <= config.MaximumCommandRadiusCvPercent && ...
            row.CycleCountFromLog >= config.RequestedCycleCount;

        [actX, actXName, hasActX] = optionalNumericColumnLocal(scan, ...
            ["act_x_mm" "dataActPosX" "actPosX"], NaN);
        [actY, actYName, hasActY] = optionalNumericColumnLocal(scan, ...
            ["act_y_mm" "dataActPosY" "actPosY"], NaN);
        if hasActX && hasActY && any(isfinite(actX)) && any(isfinite(actY))
            [lagSamples, alignedRmsUm] = alignResponseLocal(cmdX, cmdY, actX, actY);
            row.ResponsePathEvidence = "TIME_SERIES_AVAILABLE";
            row.ResponseBestLagSamples = lagSamples;
            row.AlignedCommandResponseRmsUm = alignedRmsUm;
        else
            row.ResponsePathEvidence = "NOT_AVAILABLE";
            actX = nan(size(cmdX)); actY = nan(size(cmdY));
            actXName = ""; actYName = "";
        end

        if row.CommandPathValid && row.ResponsePathEvidence == "TIME_SERIES_AVAILABLE"
            row.MotionQcStatus = "COMMAND_VALID_RESPONSE_TIME_SERIES_AVAILABLE";
        elseif row.CommandPathValid
            row.MotionQcStatus = "COMMAND_VALID_RESPONSE_NOT_AVAILABLE";
        else
            row.MotionQcStatus = "COMMAND_REVIEW_REQUIRED";
        end
        row.Message = sprintf('Command columns: %s/%s; response columns: %s/%s.', ...
            nameCmdX, nameCmdY, actXName, actYName);
        writeMotionPlotLocal(plotRoot, run.DatasetID, cmdX, cmdY, actX, actY, row);
    catch ME
        row.MotionQcStatus = "FAILED";
        row.Message = string(ME.message);
        warning('Stage3V2:MotionLogFailed', 'K=%d %s failed: %s', ...
            k, run.DatasetID, ME.message);
    end
    rows(end+1, 1) = row; %#ok<AGROW>
    fprintf('[%d/%d] %s: %s\n', position, numel(selectedK), ...
        run.DatasetID, row.MotionQcStatus);
end

motionQc = struct2table(rows);
outputFile = fullfile(qcRoot, 'stage3_v2_motion_qc.csv');
writetable(motionQc, outputFile);
fprintf('Motion QC: %s\n', outputFile);
end

function scan = selectScanRowsLocal(logTable)
names = string(logTable.Properties.VariableNames);
stateIndex = find(strcmpi(names, 'state'), 1);
if isempty(stateIndex)
    scan = logTable;
else
    state = string(logTable.(logTable.Properties.VariableNames{stateIndex}));
    mask = strcmpi(state, 'CIRCLE_SCAN');
    if ~any(mask)
        error('Log contains no CIRCLE_SCAN rows.');
    end
    scan = logTable(mask, :);
end
end

function [values, matchedName] = numericColumnLocal(tableValue, aliases)
[values, matchedName, found] = optionalNumericColumnLocal(tableValue, aliases, NaN);
if ~found
    error('Required log column missing. Tried: %s', strjoin(aliases, ', '));
end
end

function [values, matchedName, found] = optionalNumericColumnLocal(tableValue, aliases, defaultValue)
names = string(tableValue.Properties.VariableNames);
matchedName = ""; found = false;
for aliasIndex = 1:numel(aliases)
    match = find(strcmpi(names, aliases(aliasIndex)), 1);
    if ~isempty(match)
        matchedName = names(match);
        raw = tableValue.(tableValue.Properties.VariableNames{match});
        if isnumeric(raw)
            values = double(raw);
        else
            values = str2double(string(raw));
        end
        found = true;
        return;
    end
end
if isscalar(defaultValue)
    values = repmat(double(defaultValue), height(tableValue), 1);
else
    values = double(defaultValue);
end
end

function count = cycleCountLocal(scan)
names = string(scan.Properties.VariableNames);
match = find(strcmpi(names, 'circle_index'), 1);
if ~isempty(match)
    values = double(scan.(scan.Properties.VariableNames{match}));
    values = values(isfinite(values));
    count = numel(unique(values));
    return;
end
match = find(strcmpi(names, 'circle_completed'), 1);
if ~isempty(match)
    values = double(scan.(scan.Properties.VariableNames{match}));
    count = max(values, [], 'omitnan');
else
    count = NaN;
end
end

function errorPercent = periodErrorLocal(scan, run)
names = string(scan.Properties.VariableNames);
matchTime = find(strcmpi(names, 'elapsed_ms'), 1);
matchCircle = find(strcmpi(names, 'circle_index'), 1);
if isempty(matchTime) || isempty(matchCircle)
    errorPercent = NaN;
    return;
end
timeMs = double(scan.(scan.Properties.VariableNames{matchTime}));
circleIndex = double(scan.(scan.Properties.VariableNames{matchCircle}));
cycleLabels = unique(circleIndex(isfinite(circleIndex)), 'stable');
periods = nan(numel(cycleLabels), 1);
for circleNumber = 1:numel(cycleLabels)
    values = timeMs(circleIndex == cycleLabels(circleNumber));
    if numel(values) >= 2
        periods(circleNumber) = (max(values) - min(values)) / 1000;
    end
end
measured = mean(periods, 'omitnan');
expected = 2 * pi * double(run.RadiusMm) / double(run.VelocityMmS);
if isfinite(measured) && expected > 0
    errorPercent = 100 * abs(measured - expected) / expected;
else
    errorPercent = NaN;
end
end

function [bestLag, rmsUm] = alignResponseLocal(cmdX, cmdY, actX, actY)
n = min([numel(cmdX), numel(cmdY), numel(actX), numel(actY)]);
cmdX = cmdX(1:n); cmdY = cmdY(1:n); actX = actX(1:n); actY = actY(1:n);
maximumLag = min(500, floor(n / 10));
errors = inf(maximumLag + 1, 1);
for lag = 0:maximumLag
    if lag == 0
        commandIndices = 1:n; responseIndices = 1:n;
    else
        commandIndices = 1:(n-lag); responseIndices = (1+lag):n;
    end
    dx = actX(responseIndices) - cmdX(commandIndices);
    dy = actY(responseIndices) - cmdY(commandIndices);
    valid = isfinite(dx) & isfinite(dy);
    if nnz(valid) >= 10
        errors(lag+1) = sqrt(mean(dx(valid).^2 + dy(valid).^2));
    end
end
[minimumError, index] = min(errors);
bestLag = index - 1;
rmsUm = 1000 * minimumError;
end

function writeMotionPlotLocal(folder, datasetID, cmdX, cmdY, actX, actY, row)
fig = figure('Visible', 'off', 'Color', 'white', 'Position', [100 100 850 650]);
plot(cmdX, cmdY, '-', 'Color', [0 0.4470 0.7410], ...
    'LineWidth', 1.8, 'DisplayName', 'Command'); hold on;
if any(isfinite(actX)) && any(isfinite(actY))
    plot(actX, actY, '-', 'Color', [0.8500 0.3250 0.0980], ...
        'LineWidth', 1.0, 'DisplayName', 'Response time series');
end
axis equal; grid on; xlabel('X (mm)'); ylabel('Y (mm)');
legend('Location', 'best');
title({char(datasetID), char(row.MotionQcStatus), ...
    'Response time series is not assumed one-to-one without lag alignment'}, ...
    'Interpreter', 'none');
exportgraphics(fig, fullfile(folder, char(datasetID + "_motion_log.png")), ...
    'Resolution', 180);
close(fig);
end

function row = baseMotionRowLocal(k, run)
row = emptyMotionRowLocal();
row.K = k; row.DatasetID = string(run.DatasetID);
row.RepeatID = string(run.RepeatID); row.ThicknessUm = double(run.ThicknessUm);
row.TechnicalID = string(run.TechnicalID); row.LogFile = string(run.LogFile);
end

function row = emptyMotionRowLocal()
row = struct('K', NaN, 'DatasetID', "", 'RepeatID', "", ...
    'ThicknessUm', NaN, 'TechnicalID', "", 'LogFile', "", ...
    'MotionLogAvailable', false, 'CommandSampleCount', NaN, ...
    'CommandRadiusMeanMm', NaN, 'CommandRadiusStandardDeviationMm', NaN, ...
    'CommandRadiusCvPercent', NaN, 'CommandRadiusErrorPercent', NaN, ...
    'CycleCountFromLog', NaN, 'MotionPeriodErrorPercent', NaN, ...
    'CommandPathValid', false, 'ResponsePathEvidence', "", ...
    'ResponseBestLagSamples', NaN, 'AlignedCommandResponseRmsUm', NaN, ...
    'MotionQcStatus', "", 'Message', "");
end
