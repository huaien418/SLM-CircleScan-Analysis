function qcTable = validate_effective_cycle_qc_v2(config, manifest, ...
        intervalStatus, roiFile, selectedK, rerunExisting)
%VALIDATE_EFFECTIVE_CYCLE_QC_V2 Validate exposure, ROI and effective cycles.

if nargin < 4 || strlength(string(roiFile)) == 0
    roiFile = fullfile(config.AnalysisRoot, 'roi', ...
        'stage3_v2_global_roi_approved.mat');
end
if nargin < 5 || isempty(selectedK)
    selectedK = 1:height(manifest);
end
if nargin < 6 || isempty(rerunExisting)
    rerunExisting = logical(config.RerunExisting);
end
selectedK = stage3v2.validateSelection(selectedK, height(manifest));
roi = stage3v2.loadApprovedRoi(roiFile);
stage3v2.requireVariables(intervalStatus, ...
    ["K" "BatchStatus" "DetectorStatus" "CompleteCycleCount" ...
    "RecommendedStartFrame" "RecommendedEndFrame" ...
    "ImagePeriodConsistencyErrorPercent" "OutputFolder"], 'intervalStatus');

qcRoot = fullfile(config.AnalysisRoot, 'qc');
perRunRoot = fullfile(qcRoot, 'per_run');
statusFolder = fullfile(config.AnalysisRoot, 'batch_status');
if ~isfolder(perRunRoot), mkdir(perRunRoot); end
if ~isfolder(statusFolder), mkdir(statusFolder); end
statusFile = fullfile(statusFolder, 'stage3_v2_image_qc_status.csv');

fprintf('\n=== Stage 3 V2 effective-cycle image QC ===\n');
displayTable = manifest(selectedK, {'DatasetID','RepeatID','ThicknessUm', ...
    'TechnicalID','ImageCount'});
displayTable.K = selectedK(:);
displayTable = movevars(displayTable, 'K', 'Before', 1);
disp(displayTable);

rows = cell(numel(selectedK), 1);
for position = 1:numel(selectedK)
    k = selectedK(position);
    run = manifest(k, :);
    interval = intervalStatus(intervalStatus.K == k, :);
    outputFolder = fullfile(perRunRoot, char(run.DatasetID));
    resultMat = fullfile(outputFolder, 'effective_cycle_qc.mat');
    frameFile = fullfile(outputFolder, 'effective_frame_qc.csv');
    fprintf('\n[%d/%d] K=%d %s\n', position, numel(selectedK), ...
        k, run.DatasetID);

    if isfile(resultMat) && isfile(frameFile) && ~rerunExisting
        saved = load(resultMat, 'qcRow');
        row = saved.qcRow;
        row.BatchStatus = "SKIPPED_EXISTING";
        row.Message = "Existing V2 image QC preserved.";
        rows{position} = struct2table(row, 'AsArray', true);
        writePartialLocal(rows, position, statusFile);
        continue;
    end

    try
        if height(interval) ~= 1 || interval.BatchStatus == "FAILED"
            error('A completed interval result is required.');
        end
        if ~isfolder(outputFolder), mkdir(outputFolder); end
        [frameTable, meanCorrectedImage, temporalStdImage, maxDigital] = ...
            analyzeRunLocal(run, interval, roi.roiRect, config);
        qcRow = summarizeLocal(k, run, interval, frameTable, ...
            meanCorrectedImage, temporalStdImage, maxDigital, ...
            roi.roiRect, config, outputFolder);
        save(resultMat, 'qcRow', 'meanCorrectedImage', ...
            'temporalStdImage', 'maxDigital');
        writetable(frameTable, frameFile);
        writeRunPreviewLocal(outputFolder, meanCorrectedImage, ...
            temporalStdImage, roi.roiRect, qcRow);
        rows{position} = struct2table(qcRow, 'AsArray', true);
        fprintf('Image QC: %s | saturation %.5f%% | frames %d\n', ...
            qcRow.ImageQcStatus, qcRow.MaximumSaturatedPixelPercent, ...
            qcRow.EffectiveFrameCount);
    catch ME
        qcRow = baseRowLocal(k, run, roi.roiRect, outputFolder);
        qcRow.BatchStatus = "FAILED";
        qcRow.ImageQcStatus = "FAILED";
        qcRow.Message = string(ME.message);
        rows{position} = struct2table(qcRow, 'AsArray', true);
        warning('Stage3V2:ImageQcFailed', 'K=%d %s failed: %s', ...
            k, run.DatasetID, ME.message);
    end
    writePartialLocal(rows, position, statusFile);
