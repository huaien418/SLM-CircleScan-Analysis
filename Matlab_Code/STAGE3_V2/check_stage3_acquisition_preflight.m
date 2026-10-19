function [summary, frameTable] = check_stage3_acquisition_preflight( ...
        imageFolder, config, roiSource)
%CHECK_STAGE3_ACQUISITION_PREFLIGHT Exposure/signal check for a 40 um pilot.
%
% No centroid or camera-derived geometric path is reported.

if nargin < 1 || strlength(string(imageFolder)) == 0
    selected = uigetdir(pwd, 'Select one 40 um preflight image folder');
    if isequal(selected, 0), error('No image folder was selected.'); end
    imageFolder = selected;
end
if nargin < 3
    roiSource = config.IntervalRoiSource;
end
if ~isfolder(imageFolder), error('Image folder not found: %s', imageFolder); end
if ~isfolder(config.DarkFolderBeginning)
    error('Matching dark-frame folder not found: %s', config.DarkFolderBeginning);
end

outputFolder = fullfile(imageFolder, 'AcquisitionPreflight_V2');
opts = struct('OutputFolder', outputFolder, 'WriteOutputs', true, ...
    'ConfirmAutoRoi', logical(config.ConfirmAutoRoi), ...
    'MakeDiagnosticPlot', logical(config.MakeFigures));
addpath(char(config.LegacyCodeRoot));
[interval, ~, ~] = detect_circle_scan_interval(imageFolder, roiSource, ...
    config.DarkFolderBeginning, config.CameraHz, config.RadiusMm, ...
    config.VelocityMmS, config.RequestedCycleCount, opts);
if ~isfinite(interval.RecommendedStartFrame(1))
    error('No effective five-cycle range was accepted. Review detector output.');
end

