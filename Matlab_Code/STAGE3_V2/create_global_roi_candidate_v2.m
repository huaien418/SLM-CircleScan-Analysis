function candidate = create_global_roi_candidate_v2(config, manifest, intervalStatus, selectedK)
%CREATE_GLOBAL_ROI_CANDIDATE_V2 Build one candidate ROI from valid intervals.
%
% The candidate is never approved automatically. Run approve_global_roi_v2
% after visually checking the generated preview.

if nargin < 4 || isempty(selectedK)
    selectedK = 1:height(manifest);
end
selectedK = stage3v2.validateSelection(selectedK, height(manifest));
required = ["K" "BatchStatus" "RecommendedStartFrame" ...
    "RecommendedEndFrame"];
stage3v2.requireVariables(intervalStatus, required, 'intervalStatus');

roiFolder = fullfile(config.AnalysisRoot, 'roi');
if ~isfolder(roiFolder), mkdir(roiFolder); end
[darkImage, ~] = stage3v2.loadDarkImage(config.DarkFolderBeginning, []);

runRows = repmat(emptyRunRoiLocal(), 0, 1);
variationMaps = cell(0, 1);
meanImages = cell(0, 1);
imageSize = [];

for selectedPosition = 1:numel(selectedK)
    k = selectedK(selectedPosition);
    status = intervalStatus(intervalStatus.K == k, :);
    if height(status) ~= 1 || status.BatchStatus == "FAILED" || ...
            ~isfinite(status.RecommendedStartFrame(1)) || ...
            ~isfinite(status.RecommendedEndFrame(1))
        continue;
    end
    run = manifest(k, :);
    files = stage3v2.listImages(run.ImageFolder);
    startFrame = round(double(status.RecommendedStartFrame(1)));
    endFrame = round(double(status.RecommendedEndFrame(1)));
    if startFrame < 1 || endFrame > numel(files) || endFrame < startFrame
        error('K=%d interval is outside the image sequence.', k);
    end
    sampleCount = min(double(config.MaximumRoiCandidateFramesPerRun), ...
        endFrame - startFrame + 1);
    sampleIndices = unique(round(linspace(startFrame, endFrame, sampleCount)));
    [meanImage, variationImage] = sampledMomentsLocal( ...
        run.ImageFolder, files, sampleIndices, darkImage);
    if isempty(imageSize)
        imageSize = size(meanImage);
    elseif ~isequal(size(meanImage), imageSize)
        error('K=%d image dimensions differ from earlier datasets.', k);
    end
    autoRect = variationBoundingBoxLocal(variationImage, config.RoiMarginPixels);
    row = emptyRunRoiLocal();
    row.K = k;
    row.DatasetID = string(run.DatasetID);
    row.RoiX = autoRect(1);
    row.RoiY = autoRect(2);
    row.RoiWidth = autoRect(3);
    row.RoiHeight = autoRect(4);
    row.SampledFrameCount = numel(sampleIndices);
    runRows(end+1, 1) = row; %#ok<AGROW>
    variationMaps{end+1, 1} = variationImage; %#ok<AGROW>
    meanImages{end+1, 1} = meanImage; %#ok<AGROW>
end

if isempty(runRows)
    error('No valid interval datasets were available for Global ROI creation.');
end
runRois = struct2table(runRows);
roiRects = [runRois.RoiX, runRois.RoiY, runRois.RoiWidth, runRois.RoiHeight];
candidateRect = unionRectanglesLocal(roiRects, imageSize, config.RoiMarginPixels);
candidateArea = (candidateRect(3) + 1) * (candidateRect(4) + 1);
if candidateArea / prod(imageSize) > double(config.MaximumRoiAreaFraction)
    error(['Candidate Global ROI covers %.1f%% of the image, above the ' ...
        'configured %.1f%% limit. Inspect variation maps.'], ...
        100 * candidateArea / prod(imageSize), ...
        100 * double(config.MaximumRoiAreaFraction));
end

candidate = struct;
candidate.version = "STAGE3_V2_GLOBAL_ROI_CANDIDATE_1.0";
candidate.createdAt = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
candidate.roiRect = candidateRect;
candidate.imageSize = imageSize;
candidate.actualPixelCount = candidateArea;
candidate.sourceDatasetCount = height(runRois);
candidate.sourceDatasetIDs = runRois.DatasetID;
candidate.runRois = runRois;
candidate.approvalStatus = "CANDIDATE_NOT_APPROVED";