end

qcTable = vertcat(rows{:});
writetable(qcTable, statusFile);
writeCombinedPreviewLocal(qcTable, perRunRoot, qcRoot, roi.roiRect);
fprintf('\n=== Stage 3 V2 image QC finished ===\n');
fprintf('ELIGIBLE: %d / %d\n', sum(qcTable.BrightnessAnalysisEligible), ...
    height(qcTable));
fprintf('FAILED: %d\n', sum(qcTable.BatchStatus == "FAILED"));
fprintf('Status CSV: %s\n', statusFile);
end

function [frameTable, meanImage, stdImage, maxDigital] = ...
        analyzeRunLocal(run, interval, roiRect, config)
files = stage3v2.listImages(run.ImageFolder);
startFrame = round(double(interval.RecommendedStartFrame(1)));
endFrame = round(double(interval.RecommendedEndFrame(1)));
if startFrame < 1 || endFrame > numel(files) || endFrame < startFrame
    error('Recommended interval is outside the image sequence.');
end
[firstImage, maxDigital] = stage3v2.readGray( ...
    fullfile(run.ImageFolder, files(startFrame).name));
darkImage = stage3v2.loadDarkImage(run.DarkFolder, size(firstImage));
stage3v2.cropRoi(firstImage, roiRect); % boundary check

frameCount = endFrame - startFrame + 1;
frameIndex = (startFrame:endFrame).';
imageName = strings(frameCount, 1);
rawP99 = nan(frameCount, 1);
saturatedPixelCount = nan(frameCount, 1);
saturatedPixelPercent = nan(frameCount, 1);
meanDarkCorrectedRoi = nan(frameCount, 1);
meanImage = zeros(size(firstImage));
m2Image = zeros(size(firstImage));
satThreshold = double(config.SaturationFractionOfDigitalMax) * maxDigital;

for position = 1:frameCount
    absoluteIndex = frameIndex(position);
    [image, currentMax] = stage3v2.readGray( ...
        fullfile(run.ImageFolder, files(absoluteIndex).name));
    if ~isequal(size(image), size(firstImage))
        error('Image dimensions changed within the dataset.');
    end
    maxDigital = max(maxDigital, currentMax);
    rawRoi = stage3v2.cropRoi(image, roiRect);
    corrected = max(image - darkImage, 0);
    correctedRoi = stage3v2.cropRoi(corrected, roiRect);
    rawValues = rawRoi(:);
    imageName(position) = string(files(absoluteIndex).name);
    rawP99(position) = stage3v2.percentile(rawValues, 99);
    saturatedPixelCount(position) = sum(rawValues >= satThreshold);
    saturatedPixelPercent(position) = ...
        100 * saturatedPixelCount(position) / numel(rawValues);
    meanDarkCorrectedRoi(position) = mean(correctedRoi(:), 'omitnan');
    delta = corrected - meanImage;
    meanImage = meanImage + delta / position;
    m2Image = m2Image + delta .* (corrected - meanImage);
end
if frameCount > 1
    stdImage = sqrt(m2Image / (frameCount - 1));
else
    stdImage = zeros(size(meanImage));
end
frameTable = table(frameIndex, imageName, rawP99, saturatedPixelCount, ...
    saturatedPixelPercent, meanDarkCorrectedRoi, ...
    'VariableNames', {'FrameIndex','ImageName','P99Raw', ...
    'SaturatedPixelCount','SaturatedPixelPercent','MeanDarkCorrectedRoi'});
end

function row = summarizeLocal(k, run, interval, frameTable, meanImage, ...
        stdImage, maxDigital, roiRect, config, outputFolder)
