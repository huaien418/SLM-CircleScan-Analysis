function outputs = extract_stage3_brightness_features_v2(config, manifest, ...
        intervalStatus, imageQc, roiFile, selectedK, rerunExisting)
%EXTRACT_STAGE3_BRIGHTNESS_FEATURES_V2 Extract corrected bright-tail metrics.
%
% Top1MeanDN is the predeclared primary feature. The run value is the
% equally weighted mean of the five cycle means, not a pooled-frame mean.

if nargin < 5 || strlength(string(roiFile)) == 0
    roiFile = fullfile(config.AnalysisRoot, 'roi', ...
        'stage3_v2_global_roi_approved.mat');
end
if nargin < 6 || isempty(selectedK)
    selectedK = 1:height(manifest);
end
if nargin < 7 || isempty(rerunExisting)
    rerunExisting = logical(config.RerunExisting);
end
selectedK = stage3v2.validateSelection(selectedK, height(manifest));
roi = stage3v2.loadApprovedRoi(roiFile);
stage3v2.requireVariables(imageQc, ...
    ["K" "BrightnessAnalysisEligible" "EffectiveStartFrame" ...
    "EffectiveEndFrame"], 'imageQc');
stage3v2.requireVariables(intervalStatus, ["K" "OutputFolder"], 'intervalStatus');

features = ["RoiMeanDN" "P90DN" "P95DN" "P99DN" ...
    "Top10MeanDN" "Top5MeanDN" "Top1MeanDN" "MaximumDN"];
featuresRoot = fullfile(config.AnalysisRoot, 'features');
perRunRoot = fullfile(featuresRoot, 'per_run');
statusFolder = fullfile(config.AnalysisRoot, 'batch_status');
if ~isfolder(perRunRoot), mkdir(perRunRoot); end
if ~isfolder(statusFolder), mkdir(statusFolder); end
batchFile = fullfile(statusFolder, 'stage3_v2_feature_batch_status.csv');

fprintf('\n=== Stage 3 V2 brightness feature extraction ===\n');
displayTable = manifest(selectedK, {'DatasetID','RepeatID','ThicknessUm', ...
    'TechnicalID'});
displayTable.K = selectedK(:);
displayTable = movevars(displayTable, 'K', 'Before', 1);
disp(displayTable);

statusRows = cell(numel(selectedK), 1);
for position = 1:numel(selectedK)
    k = selectedK(position);
    run = manifest(k, :);
    qc = imageQc(imageQc.K == k, :);
    interval = intervalStatus(intervalStatus.K == k, :);
    runFolder = fullfile(perRunRoot, char(run.DatasetID));
    frameFile = fullfile(runFolder, 'frame_features.csv');
    cycleFile = fullfile(runFolder, 'cycle_features.csv');
    runFile = fullfile(runFolder, 'run_features.csv');
    fprintf('\n[%d/%d] K=%d %s\n', position, numel(selectedK), k, run.DatasetID);

    expectedFiles = [string(frameFile) string(cycleFile) string(runFile)];
    if all(isfile(expectedFiles)) && ~rerunExisting
        statusRows{position} = statusRowLocal(k, run, ...
            "SKIPPED_EXISTING", "Existing V2 feature files preserved.", runFolder);
        writePartialLocal(statusRows, position, batchFile);
        continue;
    end

    try
        if height(qc) ~= 1 || ~logical(qc.BrightnessAnalysisEligible(1))
            error('Dataset is not eligible according to image QC.');
        end
        if height(interval) ~= 1
            error('Exactly one interval row is required.');
        end
        cycleWindowFile = fullfile(char(interval.OutputFolder(1)), ...
            'detected_cycle_windows.csv');
        if ~isfile(cycleWindowFile)
            error('Cycle window file not found: %s', cycleWindowFile);
        end
        cycleWindows = readtable(cycleWindowFile, 'TextType', 'string');
        stage3v2.requireVariables(cycleWindows, ...
            ["CycleIndex" "StartFrame" "EndFrame"], 'cycle windows');
        if height(cycleWindows) ~= config.RequestedCycleCount
            error('Expected %d cycle windows; found %d.', ...
                config.RequestedCycleCount, height(cycleWindows));
        end
        if ~isfolder(runFolder), mkdir(runFolder); end
        [frameTable, cycleTable, runTable] = analyzeRunLocal(run, qc, ...
            cycleWindows, roi.roiRect, features);
        writetable(frameTable, frameFile);
        writetable(cycleTable, cycleFile);
        writetable(runTable, runFile);
        statusRows{position} = statusRowLocal(k, run, "COMPLETED", ...
            sprintf('%d frames, %d cycles, %d features.', ...
            height(frameTable), height(cycleWindows), numel(features)), runFolder);
    catch ME
        statusRows{position} = statusRowLocal(k, run, "FAILED", ...
            string(ME.message), runFolder);
        warning('Stage3V2:FeatureFailed', 'K=%d %s failed: %s', ...
            k, run.DatasetID, ME.message);
    end
    writePartialLocal(statusRows, position, batchFile);