roiData = load(fullfile(outputFolder, 'roi_definition.mat'), 'roiRect');
roiRect = double(roiData.roiRect(:).');
files = stage3v2.listImages(imageFolder);
startFrame = round(interval.RecommendedStartFrame(1));
endFrame = round(interval.RecommendedEndFrame(1));
[firstImage, maxDigital] = stage3v2.readGray( ...
    fullfile(imageFolder, files(startFrame).name));
darkImage = stage3v2.loadDarkImage(config.DarkFolderBeginning, size(firstImage));
darkRoi = stage3v2.cropRoi(darkImage, roiRect);
[darkMean, darkTemporalNoiseSd, darkFrameCount] = ...
    darkTemporalNoiseLocal(config.DarkFolderBeginning, roiRect, size(firstImage));

frameCount = endFrame - startFrame + 1;
frameIndex = (startFrame:endFrame).';
imageName = strings(frameCount, 1);
roiMean = nan(frameCount, 1);
p99 = nan(frameCount, 1);
top1 = nan(frameCount, 1);
satPercent = nan(frameCount, 1);
top1PixelCount = NaN;
satThreshold = double(config.SaturationFractionOfDigitalMax) * maxDigital;
for position = 1:frameCount
    image = stage3v2.readGray(fullfile(imageFolder, ...
        files(frameIndex(position)).name));
    rawRoi = stage3v2.cropRoi(image, roiRect);
    correctedRoi = max(rawRoi - darkRoi, 0);
    values = correctedRoi(:);
    imageName(position) = string(files(frameIndex(position)).name);
    roiMean(position) = mean(values, 'omitnan');
    p99(position) = stage3v2.percentile(values, 99);
    [top1(position), top1PixelCount] = ...
        stage3v2.topFractionMean(values, 0.01);
    satPercent(position) = 100 * mean(rawRoi(:) >= satThreshold);
end
frameTable = table(frameIndex, imageName, roiMean, p99, top1, satPercent, ...
    'VariableNames', {'FrameIndex','ImageName','RoiMeanDN','P99DN', ...
    'Top1MeanDN','SaturatedPixelPercent'});

meanTop1 = mean(top1, 'omitnan');
% meanTop1 is already dark-corrected. Do not subtract darkMean again.
if darkTemporalNoiseSd > 0
    top1Snr = meanTop1 / darkTemporalNoiseSd;
elseif meanTop1 > 0
    top1Snr = Inf;
else
    top1Snr = 0;
end
maximumSaturation = max(satPercent, [], 'omitnan');
exposurePassed = maximumSaturation < config.MaximumSaturationPercent;
signalPassed = top1Snr >= config.MinimumTop1Snr;
if exposurePassed && signalPassed
    decision = "PASS";
    reason = "No saturation warning and Top1 signal exceeds the configured dark-noise gate.";
elseif ~exposurePassed
    decision = "SATURATION_REVIEW";
    reason = "At least one effective frame reached the saturation warning threshold.";
else
    decision = "LOW_SIGNAL_REVIEW";
    reason = "Top1 signal-to-dark-noise ratio is below the configured gate.";
end

summary = table(string(imageFolder), string(config.DarkFolderBeginning), ...
    config.ExposureUs, config.CameraHz, startFrame, endFrame, frameCount, ...
    roiRect(1), roiRect(2), roiRect(3), roiRect(4), top1PixelCount, ...
    mean(roiMean, 'omitnan'), mean(p99, 'omitnan'), meanTop1, ...
    darkMean, darkTemporalNoiseSd, darkFrameCount, top1Snr, ...
    maximumSaturation, exposurePassed, ...
    signalPassed, decision, reason, ...
    'VariableNames', {'ImageFolder','DarkFolder','ExposureUs','CameraHz', ...
    'StartFrame','EndFrame','FrameCount','RoiX','RoiY','RoiWidth', ...
    'RoiHeight','Top1PixelCount','MeanRoiMeanDN','MeanP99DN', ...
    'MeanTop1MeanDN','DarkMeanDN','DarkTemporalNoiseSdDN', ...
    'DarkFrameCount','Top1Snr', ...
    'MaximumSaturatedPixelPercent','ExposureQcPassed','SignalQcPassed', ...
    'PreflightDecision','Reason'});
writetable(frameTable, fullfile(outputFolder, 'preflight_frame_features.csv'));
writetable(summary, fullfile(outputFolder, 'preflight_summary.csv'));

fprintf('\n=== Stage 3 V2 acquisition preflight ===\n');
fprintf('Decision: %s\n', decision);
fprintf('Mean Top1: %.3f DN | Top1 SNR: %.3f\n', meanTop1, top1Snr);
fprintf('Maximum saturated pixel percent: %.6f%%\n', maximumSaturation);
fprintf('Effective range: [%d %d]\n', startFrame, endFrame);
fprintf('Output: %s\n', outputFolder);
end

function [darkMean, temporalNoiseSd, frameCount] = ...
        darkTemporalNoiseLocal(folder, roiRect, expectedSize)
files = stage3v2.listImages(folder);
frameCount = numel(files);
if frameCount < 2
    error('At least two matching dark frames are required for temporal-noise SNR.');
end
meanRoi = [];
m2Roi = [];
for fileIndex = 1:frameCount
    image = stage3v2.readGray(fullfile(folder, files(fileIndex).name));
    if ~isequal(size(image), expectedSize)
        error('Dark-frame dimensions changed within the folder.');
    end
    roi = stage3v2.cropRoi(image, roiRect);
    if isempty(meanRoi)
        meanRoi = zeros(size(roi));
        m2Roi = zeros(size(roi));
    end
    delta = roi - meanRoi;
    meanRoi = meanRoi + delta / fileIndex;
    m2Roi = m2Roi + delta .* (roi - meanRoi);
end
temporalVariance = m2Roi / (frameCount - 1);
darkMean = mean(meanRoi(:), 'omitnan');
temporalNoiseSd = sqrt(mean(temporalVariance(:), 'omitnan'));
end