row = baseRowLocal(k, run, roiRect, outputFolder);
row.BatchStatus = "COMPLETED";
row.EffectiveStartFrame = min(frameTable.FrameIndex);
row.EffectiveEndFrame = max(frameTable.FrameIndex);
row.EffectiveFrameCount = height(frameTable);
row.ExpectedTotalCycleFrames = double(run.ExpectedTotalCycleFrames);
row.FrameCountErrorPercent = 100 * abs(row.EffectiveFrameCount - ...
    row.ExpectedTotalCycleFrames) / row.ExpectedTotalCycleFrames;
row.CompleteCycleCount = double(interval.CompleteCycleCount(1));
row.ImagePeriodConsistencyErrorPercent = ...
    double(interval.ImagePeriodConsistencyErrorPercent(1));
row.MaximumSaturatedPixelPercent = ...
    max(frameTable.SaturatedPixelPercent, [], 'omitnan');
row.MaximumSaturatedPixelCount = ...
    max(frameTable.SaturatedPixelCount, [], 'omitnan');
row.FramesAtOrAboveWarning = sum(frameTable.SaturatedPixelPercent >= ...
    double(config.MaximumSaturationPercent));
row.MaxRawP99 = max(frameTable.P99Raw, [], 'omitnan');
row.MeanDarkCorrectedRoiIntensity = ...
    mean(frameTable.MeanDarkCorrectedRoi, 'omitnan');
row.FrameMeanTemporalCvPercent = ...
    stage3v2.cvPercent(frameTable.MeanDarkCorrectedRoi);
row.SignificantActivityOutsideRoiPixels = ...
    activityOutsideRoiLocal(stdImage, roiRect);
row.FileIntegrityPassed = all(isfinite(frameTable.P99Raw)) && ...
    all(isfinite(meanImage(:))) && maxDigital > 0;
row.ExposureQcPassed = row.FramesAtOrAboveWarning == 0;
row.IntervalQcPassed = row.CompleteCycleCount >= ...
    double(config.MinimumCompleteCycleCount) && ...
    row.ImagePeriodConsistencyErrorPercent <= ...
    double(config.MaximumImagePeriodErrorPercent);
row.RoiQcPassed = row.SignificantActivityOutsideRoiPixels == 0;
row.ImageQcPassed = row.FileIntegrityPassed && row.ExposureQcPassed && ...
    row.IntervalQcPassed && row.RoiQcPassed;
row.BrightnessAnalysisEligible = row.ImageQcPassed;
if row.ImageQcPassed
    row.ImageQcStatus = "PASS";
    row.Message = "Exposure, interval and Global ROI checks passed.";
else
    failed = strings(0, 1);
    if ~row.FileIntegrityPassed, failed(end+1) = "FILE"; end %#ok<AGROW>
    if ~row.ExposureQcPassed, failed(end+1) = "EXPOSURE"; end %#ok<AGROW>
    if ~row.IntervalQcPassed, failed(end+1) = "INTERVAL"; end %#ok<AGROW>
    if ~row.RoiQcPassed, failed(end+1) = "ROI"; end %#ok<AGROW>
    row.ImageQcStatus = "REVIEW_" + strjoin(failed, "_");
    row.Message = "One or more image QC gates require review.";
end
end

function count = activityOutsideRoiLocal(map, rect)
values = double(map(isfinite(map)));
location = median(values);
scale = 1.4826 * median(abs(values - location));
threshold = max(location + 6 * max(scale, eps), ...
    stage3v2.percentile(values, 99.5));
mask = map >= threshold;
roiMask = false(size(map));
x1 = rect(1); y1 = rect(2);
x2 = x1 + rect(3); y2 = y1 + rect(4);
roiMask(y1:y2, x1:x2) = true;
count = nnz(mask & ~roiMask);
end