end

batchStatus = vertcat(statusRows{:});
writetable(batchStatus, batchFile);
[frameFeatures, cycleFeatures, runFeatures] = ...
    collectOutputsLocal(manifest, perRunRoot, selectedK);
frameOutput = fullfile(featuresRoot, 'stage3_v2_frame_features.csv');
cycleOutput = fullfile(featuresRoot, 'stage3_v2_cycle_features.csv');
runOutput = fullfile(featuresRoot, 'stage3_v2_run_features.csv');
writetable(frameFeatures, frameOutput);
writetable(cycleFeatures, cycleOutput);
writetable(runFeatures, runOutput);

outputs = struct('BatchStatus', batchStatus, 'FrameFeatures', frameFeatures, ...
    'CycleFeatures', cycleFeatures, 'RunFeatures', runFeatures, ...
    'FrameFile', string(frameOutput), 'CycleFile', string(cycleOutput), ...
    'RunFile', string(runOutput));

fprintf('\n=== Stage 3 V2 feature extraction finished ===\n');
fprintf('COMPLETED/SKIPPED: %d / %d\n', ...
    sum(batchStatus.BatchStatus ~= "FAILED"), height(batchStatus));
fprintf('Primary feature: %s\n', config.PrimaryFeature);
fprintf('Run features: %s\n', runOutput);
end

function [frameTable, cycleTable, runTable] = analyzeRunLocal( ...
        run, qc, cycles, roiRect, featureNames)
files = stage3v2.listImages(run.ImageFolder);
startFrame = round(double(qc.EffectiveStartFrame(1)));
endFrame = round(double(qc.EffectiveEndFrame(1)));
[firstImage, maxDigital] = stage3v2.readGray( ...
    fullfile(run.ImageFolder, files(startFrame).name));
darkImage = stage3v2.loadDarkImage(run.DarkFolder, size(firstImage));
darkRoi = stage3v2.cropRoi(darkImage, roiRect);
frameIndices = (startFrame:endFrame).';
frameCount = numel(frameIndices);
imageName = strings(frameCount, 1);
cycleIndex = nan(frameCount, 1);
rawP99 = nan(frameCount, 1);
saturationPercent = nan(frameCount, 1);
featureData = nan(frameCount, numel(featureNames));
satThreshold = 0.98 * maxDigital;

for cyclePosition = 1:height(cycles)
    inCycle = frameIndices >= double(cycles.StartFrame(cyclePosition)) & ...
        frameIndices <= double(cycles.EndFrame(cyclePosition));
    if any(isfinite(cycleIndex(inCycle)))
        error('Cycle windows overlap.');
    end
    cycleIndex(inCycle) = double(cycles.CycleIndex(cyclePosition));
end
if any(~isfinite(cycleIndex))
    error('At least one effective frame is not assigned to a cycle.');
end

top1PixelCount = NaN;
for position = 1:frameCount
    absoluteIndex = frameIndices(position);
    [image, currentMax] = stage3v2.readGray( ...
        fullfile(run.ImageFolder, files(absoluteIndex).name));
    maxDigital = max(maxDigital, currentMax);
    rawRoi = stage3v2.cropRoi(image, roiRect);
    corrected = max(rawRoi - darkRoi, 0);
    values = double(corrected(:));
    rawValues = double(rawRoi(:));
    sortedValues = sort(values, 'descend');
    [top10, ~] = stage3v2.topFractionMean(sortedValues, 0.10);
    [top5, ~] = stage3v2.topFractionMean(sortedValues, 0.05);
    [top1, top1PixelCount] = stage3v2.topFractionMean(sortedValues, 0.01);
    featureData(position, :) = [mean(values, 'omitnan'), ...
        stage3v2.percentile(values, 90), ...
        stage3v2.percentile(values, 95), ...
        stage3v2.percentile(values, 99), top10, top5, top1, ...
        max(values, [], 'omitnan')];
    imageName(position) = string(files(absoluteIndex).name);
    rawP99(position) = stage3v2.percentile(rawValues, 99);
    saturationPercent(position) = 100 * mean(rawValues >= satThreshold);
end

frameTable = table(repmat(double(run.K), frameCount, 1), ...
    repmat(string(run.DatasetID), frameCount, 1), frameIndices, imageName, ...
    cycleIndex, rawP99, saturationPercent, ...
    'VariableNames', {'K','DatasetID','FrameIndex','ImageName', ...
    'CycleIndex','P99Raw','SaturatedPixelPercent'});
