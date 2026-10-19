function referenceQc = analyze_reference_drift_v2(config, roiFile)
%ANALYZE_REFERENCE_DRIFT_V2 Compare beginning/end dark and naked references.

if nargin < 2 || strlength(string(roiFile)) == 0
    roiFile = fullfile(config.AnalysisRoot, 'roi', ...
        'stage3_v2_global_roi_approved.mat');
end
roi = stage3v2.loadApprovedRoi(roiFile);
qcRoot = fullfile(config.AnalysisRoot, 'qc');
if ~isfolder(qcRoot), mkdir(qcRoot); end

rows = repmat(emptyReferenceRowLocal(), 0, 1);
rows(end+1, 1) = comparePairLocal("DARK", ...
    config.DarkFolderBeginning, config.DarkFolderEnd, roi.roiRect, config, ...
    "", ""); %#ok<AGROW>
rows(end+1, 1) = comparePairLocal("NAKED", ...
    config.NakedBeginningFolder, config.NakedEndFolder, roi.roiRect, config, ...
    config.DarkFolderBeginning, config.DarkFolderEnd); %#ok<AGROW>
referenceQc = struct2table(rows);
outputFile = fullfile(qcRoot, 'stage3_v2_reference_qc.csv');
writetable(referenceQc, outputFile);
fprintf('\n=== Stage 3 V2 reference drift ===\n');
disp(referenceQc(:, {'ReferenceType','ReferenceQcStatus', ...
    'BeginningTop1MeanDN','EndTop1MeanDN','Top1DriftPercent', ...
    'MaximumSaturatedPixelPercent'}));
fprintf('Reference QC: %s\n', outputFile);
end

function row = comparePairLocal(referenceType, beginningFolder, endFolder, ...
        roiRect, config, beginningDarkFolder, endDarkFolder)
row = emptyReferenceRowLocal();
row.ReferenceType = referenceType;
row.BeginningFolder = string(beginningFolder);
row.EndFolder = string(endFolder);
if strlength(string(beginningFolder)) == 0 || strlength(string(endFolder)) == 0 || ...
        ~isfolder(beginningFolder) || ~isfolder(endFolder)
    row.ReferenceQcStatus = "NOT_AVAILABLE";
    row.Message = "Beginning/end reference folders were not both supplied.";
    return;
end
if referenceType == "NAKED" && ...
        (strlength(string(beginningDarkFolder)) == 0 || ...
        strlength(string(endDarkFolder)) == 0 || ...
        ~isfolder(beginningDarkFolder) || ~isfolder(endDarkFolder))
    row.ReferenceQcStatus = "NOT_AVAILABLE";
    row.Message = "Naked references are optional. When supplied, matching " + ...
        "beginning/end dark folders are required for valid correction.";
    return;
end
try
    beginning = referenceFeaturesLocal(beginningFolder, roiRect, config, ...
        beginningDarkFolder);
    ending = referenceFeaturesLocal(endFolder, roiRect, config, endDarkFolder);
    row.BeginningRoiMeanDN = beginning.RoiMeanDN;
    row.EndRoiMeanDN = ending.RoiMeanDN;
    row.RoiMeanDriftPercent = symmetricDifferenceLocal( ...
        beginning.RoiMeanDN, ending.RoiMeanDN);
    row.BeginningTop1MeanDN = beginning.Top1MeanDN;
    row.EndTop1MeanDN = ending.Top1MeanDN;
    row.Top1DriftPercent = symmetricDifferenceLocal( ...
        beginning.Top1MeanDN, ending.Top1MeanDN);
    row.MaximumSaturatedPixelPercent = max( ...
        beginning.MaximumSaturatedPixelPercent, ...
        ending.MaximumSaturatedPixelPercent);
    if row.MaximumSaturatedPixelPercent >= config.MaximumSaturationPercent
        row.ReferenceQcStatus = "REFERENCE_SATURATED";
        row.Message = "Drift values are not valid because a reference is saturated.";
    else
        row.ReferenceQcStatus = "AVAILABLE_NO_HARD_GATE";
        row.Message = "Drift is reported descriptively; no validated hard threshold exists yet.";
    end
    if referenceType == "NAKED"
        row.CorrectionMode = "PAIRED_DARK_CORRECTED";
    else
        row.CorrectionMode = "RAW_DARK_REFERENCE";
    end
catch ME
    row.ReferenceQcStatus = "FAILED";
    row.Message = string(ME.message);
end
end

function feature = referenceFeaturesLocal(folder, roiRect, config, darkFolder)
files = stage3v2.listImages(folder);
if isempty(files), error('No images in reference folder: %s', folder); end
darkImage = [];
if strlength(string(darkFolder)) > 0
    darkImage = stage3v2.loadDarkImage(darkFolder, []);
end
roiMeans = nan(numel(files), 1);
top1Means = nan(numel(files), 1);
satPercent = nan(numel(files), 1);
for fileIndex = 1:numel(files)
    [image, maxDigital] = stage3v2.readGray(fullfile(folder, files(fileIndex).name));
    rawRoi = stage3v2.cropRoi(image, roiRect);
    if isempty(darkImage)
        correctedRoi = rawRoi;
    else
        if ~isequal(size(image), size(darkImage))
            error('Reference image and matching dark image sizes differ.');
        end
        darkRoi = stage3v2.cropRoi(darkImage, roiRect);
        correctedRoi = max(rawRoi - darkRoi, 0);
    end
    values = double(correctedRoi(:));
    roiMeans(fileIndex) = mean(values, 'omitnan');
    top1Means(fileIndex) = stage3v2.topFractionMean(values, 0.01);
    satPercent(fileIndex) = 100 * mean(double(rawRoi(:)) >= ...
        config.SaturationFractionOfDigitalMax * maxDigital);
end
feature = struct('RoiMeanDN', mean(roiMeans, 'omitnan'), ...
    'Top1MeanDN', mean(top1Means, 'omitnan'), ...
    'MaximumSaturatedPixelPercent', max(satPercent, [], 'omitnan'));
end

function value = symmetricDifferenceLocal(a, b)
denominator = abs(a) + abs(b);
if denominator > 0, value = 200 * abs(a-b) / denominator; else, value = NaN; end
end

function row = emptyReferenceRowLocal()
row = struct('ReferenceType', "", 'BeginningFolder', "", 'EndFolder', "", ...
    'CorrectionMode', "", ...
    'BeginningRoiMeanDN', NaN, 'EndRoiMeanDN', NaN, ...
    'RoiMeanDriftPercent', NaN, 'BeginningTop1MeanDN', NaN, ...
    'EndTop1MeanDN', NaN, 'Top1DriftPercent', NaN, ...
    'MaximumSaturatedPixelPercent', NaN, 'ReferenceQcStatus', "", ...
    'Message', "");
end