function writeRunPreviewLocal(folder, meanImage, stdImage, roiRect, row)
fig = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [100 100 1050 480]);
layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact');
ax = nexttile(layout); imagesc(ax, meanImage); axis(ax, 'image');
colormap(ax, 'turbo'); hold(ax, 'on');
rectangle(ax, 'Position', roiRect, 'EdgeColor', 'r', 'LineWidth', 2);
title(ax, 'Dark-corrected effective-cycle mean', 'Color', 'black');
ax = nexttile(layout); imagesc(ax, stdImage); axis(ax, 'image');
colormap(ax, 'turbo'); hold(ax, 'on');
rectangle(ax, 'Position', roiRect, 'EdgeColor', 'r', 'LineWidth', 2);
title(ax, 'Temporal standard deviation (diagnostic)', 'Color', 'black');
title(layout, sprintf('%s | %s', row.DatasetID, row.ImageQcStatus), ...
    'Interpreter', 'none', 'Color', 'black');
exportgraphics(fig, fullfile(folder, 'effective_cycle_qc_preview.png'), ...
    'Resolution', 180);
close(fig);
end

function writeCombinedPreviewLocal(qcTable, perRunRoot, qcRoot, roiRect)
valid = qcTable.BatchStatus ~= "FAILED";
rows = qcTable(valid, :);
if isempty(rows), return; end
columnCount = min(5, height(rows));
rowCount = ceil(height(rows) / columnCount);
fig = figure('Visible', 'off', 'Color', 'white', ...
    'Position', [30 30 330*columnCount 300*rowCount]);
layout = tiledlayout(fig, rowCount, columnCount, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
for index = 1:height(rows)
    data = load(fullfile(perRunRoot, char(rows.DatasetID(index)), ...
        'effective_cycle_qc.mat'), 'meanCorrectedImage');
    ax = nexttile(layout); imagesc(ax, data.meanCorrectedImage);
    axis(ax, 'image'); colormap(ax, 'turbo'); hold(ax, 'on');
    rectangle(ax, 'Position', roiRect, 'EdgeColor', 'r', 'LineWidth', 1.5);
    title(ax, rows.DatasetID(index), 'Interpreter', 'none', 'Color', 'black');
end
title(layout, sprintf('Stage 3 V2 effective-cycle means | Global ROI [%d %d %d %d]', ...
    roiRect), 'Color', 'black', 'FontWeight', 'bold');
exportgraphics(fig, fullfile(qcRoot, ...
    'stage3_v2_effective_cycle_mean_images.png'), 'Resolution', 180);
close(fig);
end

function row = baseRowLocal(k, run, roiRect, outputFolder)
row = struct('K', k, 'DatasetID', string(run.DatasetID), ...
    'RepeatID', string(run.RepeatID), 'ThicknessUm', double(run.ThicknessUm), ...
    'TechnicalID', string(run.TechnicalID), 'BatchStatus', "", ...
    'EffectiveStartFrame', NaN, 'EffectiveEndFrame', NaN, ...
    'EffectiveFrameCount', NaN, 'ExpectedTotalCycleFrames', ...
    double(run.ExpectedTotalCycleFrames), 'FrameCountErrorPercent', NaN, ...
    'CompleteCycleCount', NaN, 'ImagePeriodConsistencyErrorPercent', NaN, ...
    'MaximumSaturatedPixelPercent', NaN, ...
    'MaximumSaturatedPixelCount', NaN, 'FramesAtOrAboveWarning', NaN, ...
    'MaxRawP99', NaN, 'MeanDarkCorrectedRoiIntensity', NaN, ...
    'FrameMeanTemporalCvPercent', NaN, ...
    'SignificantActivityOutsideRoiPixels', NaN, ...
    'RoiX', roiRect(1), 'RoiY', roiRect(2), ...
    'RoiWidth', roiRect(3), 'RoiHeight', roiRect(4), ...
    'FileIntegrityPassed', false, 'ExposureQcPassed', false, ...
    'IntervalQcPassed', false, 'RoiQcPassed', false, ...
    'ImageQcPassed', false, 'BrightnessAnalysisEligible', false, ...
    'ImageQcStatus', "", 'Message', "", 'OutputFolder', string(outputFolder));
end

function writePartialLocal(rows, position, statusFile)
available = rows(1:position);
available = available(~cellfun(@isempty, available));
if ~isempty(available), writetable(vertcat(available{:}), statusFile); end
end