frameTable = [frameTable, array2table(featureData, ...
    'VariableNames', cellstr(featureNames))];

cycleRows = repmat(emptyFeatureRowLocal(), 0, 1);
runRows = repmat(emptyFeatureRowLocal(), 0, 1);
for featurePosition = 1:numel(featureNames)
    featureID = featureNames(featurePosition);
    cycleMeans = nan(height(cycles), 1);
    for cyclePosition = 1:height(cycles)
        inCycle = cycleIndex == double(cycles.CycleIndex(cyclePosition));
        values = featureData(inCycle, featurePosition);
        row = identityRowLocal(run, featureID);
        row.CycleIndex = double(cycles.CycleIndex(cyclePosition));
        row.StartFrame = min(frameIndices(inCycle));
        row.EndFrame = max(frameIndices(inCycle));
        row.FrameCount = sum(inCycle);
        row.MeanDN = mean(values, 'omitnan');
        row.StandardDeviationDN = std(values, 0, 'omitnan');
        row.CvPercent = stage3v2.cvPercent(values);
        row.Top1PixelCount = top1PixelCount;
        cycleRows(end+1, 1) = row; %#ok<AGROW>
        cycleMeans(cyclePosition) = row.MeanDN;
    end
    row = identityRowLocal(run, featureID);
    row.CycleIndex = NaN;
    row.StartFrame = startFrame;
    row.EndFrame = endFrame;
    row.FrameCount = frameCount;
    row.MeanDN = mean(cycleMeans, 'omitnan');
    row.StandardDeviationDN = std(cycleMeans, 0, 'omitnan');
    row.CvPercent = stage3v2.cvPercent(cycleMeans);
    row.Top1PixelCount = top1PixelCount;
    runRows(end+1, 1) = row; %#ok<AGROW>
end
cycleTable = struct2table(cycleRows);
runTable = struct2table(runRows);
runTable.Properties.VariableNames{'MeanDN'} = 'RunMeanOfCycleMeansDN';
runTable.Properties.VariableNames{'StandardDeviationDN'} = 'CycleMeanStandardDeviationDN';
runTable.Properties.VariableNames{'CvPercent'} = 'CycleMeanCvPercent';
end

function row = identityRowLocal(run, featureID)
row = emptyFeatureRowLocal();
row.K = double(run.K);
row.DatasetID = string(run.DatasetID);
row.RepeatID = string(run.RepeatID);
row.ThicknessUm = double(run.ThicknessUm);
row.TechnicalID = string(run.TechnicalID);
row.ParameterID = string(run.ParameterID);
row.FeatureID = string(featureID);
end

function row = emptyFeatureRowLocal()
row = struct('K', NaN, 'DatasetID', "", 'RepeatID', "", ...
    'ThicknessUm', NaN, 'TechnicalID', "", 'ParameterID', "", ...
    'FeatureID', "", 'CycleIndex', NaN, 'StartFrame', NaN, ...
    'EndFrame', NaN, 'FrameCount', NaN, 'MeanDN', NaN, ...
    'StandardDeviationDN', NaN, 'CvPercent', NaN, 'Top1PixelCount', NaN);
end

function [frameFeatures, cycleFeatures, runFeatures] = ...
        collectOutputsLocal(manifest, perRunRoot, selectedK)
frameFeatures = table(); cycleFeatures = table(); runFeatures = table();
for k = selectedK
    runFolder = fullfile(perRunRoot, char(manifest.DatasetID(k)));
    files = [string(fullfile(runFolder, 'frame_features.csv')), ...
        string(fullfile(runFolder, 'cycle_features.csv')), ...
        string(fullfile(runFolder, 'run_features.csv'))];
    if ~all(isfile(files)), continue; end
    frameFeatures = appendTableLocal(frameFeatures, ...
        readtable(files(1), 'TextType', 'string'));
    cycleFeatures = appendTableLocal(cycleFeatures, ...
        readtable(files(2), 'TextType', 'string'));
    runFeatures = appendTableLocal(runFeatures, ...
        readtable(files(3), 'TextType', 'string'));
end
end

function combined = appendTableLocal(combined, addition)
if isempty(combined), combined = addition; else, combined = [combined; addition]; end
end

function row = statusRowLocal(k, run, state, message, outputFolder)
row = table(k, string(run.DatasetID), string(run.RepeatID), ...
    double(run.ThicknessUm), string(run.TechnicalID), string(state), ...
    string(message), string(outputFolder), 'VariableNames', ...
    {'K','DatasetID','RepeatID','ThicknessUm','TechnicalID', ...
    'BatchStatus','Message','OutputFolder'});
end

function writePartialLocal(rows, position, path)
available = rows(1:position);
available = available(~cellfun(@isempty, available));
if ~isempty(available), writetable(vertcat(available{:}), path); end
end