candidateFile = fullfile(roiFolder, 'stage3_v2_global_roi_candidate.mat');
tableFile = fullfile(roiFolder, 'stage3_v2_per_run_roi_candidates.csv');
save(candidateFile, 'candidate', 'meanImages', 'variationMaps');
writetable(runRois, tableFile);
writePreviewLocal(meanImages, runRois, candidateRect, roiFolder);

fprintf('\n=== Stage 3 V2 Global ROI candidate created ===\n');
fprintf('Source datasets: %d\n', height(runRois));
fprintf('Candidate [x y width height] = [%d %d %d %d]\n', candidateRect);
fprintf('Candidate file: %s\n', candidateFile);
fprintf('Next: approve_global_roi_v2(candidateFile)\n');
end

function [meanImage, stdImage] = sampledMomentsLocal(folder, files, indices, darkImage)
meanImage = [];
m2Image = [];
for position = 1:numel(indices)
    image = stage3v2.readGray(fullfile(folder, files(indices(position)).name));
    if ~isequal(size(image), size(darkImage))
        error('Experimental image and dark image sizes differ.');
    end
    corrected = max(image - darkImage, 0);
    if isempty(meanImage)
        meanImage = zeros(size(corrected));
        m2Image = zeros(size(corrected));
    end
    delta = corrected - meanImage;
    meanImage = meanImage + delta / position;
    m2Image = m2Image + delta .* (corrected - meanImage);
end
if numel(indices) > 1
    stdImage = sqrt(m2Image / (numel(indices) - 1));
else
    stdImage = zeros(size(meanImage));
end
end

function rect = variationBoundingBoxLocal(map, margin)
values = double(map(isfinite(map)));
location = median(values);
scale = 1.4826 * median(abs(values - location));
threshold = max(location + 4 * max(scale, eps), ...
    stage3v2.percentile(values, 97));
mask = map >= threshold;
if nnz(mask) < 8
    threshold = stage3v2.percentile(values, 99.5);
    mask = map >= threshold;
end
[row, column] = find(mask);
if isempty(row)
    error('Variation map did not contain a usable activity component.');
end
x1 = max(1, min(column) - margin);
y1 = max(1, min(row) - margin);
x2 = min(size(map, 2), max(column) + margin);
y2 = min(size(map, 1), max(row) + margin);
rect = [x1 y1 x2-x1 y2-y1];
end

function rect = unionRectanglesLocal(rectangles, imageSize, margin)
x1 = max(1, min(rectangles(:,1)) - margin);
y1 = max(1, min(rectangles(:,2)) - margin);
x2 = min(imageSize(2), max(rectangles(:,1) + rectangles(:,3)) + margin);
y2 = min(imageSize(1), max(rectangles(:,2) + rectangles(:,4)) + margin);
rect = round([x1 y1 x2-x1 y2-y1]);
end

function writePreviewLocal(meanImages, runRois, candidateRect, roiFolder)
columnCount = min(5, numel(meanImages));
rowCount = ceil(numel(meanImages) / columnCount);
fig = figure('Color', 'white', 'Name', 'Stage 3 V2 Global ROI candidate', ...
    'Position', [30 30 350*columnCount 320*rowCount]);
layout = tiledlayout(fig, rowCount, columnCount, ...
    'TileSpacing', 'compact', 'Padding', 'compact');
for index = 1:numel(meanImages)
    ax = nexttile(layout);
    imagesc(ax, meanImages{index});
    axis(ax, 'image');
    colormap(ax, 'turbo');
    hold(ax, 'on');
    runRect = [runRois.RoiX(index), runRois.RoiY(index), ...
        runRois.RoiWidth(index), runRois.RoiHeight(index)];
    rectangle(ax, 'Position', candidateRect, 'EdgeColor', 'r', 'LineWidth', 2);
    rectangle(ax, 'Position', runRect, 'EdgeColor', 'y', ...
        'LineStyle', '--', 'LineWidth', 1.2);
    title(ax, runRois.DatasetID(index), 'Interpreter', 'none', 'Color', 'black');
end
title(layout, sprintf(['Stage 3 V2 Global ROI candidate [%d %d %d %d]\n' ...
    'Red = union candidate; yellow = per-run automatic ROI'], candidateRect), ...
    'Color', 'black', 'FontWeight', 'bold');
previewFile = fullfile(roiFolder, 'stage3_v2_global_roi_candidate_preview.png');
exportgraphics(fig, previewFile, 'Resolution', 180);
close(fig);
end

function row = emptyRunRoiLocal()
row = struct('K', NaN, 'DatasetID', "", 'RoiX', NaN, 'RoiY', NaN, ...
    'RoiWidth', NaN, 'RoiHeight', NaN, 'SampledFrameCount', NaN);
end

