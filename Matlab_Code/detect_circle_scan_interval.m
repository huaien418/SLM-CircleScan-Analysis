function [summaryTable, circleTable, featureTable] = detect_circle_scan_interval( ...
    imageFolder, roiSource, darkFolder, cameraHz, radiusMm, ...
    velocityMmS, requestedCircleCount, options)
%DETECT_CIRCLE_SCAN_INTERVAL Detect CircleScan activity and repeated circles.
%
% This function performs two connected tasks in one public entry point:
%   1. Detect the sustained activity interval inside a manual S-to-H capture.
%   2. Estimate the repeated period and return conservative full-circle ranges.
% When roiSource is empty, a two-stage automatic ROI workflow first uses a
% downsampled full-frame sequence to find coarse activity, then builds a
% temporal variation map and proposes one fixed ROI for confirmation.
%
% Example:
%   opts = struct;
%   opts.WriteOutputs = true;
%   [summary, circles, features] = detect_circle_scan_interval( ...
%       'C:\data\40um_X0_Y0_R01', ...
%       'C:\data\ExposurePilot\InitialBrightness_Result\roi_definition.mat', ...
%       'C:\data\Dark_EXP1000', 20, 0.5, 1.0, 5, opts);
%
% roiSource may be:
%   - a roi_definition.mat path containing roiRect,
%   - a numeric [x y width height] rectangle, or
%   - empty, which runs automatic ROI detection and asks for confirmation.
%
% The result is image-evidence only. Manual camera S/H has no shared clock or
% trigger with CODESYS, so the returned ranges do not prove exact scanner
% phase or photo-to-command synchronization. Low-confidence results are
% marked NEEDS_MANUAL_REVIEW instead of being force-accepted.

if nargin < 1 || isempty(imageFolder)
    imageFolder = uigetdir(pwd, 'Select the complete S-to-H image folder');
    if isequal(imageFolder, 0)
        error('No image folder was selected.');
    end
end
if nargin < 2
    roiSource = '';
end
if nargin < 3
    darkFolder = '';
end
if nargin < 4 || isempty(cameraHz)
    cameraHz = 20;
end
if nargin < 5 || isempty(radiusMm)
    radiusMm = 0.5;
end
if nargin < 6 || isempty(velocityMmS)
    velocityMmS = 1.0;
end
if nargin < 7 || isempty(requestedCircleCount)
    requestedCircleCount = NaN;
end
if nargin < 8 || isempty(options)
    options = struct;
end

validatePositiveScalar(cameraHz, 'cameraHz');
validatePositiveScalar(radiusMm, 'radiusMm');
validatePositiveScalar(velocityMmS, 'velocityMmS');
if ~(isscalar(requestedCircleCount) && ...
        (isnan(requestedCircleCount) || ...
        (isfinite(requestedCircleCount) && requestedCircleCount >= 1)))
    error('requestedCircleCount must be NaN or a positive scalar.');
end

opts = mergeOptions(options, defaultOptions());
imageFolder = char(string(imageFolder));
darkFolder = char(string(darkFolder));

files = listImageFiles(imageFolder);
if isempty(files)
    error('No supported image files were found in: %s', imageFolder);
end
frameCount = numel(files);
if frameCount < 12
    error('At least 12 images are required; only %d were found.', frameCount);
end

[referenceImage, maxDigital] = buildMeanImage(imageFolder, files);
if ~isempty(darkFolder)
    darkFiles = listImageFiles(darkFolder);
    if isempty(darkFiles)
        error('No dark images were found in: %s', darkFolder);
    end
    [darkImage, ~] = buildMeanImage(darkFolder, darkFiles);
    assertSameSize(darkImage, referenceImage, 'dark reference');
    darkSource = string(darkFolder);
else
    darkImage = [];
    darkSource = "none";
end

expectedPeriodSeconds = 2 * pi * radiusMm / velocityMmS;
expectedPeriodFrames = cameraHz * expectedPeriodSeconds;

if isempty(darkImage)
    darkImage = zeros(size(referenceImage));
else
    assertSameSize(darkImage, referenceImage, 'dark reference');
end
[roiRect, roiSelectionMode, autoRoiDiagnostics] = resolveRoi( ...
    roiSource, referenceImage, imageFolder, files, darkImage, ...
    expectedPeriodFrames, cameraHz, requestedCircleCount, opts);

edgeFrameCount = round(opts.BaselineSeconds * cameraHz);
edgeFrameCount = max(3, min(edgeFrameCount, floor(frameCount / 4)));
baselineIndex = unique([2:edgeFrameCount, ...
    (frameCount - edgeFrameCount + 1):frameCount]);
baselineIndex = baselineIndex(baselineIndex >= 1 & baselineIndex <= frameCount);

[rawMean, correctedMean, correctedP99, spatialCv, saturationPercent, ...
    differenceEnergy, adjacentCorrelation, textureMatrix, imageNames] = ...
    extractFrameFeatures(imageFolder, files, roiRect, darkImage, ...
    maxDigital, opts.MaxTexturePixels);

baselineTexture = mean(double(textureMatrix(baselineIndex, :)), 1);
baselineTextureNorm = sqrt(sum(baselineTexture .^ 2));
if baselineTextureNorm > eps
    baselineTexture = baselineTexture / baselineTextureNorm;
    baselineTextureCorrelation = double(textureMatrix) * baselineTexture';
else
    baselineTextureCorrelation = zeros(frameCount, 1);
end
baselineTextureDistance = max(0, 1 - baselineTextureCorrelation);

meanStep = [NaN; abs(diff(correctedMean))];
p99Step = [NaN; abs(diff(correctedP99))];
textureChange = max(0, 1 - adjacentCorrelation);
baselineSpatialCv = median(spatialCv(baselineIndex), 'omitnan');
spatialCvDeviation = abs(spatialCv - baselineSpatialCv);

zDifference = positiveRobustZ(differenceEnergy, baselineIndex, opts.MaxFeatureZ);
zAdjacentTexture = positiveRobustZ(textureChange, baselineIndex, opts.MaxFeatureZ);
zBaselineTexture = positiveRobustZ( ...
    baselineTextureDistance, baselineIndex, opts.MaxFeatureZ);
zMeanStep = positiveRobustZ(meanStep, baselineIndex, opts.MaxFeatureZ);
zP99Step = positiveRobustZ(p99Step, baselineIndex, opts.MaxFeatureZ);
zSpatial = positiveRobustZ(spatialCvDeviation, baselineIndex, opts.MaxFeatureZ);

activityScore = 0.30 * zDifference + 0.25 * zAdjacentTexture + ...
    0.20 * zBaselineTexture + 0.10 * zMeanStep + ...
    0.10 * zP99Step + 0.05 * zSpatial;

smoothWindow = max(1, round(opts.SmoothSeconds * cameraHz));
if mod(smoothWindow, 2) == 0
    smoothWindow = smoothWindow + 1;
end
smoothedActivityScore = movmean(activityScore, smoothWindow, ...
    'Endpoints', 'shrink');

[baselineActivityLocation, baselineActivityScale] = ...
    robustLocationScale(smoothedActivityScore(baselineIndex));
activityThreshold = max(opts.ActivityThreshold, ...
    baselineActivityLocation + ...
    opts.BaselineSigmaThreshold * baselineActivityScale);

activeMask = smoothedActivityScore >= activityThreshold;
maxGapFrames = max(1, round(opts.MergeGapFractionPeriod * expectedPeriodFrames));
minimumRunFrames = max(3, round( ...
    opts.MinimumActivityFractionPeriod * expectedPeriodFrames));
activeMask = fillShortGaps(activeMask, maxGapFrames);
activeMask = removeShortRuns(activeMask, minimumRunFrames);

[runStarts, runEnds] = logicalRuns(activeMask);
candidateStart = NaN;
candidateEnd = NaN;
if ~isempty(runStarts)
    selectedRun = chooseActivityRun(runStarts, runEnds, ...
        smoothedActivityScore, expectedPeriodFrames, requestedCircleCount);
    candidateStart = runStarts(selectedRun);
    candidateEnd = runEnds(selectedRun);

    lowerThreshold = max( ...
        baselineActivityLocation + 1.5 * baselineActivityScale, ...
        0.55 * activityThreshold);
    while candidateStart > 2 && ...
            smoothedActivityScore(candidateStart - 1) >= lowerThreshold
        candidateStart = candidateStart - 1;
    end
    while candidateEnd < frameCount && ...
            smoothedActivityScore(candidateEnd + 1) >= lowerThreshold
        candidateEnd = candidateEnd + 1;
    end
    edgePadding = floor(smoothWindow / 2);
    candidateStart = max(1, candidateStart - edgePadding);
    candidateEnd = min(frameCount, candidateEnd + edgePadding);
end

candidateMask = false(frameCount, 1);
if isfinite(candidateStart)
    candidateMask(candidateStart:candidateEnd) = true;
end

lags = zeros(0, 1);
roiRecurrence = zeros(0, 1);
featureAutocorrelation = zeros(0, 1);
periodEvidence = zeros(0, 1);
fftPeriodFrames = NaN;
spectralStrength = 0;
periodFrames = NaN;
periodUncertaintyFrames = NaN;
periodicityStrength = 0;

if isfinite(candidateStart)
    candidateLength = candidateEnd - candidateStart + 1;
    minimumLag = max(2, floor(expectedPeriodFrames * ...
        (1 - opts.PeriodToleranceFraction)));
    maximumLag = ceil(expectedPeriodFrames * ...
        (1 + opts.PeriodToleranceFraction));
    maximumLag = min(maximumLag, candidateLength - 4);

    if maximumLag >= minimumLag && candidateLength >= 1.5 * expectedPeriodFrames
        lags = (minimumLag:maximumLag)';
        periodicSignals = [correctedMean, correctedP99, spatialCv, ...
            baselineTextureCorrelation];
        [roiRecurrence, featureAutocorrelation] = calculateLagCurves( ...
            textureMatrix, periodicSignals, candidateStart, candidateEnd, lags);

        [recurrenceEvidence, recurrenceStrength] = ...
            normalizePeriodEvidence(roiRecurrence, 0.12);
        [autocorrelationEvidence, autocorrelationStrength] = ...
            normalizePeriodEvidence(featureAutocorrelation, 0.18);
        periodEvidence = 0.60 * recurrenceEvidence + ...
            0.40 * autocorrelationEvidence;
        periodicityStrength = 0.60 * recurrenceStrength + ...
            0.40 * autocorrelationStrength;

        if any(isfinite(periodEvidence)) && max(periodEvidence) > 0
            [~, peakIndex] = max(periodEvidence);
            periodFrames = refinePeakLocation(lags, periodEvidence, peakIndex);
            periodUncertaintyFrames = estimatePeakUncertainty( ...
                lags, periodEvidence, peakIndex);
        end

        [fftPeriodFrames, spectralStrength] = estimateFftPeriod( ...
            periodicSignals(candidateStart:candidateEnd, :), ...
            minimumLag, maximumLag);
        if ~isfinite(periodFrames) && isfinite(fftPeriodFrames)
            periodFrames = fftPeriodFrames;
            periodUncertaintyFrames = max(1, ...
                opts.PeriodToleranceFraction * expectedPeriodFrames / 2);
        elseif isfinite(periodFrames) && isfinite(fftPeriodFrames)
            periodUncertaintyFrames = max(periodUncertaintyFrames, ...
                abs(periodFrames - fftPeriodFrames) / 2);
        end
    end
end

[circleTable, selectedStart, selectedEnd, completeCircleCount, ...
    boundaryUncertaintyFrames] = buildConservativeCircles( ...
    candidateStart, candidateEnd, periodFrames, periodUncertaintyFrames, ...
    smoothWindow, requestedCircleCount);

selectedCircleMask = false(frameCount, 1);
if isfinite(selectedStart)
    selectedCircleMask(selectedStart:selectedEnd) = true;
end

candidateDurationFrames = NaN;
estimatedCircleCount = NaN;
if isfinite(candidateStart)
    candidateDurationFrames = candidateEnd - candidateStart + 1;
    if isfinite(periodFrames) && periodFrames > 0
        estimatedCircleCount = candidateDurationFrames / periodFrames;
    end
end

[confidence, status, reason] = classifyDetection( ...
    candidateStart, candidateEnd, smoothedActivityScore, baselineIndex, ...
    activityThreshold, expectedPeriodFrames, periodFrames, fftPeriodFrames, ...
    periodicityStrength, spectralStrength, completeCircleCount, ...
    requestedCircleCount, saturationPercent, correctedMean, opts);

nominalTimeSeconds = ((0:frameCount-1)' / cameraHz);
featureTable = table((1:frameCount)', imageNames, nominalTimeSeconds, ...
    rawMean, correctedMean, correctedP99, spatialCv, saturationPercent, ...
    differenceEnergy, adjacentCorrelation, textureChange, ...
    baselineTextureCorrelation, baselineTextureDistance, activityScore, ...
    smoothedActivityScore, candidateMask, selectedCircleMask, ...
    'VariableNames', {'FrameIndex','ImageName','NominalTimeSeconds', ...
    'MeanRaw','MeanDarkCorrected','P99DarkCorrected','SpatialCvPercent', ...
    'SaturatedPixelPercent','DifferenceEnergy','AdjacentCorrelation', ...
    'TextureChange','BaselineTextureCorrelation', ...
    'BaselineTextureDistance','ActivityScore','SmoothedActivityScore', ...
    'IsCandidateActivity','IsSelectedFullCircle'});

if isfinite(periodFrames)
    periodSeconds = periodFrames / cameraHz;
else
    periodSeconds = NaN;
end

outputFolder = resolveOutputFolder(imageFolder, opts.OutputFolder);
summaryTable = table(string(imageFolder), frameCount, cameraHz, radiusMm, ...
    velocityMmS, requestedCircleCount, expectedPeriodFrames, ...
    expectedPeriodSeconds, candidateStart, candidateEnd, ...
    candidateDurationFrames, periodFrames, periodSeconds, ...
    fftPeriodFrames, periodUncertaintyFrames, estimatedCircleCount, ...
    completeCircleCount, selectedStart, selectedEnd, ...
    boundaryUncertaintyFrames, confidence, string(status), string(reason), ...
    darkSource, string(roiSelectionMode), ...
    roiRect(1), roiRect(2), roiRect(3), roiRect(4), ...
    autoRoiDiagnostics.Confidence, ...
    autoRoiDiagnostics.CoarseStartFrame, ...
    autoRoiDiagnostics.CoarseEndFrame, ...
    autoRoiDiagnostics.VariationThreshold, ...
    autoRoiDiagnostics.CandidateCount, ...
    autoRoiDiagnostics.SecondBestScoreRatio, ...
    string(outputFolder), ...
    'VariableNames', {'ImageFolder','FrameCount','CameraHz','RadiusMm', ...
    'VelocityMmS','RequestedCircleCount','ExpectedPeriodFrames', ...
    'ExpectedPeriodSeconds','CandidateStartFrame','CandidateEndFrame', ...
    'CandidateDurationFrames','EstimatedPeriodFrames', ...
    'EstimatedPeriodSeconds','FftPeriodFrames','PeriodUncertaintyFrames', ...
    'EstimatedCircleCount','CompleteCircleCount', ...
    'RecommendedStartFrame','RecommendedEndFrame', ...
    'BoundaryUncertaintyFrames','Confidence','Status','Reason', ...
    'DarkFolder','RoiSelectionMode','RoiX','RoiY','RoiWidth','RoiHeight', ...
    'AutoRoiConfidence','AutoRoiCoarseStartFrame', ...
    'AutoRoiCoarseEndFrame','AutoRoiVariationThreshold', ...
    'AutoRoiCandidateCount','AutoRoiSecondBestScoreRatio','OutputFolder'});

if opts.WriteOutputs
    if ~isfolder(outputFolder)
        mkdir(outputFolder);
    end
    writetable(featureTable, fullfile(outputFolder, 'feature_timeseries.csv'));
    writetable(summaryTable, fullfile(outputFolder, 'detection_summary.csv'));
    writetable(circleTable, fullfile(outputFolder, 'detected_circles.csv'));
    save(fullfile(outputFolder, 'circle_interval_analysis.mat'), ...
        'summaryTable', 'circleTable', 'featureTable', 'roiRect', ...
        'darkImage', 'lags', 'roiRecurrence', ...
        'featureAutocorrelation', 'periodEvidence', 'opts', ...
        'roiSelectionMode', 'autoRoiDiagnostics');
    save(fullfile(outputFolder, 'roi_definition.mat'), ...
        'roiRect', 'roiSelectionMode', 'autoRoiDiagnostics');
    if autoRoiDiagnostics.WasAttempted && ...
            ~isempty(autoRoiDiagnostics.VariationMap)
        writeAutoRoiPreview(outputFolder, referenceImage, roiRect, ...
            autoRoiDiagnostics, opts);
    end
    if opts.MakeDiagnosticPlot
        writeDiagnosticPlot(outputFolder, featureTable, summaryTable, ...
            circleTable, lags, roiRecurrence, featureAutocorrelation, ...
            periodEvidence, activityThreshold, opts);
    end
end

fprintf('\nCircle interval detection: %s\n', status);
fprintf('%s\n', reason);
fprintf('Expected period: %.2f frames; estimated period: %.2f frames\n', ...
    expectedPeriodFrames, periodFrames);
fprintf('Candidate activity: %.0f to %.0f; complete circles: %d\n', ...
    candidateStart, candidateEnd, completeCircleCount);
fprintf('ROI selection: %s; rectangle: [%d %d %d %d]\n', ...
    roiSelectionMode, roiRect(1), roiRect(2), roiRect(3), roiRect(4));
if isfinite(selectedStart)
    fprintf('Recommended frameRange for analyze_first_layer: [%d %d]\n', ...
        selectedStart, selectedEnd);
else
    fprintf('No automatic frameRange was accepted. Review the diagnostic plot.\n');
end
if opts.WriteOutputs
    fprintf('Output folder:\n%s\n', outputFolder);
end
end

function opts = defaultOptions()
opts = struct;
opts.BaselineSeconds = 1.0;
opts.SmoothSeconds = 0.20;
opts.PeriodToleranceFraction = 0.25;
opts.ActivityThreshold = 2.0;
opts.BaselineSigmaThreshold = 3.5;
opts.MinimumActivityFractionPeriod = 0.35;
opts.MergeGapFractionPeriod = 0.15;
opts.MinimumCompleteCircles = 3;
opts.ConfidenceAcceptThreshold = 0.75;
opts.MaximumSaturationPercent = 0.10;
opts.MinimumCorrectedMean = 5.0;
opts.MaxFeatureZ = 12;
opts.MaxTexturePixels = 2048;
opts.ConfirmAutoRoi = true;
opts.AutoRoiMarginPixels = 8;
opts.AutoRoiMaxDimension = 192;
opts.AutoRoiMaxFrames = 400;
opts.AutoRoiMinimumComponentPixels = 8;
opts.AutoRoiMaximumAreaFraction = 0.35;
opts.AutoRoiMaximumSecondBestRatio = 0.85;
opts.AutoRoiMinimumPeriodicity = 0.30;
opts.AutoRoiMinimumConfidence = 0.55;
opts.OutputFolder = '';
opts.WriteOutputs = true;
opts.MakeDiagnosticPlot = true;
opts.FigureVisible = 'off';
end

function opts = mergeOptions(userOptions, defaults)
if ~isstruct(userOptions) || ~isscalar(userOptions)
    error('options must be a scalar struct.');
end
opts = defaults;
names = fieldnames(userOptions);
knownNames = fieldnames(defaults);
for i = 1:numel(names)
    if ~ismember(names{i}, knownNames)
        error('Unknown options field: %s', names{i});
    end
    opts.(names{i}) = userOptions.(names{i});
end
validatePositiveScalar(opts.BaselineSeconds, 'options.BaselineSeconds');
validatePositiveScalar(opts.SmoothSeconds, 'options.SmoothSeconds');
validatePositiveScalar(opts.PeriodToleranceFraction, ...
    'options.PeriodToleranceFraction');
validatePositiveScalar(opts.ActivityThreshold, 'options.ActivityThreshold');
validatePositiveScalar(opts.BaselineSigmaThreshold, ...
    'options.BaselineSigmaThreshold');
validatePositiveScalar(opts.MinimumCompleteCircles, ...
    'options.MinimumCompleteCircles');
validatePositiveScalar(opts.ConfidenceAcceptThreshold, ...
    'options.ConfidenceAcceptThreshold');
validatePositiveScalar(opts.MaxTexturePixels, 'options.MaxTexturePixels');
if ~(islogical(opts.ConfirmAutoRoi) || ...
        (isnumeric(opts.ConfirmAutoRoi) && isscalar(opts.ConfirmAutoRoi)))
    error('options.ConfirmAutoRoi must be a logical scalar.');
end
opts.ConfirmAutoRoi = logical(opts.ConfirmAutoRoi);
if ~(isnumeric(opts.AutoRoiMarginPixels) && ...
        isscalar(opts.AutoRoiMarginPixels) && ...
        isfinite(opts.AutoRoiMarginPixels) && ...
        opts.AutoRoiMarginPixels == round(opts.AutoRoiMarginPixels) && ...
        opts.AutoRoiMarginPixels >= 5 && opts.AutoRoiMarginPixels <= 10)
    error('options.AutoRoiMarginPixels must be an integer from 5 to 10.');
end
validatePositiveScalar(opts.AutoRoiMaxDimension, ...
    'options.AutoRoiMaxDimension');
validatePositiveScalar(opts.AutoRoiMaxFrames, 'options.AutoRoiMaxFrames');
validatePositiveScalar(opts.AutoRoiMinimumComponentPixels, ...
    'options.AutoRoiMinimumComponentPixels');
validateUnitInterval(opts.AutoRoiMaximumAreaFraction, ...
    'options.AutoRoiMaximumAreaFraction');
validateUnitInterval(opts.AutoRoiMaximumSecondBestRatio, ...
    'options.AutoRoiMaximumSecondBestRatio');
validateUnitInterval(opts.AutoRoiMinimumPeriodicity, ...
    'options.AutoRoiMinimumPeriodicity');
validateUnitInterval(opts.AutoRoiMinimumConfidence, ...
    'options.AutoRoiMinimumConfidence');
end

function validatePositiveScalar(value, name)
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
    error('%s must be a positive finite scalar.', name);
end
end

function validateUnitInterval(value, name)
if ~(isnumeric(value) && isscalar(value) && isfinite(value) && ...
        value > 0 && value < 1)
    error('%s must be a finite scalar strictly between 0 and 1.', name);
end
end

function outputFolder = resolveOutputFolder(imageFolder, configuredFolder)
if isempty(configuredFolder)
    outputFolder = fullfile(imageFolder, 'CircleIntervalDetection_Result');
else
    outputFolder = char(string(configuredFolder));
end
end

function [roiRect, selectionMode, diagnostics] = resolveRoi( ...
    roiSource, referenceImage, imageFolder, files, darkImage, ...
    expectedPeriodFrames, cameraHz, requestedCircleCount, opts)

diagnostics = emptyAutoRoiDiagnostics();
if ~isempty(roiSource)
    if isnumeric(roiSource)
        roiRect = roiSource;
        selectionMode = "PROVIDED_NUMERIC";
    else
        roiPath = char(string(roiSource));
        if ~isfile(roiPath)
            error('ROI file does not exist: %s', roiPath);
        end
        roiData = load(roiPath, 'roiRect');
        if ~isfield(roiData, 'roiRect')
            error('ROI file does not contain roiRect: %s', roiPath);
        end
        roiRect = roiData.roiRect;
        selectionMode = "PROVIDED_FILE";
    end
    roiRect = validateRectangle(roiRect, size(referenceImage));
    return;
end

diagnostics.WasAttempted = true;
try
    [roiRect, diagnostics] = detectAutomaticCircleRoi( ...
        imageFolder, files, darkImage, expectedPeriodFrames, cameraHz, ...
        requestedCircleCount, opts);
    selectionMode = "AUTO";
catch ME
    diagnostics = emptyAutoRoiDiagnostics();
    diagnostics.WasAttempted = true;
    diagnostics.Status = "FAILED";
    diagnostics.Reason = string(ME.message);
    if ~opts.ConfirmAutoRoi
        error('detect_circle_scan_interval:AutoRoiFailed', ...
            'Automatic ROI selection failed: %s', ME.message);
    end
    warning('detect_circle_scan_interval:AutoRoiFailed', ...
        'Automatic ROI selection failed: %s\nSwitching to manual selection.', ...
        ME.message);
    roiRect = selectRectangle(referenceImage);
    roiRect = validateRectangle(roiRect, size(referenceImage));
    selectionMode = "MANUAL_FALLBACK";
    return;
end

roiRect = validateRectangle(roiRect, size(referenceImage));
if opts.ConfirmAutoRoi
    variationDisplay = expandMapToImage( ...
        diagnostics.VariationMap, size(referenceImage));
    confirmation = confirmAutomaticCircleRoi( ...
        referenceImage, variationDisplay, roiRect, diagnostics);
    if confirmation == "ACCEPT"
        selectionMode = "AUTO_CONFIRMED";
        diagnostics.Status = "CONFIRMED";
    elseif confirmation == "MANUAL"
        roiRect = selectRectangle(referenceImage);
        roiRect = validateRectangle(roiRect, size(referenceImage));
        selectionMode = "MANUAL_OVERRIDE";
        diagnostics.Status = "REJECTED_BY_USER";
        diagnostics.Reason = "Automatic ROI was replaced by a manual rectangle.";
    else
        error('detect_circle_scan_interval:RoiConfirmationCancelled', ...
            'ROI confirmation was cancelled. No result files were written.');
    end
end
end

function diagnostics = emptyAutoRoiDiagnostics()
diagnostics = struct( ...
    'WasAttempted', false, ...
    'Status', "NOT_RUN", ...
    'Reason', "An explicit ROI was supplied.", ...
    'Confidence', NaN, ...
    'CoarseStartFrame', NaN, ...
    'CoarseEndFrame', NaN, ...
    'CoarseActivityThreshold', NaN, ...
    'VariationThreshold', NaN, ...
    'CandidateCount', 0, ...
    'SecondBestScoreRatio', NaN, ...
    'SelectedComponentAreaPixels', NaN, ...
    'SelectedPeriodicity', NaN, ...
    'SampledFrameIndices', zeros(0, 1), ...
    'SampleRows', zeros(0, 1), ...
    'SampleColumns', zeros(0, 1), ...
    'VariationMap', single(zeros(0, 0)), ...
    'CandidateMask', false(0, 0), ...
    'ProposedRoiRect', [NaN NaN NaN NaN]);
end

function [roiRect, diagnostics] = detectAutomaticCircleRoi( ...
    imageFolder, files, darkImage, expectedPeriodFrames, cameraHz, ...
    requestedCircleCount, opts)

[frameCube, sampleRows, sampleColumns, sampledFrameIndices] = ...
    buildCoarseFrameCube(imageFolder, files, darkImage, opts);
[coarseStartFrame, coarseEndFrame, coarseThreshold] = ...
    detectCoarseActivity(frameCube, sampledFrameIndices, ...
    expectedPeriodFrames, cameraHz, requestedCircleCount, opts);

activitySamples = find(sampledFrameIndices >= coarseStartFrame & ...
    sampledFrameIndices <= coarseEndFrame);
frameStep = max(1, median(diff(double(sampledFrameIndices))));
sampledPeriodFrames = expectedPeriodFrames / frameStep;
minimumActivitySamples = max(8, ceil(1.5 * sampledPeriodFrames));
if numel(activitySamples) < minimumActivitySamples
    error('The coarse activity interval contains only %d sampled frames; %d are required.', ...
        numel(activitySamples), minimumActivitySamples);
end

activityCube = frameCube(:, :, activitySamples);
percentileRange = temporalPercentileRange(activityCube, 5, 95);
temporalStd = std(activityCube, 0, 3);
variationMap = max(double(percentileRange), 3 * double(temporalStd));
variationMap = conv2(double(variationMap), ones(3, 3) / 9, 'same');
finiteVariation = variationMap(isfinite(variationMap));
variationBackground = median(finiteVariation);
variationSigma = 1.4826 * median(abs(finiteVariation - variationBackground));
variationPeak = max(finiteVariation);
variationContrast = variationPeak - variationBackground;
minimumVariationContrast = max(1, 6 * variationSigma);
if ~isfinite(variationContrast) || variationContrast <= minimumVariationContrast
    error('Temporal variation is too weak for a reliable moving-light ROI.');
end

variationThreshold = variationBackground + max( ...
    6 * variationSigma, 0.15 * variationContrast);
candidateMask = variationMap >= variationThreshold;
candidateMask = binaryCloseLocal(candidateMask, 2);
components = connectedComponentsLocal(candidateMask);

validComponents = cell(0, 1);
componentEnergy = zeros(0, 1);
componentPeriodicity = zeros(0, 1);
componentArea = zeros(0, 1);
for componentIndex = 1:numel(components)
    indices = components{componentIndex};
    area = numel(indices);
    if area < opts.AutoRoiMinimumComponentPixels || ...
            area > opts.AutoRoiMaximumAreaFraction * numel(candidateMask)
        continue;
    end
    [componentRows, componentColumns] = ind2sub(size(candidateMask), indices);
    if any(componentRows == 1 | componentRows == size(candidateMask, 1) | ...
            componentColumns == 1 | componentColumns == size(candidateMask, 2))
        continue;
    end
    recurrence = periodicRecurrenceForMask( ...
        frameCube, indices, activitySamples, sampledPeriodFrames);
    validComponents{end+1, 1} = indices; %#ok<AGROW>
    componentEnergy(end+1, 1) = sum(variationMap(indices)); %#ok<AGROW>
    componentPeriodicity(end+1, 1) = recurrence; %#ok<AGROW>
    componentArea(end+1, 1) = area; %#ok<AGROW>
end

candidateCount = numel(validComponents);
if candidateCount == 0
    error(['No temporal-variation component passed the area and image-edge ' ...
        'safety gates.']);
end

energyScore = componentEnergy / max(componentEnergy);
periodicityScore = arrayfun(@(value) clamp01((value - 0.10) / 0.80), ...
    componentPeriodicity);
combinedScore = 0.45 * energyScore + 0.55 * periodicityScore;
[sortedScore, scoreOrder] = sort(combinedScore, 'descend');
bestIndex = scoreOrder(1);
if candidateCount >= 2
    secondBestRatio = sortedScore(2) / max(sortedScore(1), eps);
else
    secondBestRatio = 0;
end
if secondBestRatio >= opts.AutoRoiMaximumSecondBestRatio
    error(['Multiple moving candidates have similar scores ' ...
        '(second/best = %.3f).'], secondBestRatio);
end

bestIndices = validComponents{bestIndex};
if componentPeriodicity(bestIndex) < opts.AutoRoiMinimumPeriodicity
    error(['The strongest moving component has recurrence %.3f, below the ' ...
        '%.3f periodicity threshold.'], componentPeriodicity(bestIndex), ...
        opts.AutoRoiMinimumPeriodicity);
end
bestMask = false(size(candidateMask));
bestMask(bestIndices) = true;
[bestRows, bestColumns] = ind2sub(size(bestMask), bestIndices);
boxHeight = max(bestRows) - min(bestRows) + 1;
boxWidth = max(bestColumns) - min(bestColumns) + 1;
aspectRatio = boxWidth / max(boxHeight, 1);
if aspectRatio < 0.40 || aspectRatio > 2.50
    error('The selected moving component has an implausible aspect ratio %.2f.', ...
        aspectRatio);
end

contrastScore = clamp01(variationContrast / ...
    max(18 * max(variationSigma, eps), eps));
periodScore = periodicityScore(bestIndex);
ambiguityScore = clamp01(1 - secondBestRatio);
confidence = 0.35 * contrastScore + 0.45 * periodScore + ...
    0.20 * ambiguityScore;
if confidence < opts.AutoRoiMinimumConfidence
    error('Automatic ROI confidence %.3f is below the %.3f threshold.', ...
        confidence, opts.AutoRoiMinimumConfidence);
end

minimumRow = min(bestRows);
maximumRow = max(bestRows);
minimumColumn = min(bestColumns);
maximumColumn = max(bestColumns);
rowSamplingMargin = samplingHalfStep(sampleRows);
columnSamplingMargin = samplingHalfStep(sampleColumns);
y1 = sampleRows(minimumRow) - rowSamplingMargin - opts.AutoRoiMarginPixels;
y2 = sampleRows(maximumRow) + rowSamplingMargin + opts.AutoRoiMarginPixels;
x1 = sampleColumns(minimumColumn) - columnSamplingMargin - opts.AutoRoiMarginPixels;
x2 = sampleColumns(maximumColumn) + columnSamplingMargin + opts.AutoRoiMarginPixels;
imageSize = size(darkImage);
if x1 <= 1 || y1 <= 1 || x2 >= imageSize(2) || y2 >= imageSize(1)
    error('The proposed moving-light ROI touches the image boundary.');
end
roiRect = validateRectangle([x1, y1, x2 - x1, y2 - y1], imageSize);
roiAreaFraction = ((roiRect(3) + 1) * (roiRect(4) + 1)) / ...
    (imageSize(1) * imageSize(2));
if roiRect(3) + 1 < 2 * opts.AutoRoiMarginPixels + 5 || ...
        roiRect(4) + 1 < 2 * opts.AutoRoiMarginPixels + 5
    error('The proposed moving-light ROI is implausibly small.');
end
if roiAreaFraction > opts.AutoRoiMaximumAreaFraction
    error('The proposed moving-light ROI covers %.1f%% of the image.', ...
        100 * roiAreaFraction);
end

diagnostics = emptyAutoRoiDiagnostics();
diagnostics.WasAttempted = true;
diagnostics.Status = "DETECTED";
diagnostics.Reason = "Periodic temporal variation produced one acceptable fixed ROI.";
diagnostics.Confidence = confidence;
diagnostics.CoarseStartFrame = coarseStartFrame;
diagnostics.CoarseEndFrame = coarseEndFrame;
diagnostics.CoarseActivityThreshold = coarseThreshold;
diagnostics.VariationThreshold = variationThreshold;
diagnostics.CandidateCount = candidateCount;
diagnostics.SecondBestScoreRatio = secondBestRatio;
diagnostics.SelectedComponentAreaPixels = componentArea(bestIndex);
diagnostics.SelectedPeriodicity = componentPeriodicity(bestIndex);
diagnostics.SampledFrameIndices = sampledFrameIndices;
diagnostics.SampleRows = sampleRows;
diagnostics.SampleColumns = sampleColumns;
diagnostics.VariationMap = single(variationMap);
diagnostics.CandidateMask = bestMask;
diagnostics.ProposedRoiRect = roiRect;
end

function [frameCube, sampleRows, sampleColumns, sampledFrameIndices] = ...
    buildCoarseFrameCube(imageFolder, files, darkImage, opts)

imageSize = size(darkImage);
scale = min(1, opts.AutoRoiMaxDimension / max(imageSize(1:2)));
sampleHeight = max(16, round(imageSize(1) * scale));
sampleWidth = max(16, round(imageSize(2) * scale));
sampleRows = unique(round(linspace(1, imageSize(1), sampleHeight)))';
sampleColumns = unique(round(linspace(1, imageSize(2), sampleWidth)))';
sampledFrameCount = min(numel(files), round(opts.AutoRoiMaxFrames));
sampledFrameIndices = unique(round(linspace(1, numel(files), sampledFrameCount)))';
frameCube = zeros(numel(sampleRows), numel(sampleColumns), ...
    numel(sampledFrameIndices), 'single');
darkSample = darkImage(sampleRows, sampleColumns);
referenceSize = imageSize(1:2);
for sampleIndex = 1:numel(sampledFrameIndices)
    frameIndex = sampledFrameIndices(sampleIndex);
    image = readGrayDouble(fullfile(imageFolder, files(frameIndex).name));
    if ~isequal(size(image), referenceSize)
        error('Image size mismatch: %s', files(frameIndex).name);
    end
    corrected = image(sampleRows, sampleColumns) - darkSample;
    corrected(corrected < 0) = 0;
    frameCube(:, :, sampleIndex) = single(corrected);
end
end

function [startFrame, endFrame, activityThreshold] = detectCoarseActivity( ...
    frameCube, sampledFrameIndices, expectedPeriodFrames, cameraHz, ...
    requestedCircleCount, opts)

sampleCount = size(frameCube, 3);
differenceEnergy = nan(sampleCount, 1);
for i = 2:sampleCount
    delta = double(frameCube(:, :, i)) - double(frameCube(:, :, i - 1));
    differenceEnergy(i) = sqrt(mean(delta(:) .^ 2));
end

frameStep = max(1, median(diff(double(sampledFrameIndices))));
edgeFrames = max(3, round(opts.BaselineSeconds * cameraHz));
baselineIndex = find(sampledFrameIndices <= edgeFrames | ...
    sampledFrameIndices >= sampledFrameIndices(end) - edgeFrames + 1);
if numel(baselineIndex) < 4
    edgeSamples = max(2, min(floor(sampleCount / 4), 5));
    baselineIndex = unique([1:edgeSamples, sampleCount-edgeSamples+1:sampleCount]);
end
activity = positiveRobustZ(differenceEnergy, baselineIndex, opts.MaxFeatureZ);
smoothWindow = max(1, round(opts.SmoothSeconds * cameraHz / frameStep));
if mod(smoothWindow, 2) == 0
    smoothWindow = smoothWindow + 1;
end
activity = movmean(activity, smoothWindow, 'Endpoints', 'shrink');
[baselineLocation, baselineScale] = robustLocationScale(activity(baselineIndex));
activityThreshold = max(opts.ActivityThreshold, ...
    baselineLocation + opts.BaselineSigmaThreshold * baselineScale);

sampledPeriod = expectedPeriodFrames / frameStep;
activeMask = activity >= activityThreshold;
activeMask = fillShortGaps(activeMask, max(1, round( ...
    opts.MergeGapFractionPeriod * sampledPeriod)));
activeMask = removeShortRuns(activeMask, max(3, round( ...
    opts.MinimumActivityFractionPeriod * sampledPeriod)));
[runStarts, runEnds] = logicalRuns(activeMask);
if isempty(runStarts)
    error('No sustained full-frame motion interval passed the coarse threshold.');
end
selectedRun = chooseActivityRun(runStarts, runEnds, activity, ...
    sampledPeriod, requestedCircleCount);
sampleStart = runStarts(selectedRun);
sampleEnd = runEnds(selectedRun);
lowerThreshold = max(baselineLocation + 1.5 * baselineScale, ...
    0.55 * activityThreshold);
while sampleStart > 2 && activity(sampleStart - 1) >= lowerThreshold
    sampleStart = sampleStart - 1;
end
while sampleEnd < sampleCount && activity(sampleEnd + 1) >= lowerThreshold
    sampleEnd = sampleEnd + 1;
end
startFrame = max(1, sampledFrameIndices(sampleStart) - ceil(frameStep));
endFrame = min(sampledFrameIndices(end), ...
    sampledFrameIndices(sampleEnd) + ceil(frameStep));
end

function variation = temporalPercentileRange(cube, lowPercent, highPercent)
sortedCube = sort(cube, 3);
frameCount = size(sortedCube, 3);
lowIndex = max(1, min(frameCount, round( ...
    1 + (frameCount - 1) * lowPercent / 100)));
highIndex = max(1, min(frameCount, round( ...
    1 + (frameCount - 1) * highPercent / 100)));
variation = sortedCube(:, :, highIndex) - sortedCube(:, :, lowIndex);
end

function mask = binaryCloseLocal(mask, radius)
kernel = ones(2 * radius + 1);
dilated = conv2(double(mask), kernel, 'same') > 0;
mask = conv2(double(dilated), kernel, 'same') == numel(kernel);
end

function components = connectedComponentsLocal(mask)
mask = logical(mask);
[height, width] = size(mask);
visited = false(height, width);
components = cell(0, 1);
[seedRows, seedColumns] = find(mask);
maximumQueueLength = nnz(mask);
for seedIndex = 1:numel(seedRows)
    startRow = seedRows(seedIndex);
    startColumn = seedColumns(seedIndex);
    if visited(startRow, startColumn)
        continue;
    end
    queueRows = zeros(maximumQueueLength, 1, 'uint32');
    queueColumns = zeros(maximumQueueLength, 1, 'uint32');
    componentIndices = zeros(maximumQueueLength, 1);
    head = 1;
    tail = 1;
    componentCount = 0;
    queueRows(1) = startRow;
    queueColumns(1) = startColumn;
    visited(startRow, startColumn) = true;
    while head <= tail
        row = double(queueRows(head));
        column = double(queueColumns(head));
        head = head + 1;
        componentCount = componentCount + 1;
        componentIndices(componentCount) = sub2ind([height width], row, column);
        for rowOffset = -1:1
            for columnOffset = -1:1
                if rowOffset == 0 && columnOffset == 0
                    continue;
                end
                neighborRow = row + rowOffset;
                neighborColumn = column + columnOffset;
                if neighborRow >= 1 && neighborRow <= height && ...
                        neighborColumn >= 1 && neighborColumn <= width && ...
                        mask(neighborRow, neighborColumn) && ...
                        ~visited(neighborRow, neighborColumn)
                    tail = tail + 1;
                    queueRows(tail) = neighborRow;
                    queueColumns(tail) = neighborColumn;
                    visited(neighborRow, neighborColumn) = true;
                end
            end
        end
    end
    components{end+1, 1} = componentIndices(1:componentCount); %#ok<AGROW>
end
end

function recurrence = periodicRecurrenceForMask( ...
    frameCube, componentIndices, activitySamples, sampledPeriodFrames)

lag = max(1, round(sampledPeriodFrames));
segment = frameCube(:, :, activitySamples);
if size(segment, 3) <= lag + 3
    recurrence = NaN;
    return;
end
pixels = reshape(segment, [], size(segment, 3))';
pixels = double(pixels(:, componentIndices));
pairCount = size(pixels, 1) - lag;
pairCorrelation = nan(pairCount, 1);
for i = 1:pairCount
    pairCorrelation(i) = correlationLocal(pixels(i, :)', pixels(i + lag, :)');
end
recurrence = median(pairCorrelation, 'omitnan');
if ~isfinite(recurrence)
    recurrence = 0;
end
end

function halfStep = samplingHalfStep(sampleIndices)
if numel(sampleIndices) < 2
    halfStep = 0;
else
    halfStep = ceil(max(diff(double(sampleIndices))) / 2);
end
end

function expanded = expandMapToImage(map, imageSize)
if isempty(map)
    expanded = zeros(imageSize(1:2));
    return;
end
rowMap = round(linspace(1, size(map, 1), imageSize(1)));
columnMap = round(linspace(1, size(map, 2), imageSize(2)));
expanded = double(map(rowMap, columnMap));
end

function choice = confirmAutomaticCircleRoi( ...
    referenceImage, variationDisplay, roiRect, diagnostics)

fig = figure('Color', 'w', 'Name', 'Confirm CircleScan automatic ROI', ...
    'NumberTitle', 'off');
cleanup = onCleanup(@() closeFigureIfOpen(fig));
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
imagesc(referenceImage); axis image; colormap gray; colorbar;
hold on;
rectangle('Position', roiRect, 'EdgeColor', 'r', 'LineWidth', 2);
title('Mean image and proposed fixed ROI');
nexttile;
imagesc(variationDisplay); axis image; colorbar;
hold on;
rectangle('Position', roiRect, 'EdgeColor', 'r', 'LineWidth', 2);
title('Temporal variation map and proposed ROI');
drawnow;

answer = questdlg(sprintf([ ...
    'The red rectangle must contain the complete moving-light path.\n' ...
    'Coarse activity: frames %d to %d. Auto ROI confidence: %.3f.\n\n' ...
    'Accept it, draw a manual ROI, or cancel without writing results?'], ...
    diagnostics.CoarseStartFrame, diagnostics.CoarseEndFrame, ...
    diagnostics.Confidence), ...
    'Confirm CircleScan automatic ROI', ...
    'Accept ROI', 'Draw manually', 'Cancel', 'Accept ROI');
if strcmp(answer, 'Accept ROI')
    choice = "ACCEPT";
elseif strcmp(answer, 'Draw manually')
    choice = "MANUAL";
else
    choice = "CANCEL";
end
clear cleanup;
end

function writeAutoRoiPreview(outputFolder, referenceImage, roiRect, ...
    diagnostics, opts)

fig = figure('Color', 'w', 'Visible', opts.FigureVisible, ...
    'Name', 'CircleScan automatic ROI diagnostic');
cleanup = onCleanup(@() closeFigureIfOpen(fig));
variationDisplay = expandMapToImage( ...
    diagnostics.VariationMap, size(referenceImage));
tiledlayout(1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
nexttile;
imagesc(referenceImage); axis image; colormap gray; colorbar;
hold on;
rectangle('Position', roiRect, 'EdgeColor', 'r', 'LineWidth', 2);
title(sprintf('Mean image | ROI mode: %s', diagnostics.Status), ...
    'Interpreter', 'none');
nexttile;
imagesc(variationDisplay); axis image; colorbar;
hold on;
rectangle('Position', roiRect, 'EdgeColor', 'r', 'LineWidth', 2);
title(sprintf('P95-P5 variation | confidence %.3f', ...
    diagnostics.Confidence));
exportgraphics(fig, fullfile(outputFolder, ...
    'circle_roi_variation_preview.png'), 'Resolution', 180);
clear cleanup;
end

function closeFigureIfOpen(fig)
if ishghandle(fig)
    close(fig);
end
end

function [rawMean, correctedMean, correctedP99, spatialCv, ...
    saturationPercent, differenceEnergy, adjacentCorrelation, ...
    textureMatrix, imageNames] = extractFrameFeatures( ...
    imageFolder, files, roiRect, darkImage, maxDigital, maxTexturePixels)

frameCount = numel(files);
rawMean = nan(frameCount, 1);
correctedMean = nan(frameCount, 1);
correctedP99 = nan(frameCount, 1);
spatialCv = nan(frameCount, 1);
saturationPercent = nan(frameCount, 1);
differenceEnergy = nan(frameCount, 1);
adjacentCorrelation = nan(frameCount, 1);
imageNames = strings(frameCount, 1);

firstImage = readGrayDouble(fullfile(imageFolder, files(1).name));
firstRoi = cropByRect(firstImage, roiRect);
sampleCount = min(numel(firstRoi), round(maxTexturePixels));
textureSampleIndex = unique(round(linspace(1, numel(firstRoi), sampleCount)));
textureMatrix = zeros(frameCount, numel(textureSampleIndex), 'single');
darkRoi = cropByRect(darkImage, roiRect);
previousCorrected = [];
satThreshold = 0.98 * maxDigital;

for i = 1:frameCount
    I = readGrayDouble(fullfile(imageFolder, files(i).name));
    assertSameSize(I, firstImage, files(i).name);
    rawRoi = cropByRect(I, roiRect);
    correctedRoi = rawRoi - darkRoi;
    correctedRoi(correctedRoi < 0) = 0;

    rawValues = rawRoi(:);
    correctedValues = correctedRoi(:);
    rawMean(i) = mean(rawValues);
    correctedMean(i) = mean(correctedValues);
    correctedP99(i) = percentileLocal(correctedValues, 99.0);
    spatialCv(i) = safeCvPercent(correctedValues);
    saturationPercent(i) = 100 * mean(rawValues >= satThreshold);
    imageNames(i) = string(files(i).name);

    if i > 1
        delta = correctedValues - previousCorrected;
        differenceEnergy(i) = sqrt(mean(delta .^ 2));
        adjacentCorrelation(i) = correlationLocal( ...
            previousCorrected, correctedValues);
    end
    previousCorrected = correctedValues;

    texture = single(correctedValues(textureSampleIndex));
    texture = texture - mean(texture);
    textureNorm = sqrt(sum(texture .^ 2));
    if textureNorm > eps('single')
        texture = texture / textureNorm;
    else
        texture(:) = 0;
    end
    textureMatrix(i, :) = texture';
end
end

function z = positiveRobustZ(values, baselineIndex, maximumZ)
[location, scale] = robustLocationScale(values(baselineIndex));
filled = values;
filled(~isfinite(filled)) = location;
z = (filled - location) / scale;
z = max(0, min(maximumZ, z));
end

function [location, scale] = robustLocationScale(values)
values = values(isfinite(values));
if isempty(values)
    location = 0;
    scale = 1;
    return;
end
location = median(values);
scale = 1.4826 * median(abs(values - location));
minimumScale = max(1e-9, 1e-6 * max(1, abs(location)));
if ~isfinite(scale) || scale < minimumScale
    scale = std(values);
end
if ~isfinite(scale) || scale < minimumScale
    scale = minimumScale;
end
end

function mask = fillShortGaps(mask, maximumGap)
mask = logical(mask(:));
[gapStarts, gapEnds] = logicalRuns(~mask);
for i = 1:numel(gapStarts)
    gapLength = gapEnds(i) - gapStarts(i) + 1;
    isInternal = gapStarts(i) > 1 && gapEnds(i) < numel(mask);
    if isInternal && gapLength <= maximumGap
        mask(gapStarts(i):gapEnds(i)) = true;
    end
end
end

function mask = removeShortRuns(mask, minimumLength)
mask = logical(mask(:));
[runStarts, runEnds] = logicalRuns(mask);
for i = 1:numel(runStarts)
    if runEnds(i) - runStarts(i) + 1 < minimumLength
        mask(runStarts(i):runEnds(i)) = false;
    end
end
end

function [runStarts, runEnds] = logicalRuns(mask)
mask = logical(mask(:));
changes = diff([false; mask; false]);
runStarts = find(changes == 1);
runEnds = find(changes == -1) - 1;
end

function selectedRun = chooseActivityRun(runStarts, runEnds, activity, ...
    expectedPeriodFrames, requestedCircleCount)
scores = zeros(numel(runStarts), 1);
for i = 1:numel(runStarts)
    range = runStarts(i):runEnds(i);
    duration = numel(range);
    strength = mean(activity(range), 'omitnan');
    if isfinite(requestedCircleCount)
        expectedDuration = requestedCircleCount * expectedPeriodFrames;
        durationFit = exp(-abs(duration - expectedDuration) / ...
            max(expectedDuration, 1));
    else
        durationFit = min(1, duration / max(3 * expectedPeriodFrames, 1));
    end
    scores(i) = strength * sqrt(duration) * (0.5 + 0.5 * durationFit);
end
[~, selectedRun] = max(scores);
end

function [roiRecurrence, featureAutocorrelation] = calculateLagCurves( ...
    textureMatrix, signals, firstFrame, lastFrame, lags)
texture = double(textureMatrix(firstFrame:lastFrame, :));
signals = preparePeriodicSignals(signals(firstFrame:lastFrame, :));
roiRecurrence = nan(numel(lags), 1);
featureAutocorrelation = nan(numel(lags), 1);

for i = 1:numel(lags)
    lag = lags(i);
    firstTexture = texture(1:end-lag, :);
    secondTexture = texture(1+lag:end, :);
    validRows = any(firstTexture ~= 0, 2) & any(secondTexture ~= 0, 2);
    if any(validRows)
        pairSimilarity = sum( ...
            firstTexture(validRows, :) .* secondTexture(validRows, :), 2);
        roiRecurrence(i) = mean(pairSimilarity, 'omitnan');
    end

    correlations = nan(size(signals, 2), 1);
    for j = 1:size(signals, 2)
        correlations(j) = correlationLocal( ...
            signals(1:end-lag, j), signals(1+lag:end, j));
    end
    featureAutocorrelation(i) = mean(correlations, 'omitnan');
end
end

function signals = preparePeriodicSignals(signals)
time = (1:size(signals, 1))';
for i = 1:size(signals, 2)
    x = signals(:, i);
    valid = isfinite(x);
    if nnz(valid) < 3
        signals(:, i) = 0;
        continue;
    end
    if any(~valid)
        x(~valid) = median(x(valid));
    end
    coefficients = polyfit(time, x, 1);
    x = x - polyval(coefficients, time);
    xStd = std(x);
    if ~isfinite(xStd) || xStd <= eps
        x(:) = 0;
    else
        x = x / xStd;
    end
    signals(:, i) = x;
end
end

function [evidence, strength] = normalizePeriodEvidence(values, scaleForStrong)
values = values(:);
valid = isfinite(values);
evidence = zeros(size(values));
if nnz(valid) < 3
    strength = 0;
    return;
end
validValues = values(valid);
minimumValue = min(validValues);
maximumValue = max(validValues);
rangeValue = maximumValue - minimumValue;
if rangeValue > eps
    evidence(valid) = (validValues - minimumValue) / rangeValue;
end
prominence = maximumValue - median(validValues);
strength = clamp01(prominence / scaleForStrong);
end

function refined = refinePeakLocation(lags, evidence, peakIndex)
refined = double(lags(peakIndex));
if peakIndex <= 1 || peakIndex >= numel(evidence)
    return;
end
y1 = evidence(peakIndex - 1);
y2 = evidence(peakIndex);
y3 = evidence(peakIndex + 1);
denominator = y1 - 2 * y2 + y3;
if isfinite(denominator) && abs(denominator) > eps
    offset = 0.5 * (y1 - y3) / denominator;
    offset = max(-1, min(1, offset));
    refined = refined + offset;
end
end

function uncertainty = estimatePeakUncertainty(lags, evidence, peakIndex)
validEvidence = evidence(isfinite(evidence));
if isempty(validEvidence)
    uncertainty = NaN;
    return;
end
baseline = median(validEvidence);
peak = evidence(peakIndex);
threshold = baseline + 0.80 * (peak - baseline);
left = peakIndex;
right = peakIndex;
while left > 1 && evidence(left - 1) >= threshold
    left = left - 1;
end
while right < numel(evidence) && evidence(right + 1) >= threshold
    right = right + 1;
end
uncertainty = max(0.5, (lags(right) - lags(left)) / 2);
end

function [periodFrames, strength] = estimateFftPeriod( ...
    signals, minimumPeriod, maximumPeriod)
signals = preparePeriodicSignals(signals);
sampleCount = size(signals, 1);
if sampleCount < maximumPeriod + 4
    periodFrames = NaN;
    strength = 0;
    return;
end

window = 0.5 - 0.5 * cos(2 * pi * (0:sampleCount-1)' / ...
    max(sampleCount - 1, 1));
nfft = 2 ^ nextpow2(max(256, sampleCount * 8));
combinedPower = zeros(nfft, 1);
validSignalCount = 0;
for i = 1:size(signals, 2)
    x = signals(:, i);
    if std(x) <= eps
        continue;
    end
    spectrum = abs(fft(x .* window, nfft)) .^ 2;
    totalPower = sum(spectrum(2:floor(nfft / 2)));
    if totalPower > 0
        combinedPower = combinedPower + spectrum / totalPower;
        validSignalCount = validSignalCount + 1;
    end
end
if validSignalCount == 0
    periodFrames = NaN;
    strength = 0;
    return;
end
combinedPower = combinedPower / validSignalCount;
frequency = (0:nfft-1)' / nfft;
validBand = frequency >= 1 / maximumPeriod & ...
    frequency <= 1 / minimumPeriod;
indices = find(validBand);
if isempty(indices)
    periodFrames = NaN;
    strength = 0;
    return;
end
[peakPower, localIndex] = max(combinedPower(indices));
peakIndex = indices(localIndex);
periodFrames = 1 / frequency(peakIndex);
bandMedian = median(combinedPower(indices));
powerRatio = peakPower / max(bandMedian, eps);
strength = clamp01((powerRatio - 1) / 5);
end

function [circleTable, selectedStart, selectedEnd, circleCount, ...
    boundaryUncertainty] = buildConservativeCircles( ...
    candidateStart, candidateEnd, periodFrames, periodUncertaintyFrames, ...
    smoothWindow, requestedCircleCount)

circleTable = emptyCircleTable();
selectedStart = NaN;
selectedEnd = NaN;
circleCount = 0;
boundaryUncertainty = NaN;
if ~isfinite(candidateStart) || ~isfinite(periodFrames) || periodFrames <= 1
    return;
end
if ~isfinite(periodUncertaintyFrames)
    periodUncertaintyFrames = 1;
end

boundaryUncertainty = max(1, ceil( ...
    periodUncertaintyFrames + floor(smoothWindow / 2)));
coreStart = candidateStart + boundaryUncertainty;
coreEnd = candidateEnd - boundaryUncertainty;
availableFrames = coreEnd - coreStart + 1;
if availableFrames < periodFrames
    return;
end

circleCount = floor(availableFrames / periodFrames);
if isfinite(requestedCircleCount)
    circleCount = min(circleCount, floor(requestedCircleCount));
end
if circleCount < 1
    return;
end

circleIndex = (1:circleCount)';
startFrame = nan(circleCount, 1);
endFrame = nan(circleCount, 1);
frameNumber = nan(circleCount, 1);
startNominalOffsetFrames = nan(circleCount, 1);
endNominalOffsetFrames = nan(circleCount, 1);
for i = 1:circleCount
    startFrame(i) = round(coreStart + (i - 1) * periodFrames);
    endFrame(i) = round(coreStart + i * periodFrames - 1);
    endFrame(i) = min(endFrame(i), coreEnd);
    frameNumber(i) = endFrame(i) - startFrame(i) + 1;
    startNominalOffsetFrames(i) = (i - 1) * periodFrames;
    endNominalOffsetFrames(i) = i * periodFrames;
end

periodColumn = repmat(periodFrames, circleCount, 1);
uncertaintyColumn = repmat(boundaryUncertainty, circleCount, 1);
circleTable = table(circleIndex, startFrame, endFrame, frameNumber, ...
    startNominalOffsetFrames, endNominalOffsetFrames, periodColumn, ...
    uncertaintyColumn, 'VariableNames', {'CircleIndex','StartFrame', ...
    'EndFrame','FrameCount','StartOffsetFrames','EndOffsetFrames', ...
    'EstimatedPeriodFrames','BoundaryUncertaintyFrames'});
selectedStart = startFrame(1);
selectedEnd = endFrame(end);
end

function circleTable = emptyCircleTable()
circleTable = table(zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    zeros(0,1), zeros(0,1), zeros(0,1), zeros(0,1), ...
    'VariableNames', {'CircleIndex','StartFrame','EndFrame','FrameCount', ...
    'StartOffsetFrames','EndOffsetFrames','EstimatedPeriodFrames', ...
    'BoundaryUncertaintyFrames'});
end

function [confidence, status, reason] = classifyDetection( ...
    candidateStart, candidateEnd, activity, baselineIndex, ...
    activityThreshold, expectedPeriod, estimatedPeriod, fftPeriod, ...
    periodicityStrength, spectralStrength, completeCircleCount, ...
    requestedCircleCount, saturationPercent, correctedMean, opts)

reasons = strings(0, 1);
if ~isfinite(candidateStart)
    confidence = 0;
    status = "NEEDS_MANUAL_REVIEW";
    reason = "No sustained activity interval passed the pilot threshold.";
    return;
end

candidateRange = candidateStart:candidateEnd;
baselineLevel = median(activity(baselineIndex), 'omitnan');
activeLevel = median(activity(candidateRange), 'omitnan');
activityStrength = clamp01((activeLevel - baselineLevel) / ...
    max(2 * activityThreshold, eps));

if isfinite(estimatedPeriod)
    theoryStrength = clamp01(1 - abs(estimatedPeriod - expectedPeriod) / ...
        (opts.PeriodToleranceFraction * expectedPeriod));
else
    theoryStrength = 0;
    reasons(end+1) = "No repeated period could be estimated.";
end

if isfinite(estimatedPeriod) && isfinite(fftPeriod)
    agreementStrength = clamp01(1 - abs(estimatedPeriod - fftPeriod) / ...
        (opts.PeriodToleranceFraction * expectedPeriod));
else
    agreementStrength = 0;
    reasons(end+1) = "Time-domain and FFT period estimates are incomplete.";
end

candidateLength = candidateEnd - candidateStart + 1;
if isfinite(estimatedPeriod)
    repeatStrength = clamp01(candidateLength / (3 * estimatedPeriod));
else
    repeatStrength = 0;
end
if isfinite(requestedCircleCount)
    expectedDuration = requestedCircleCount * expectedPeriod;
    durationStrength = clamp01(1 - abs(candidateLength - expectedDuration) / ...
        max(expectedDuration, 1));
    repeatStrength = 0.5 * repeatStrength + 0.5 * durationStrength;
end

periodEvidenceStrength = 0.65 * periodicityStrength + ...
    0.35 * spectralStrength;
confidence = 0.22 * activityStrength + 0.22 * theoryStrength + ...
    0.20 * agreementStrength + 0.22 * periodEvidenceStrength + ...
    0.14 * repeatStrength;
confidence = clamp01(confidence);

if completeCircleCount < opts.MinimumCompleteCircles
    reasons(end+1) = sprintf( ...
        "Only %d conservative full circles were retained; at least %d are required.", ...
        completeCircleCount, opts.MinimumCompleteCircles);
end
if max(saturationPercent, [], 'omitnan') >= opts.MaximumSaturationPercent
    reasons(end+1) = "At least one ROI frame reached the saturation warning level.";
end
if mean(correctedMean(candidateRange), 'omitnan') <= opts.MinimumCorrectedMean
    reasons(end+1) = "The candidate interval is too dark for reliable texture evidence.";
end
if isfinite(estimatedPeriod) && theoryStrength < 0.5
    reasons(end+1) = "The estimated period is not close enough to the theoretical period.";
end
if isfinite(estimatedPeriod) && isfinite(fftPeriod) && agreementStrength < 0.5
    reasons(end+1) = "Autocorrelation/recurrence and FFT estimates do not agree.";
end
if confidence < opts.ConfidenceAcceptThreshold
    reasons(end+1) = sprintf( ...
        "Confidence %.3f is below the %.3f acceptance threshold.", ...
        confidence, opts.ConfidenceAcceptThreshold);
end

if isempty(reasons)
    status = "AUTO_ACCEPT";
    reason = "Sustained activity and repeated-period evidence passed all pilot gates.";
else
    status = "NEEDS_MANUAL_REVIEW";
    reason = strjoin(unique(reasons, 'stable'), " ");
end
end

function writeDiagnosticPlot(outputFolder, featureTable, summaryTable, ...
    circleTable, lags, roiRecurrence, featureAutocorrelation, ...
    periodEvidence, activityThreshold, opts)

fig = figure('Color', 'w', 'Visible', opts.FigureVisible, ...
    'Name', 'CircleScan interval detection');
tiledlayout(3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
frame = featureTable.FrameIndex;

ax1 = nexttile;
set(ax1, 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
hMean = plot(frame, featureTable.MeanDarkCorrected, 'LineWidth', 1.0);
hold on;
hP99 = plot(frame, featureTable.P99DarkCorrected, 'LineWidth', 1.0);
grid on;
xlabel('Frame index');
ylabel('Gray value');
legend([hMean hP99], {'Mean dark-corrected','P99 dark-corrected'}, ...
    'Location', 'best', 'AutoUpdate', 'off', 'Color', 'w', ...
    'TextColor', 'k', 'EdgeColor', 'k');
title('Intensity features');
addIntervalMarkers(summaryTable, circleTable);

ax2 = nexttile;
set(ax2, 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
plot(frame, featureTable.SmoothedActivityScore, 'LineWidth', 1.2);
hold on;
yline(activityThreshold, '--r', 'Activity threshold');
grid on;
xlabel('Frame index');
ylabel('Activity score');
title(sprintf('%s | confidence %.3f', ...
    summaryTable.Status(1), summaryTable.Confidence(1)), ...
    'Interpreter', 'none');
addIntervalMarkers(summaryTable, circleTable);

ax3 = nexttile;
set(ax3, 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
if isempty(lags)
    axis off;
    text(0.02, 0.55, 'Insufficient repeated data for period estimation.', ...
        'Units', 'normalized', 'Color', 'k');
else
    hRecurrence = plot(lags, roiRecurrence, 'LineWidth', 1.0);
    hold on;
    hAutocorrelation = plot(lags, featureAutocorrelation, 'LineWidth', 1.0);
    hCombined = plot(lags, periodEvidence, 'k-', 'LineWidth', 1.5);
    xline(summaryTable.ExpectedPeriodFrames(1), '--', 'Expected');
    if isfinite(summaryTable.EstimatedPeriodFrames(1))
        xline(summaryTable.EstimatedPeriodFrames(1), '-', 'Estimated');
    end
    grid on;
    xlabel('Lag (frames)');
    ylabel('Period evidence');
    legend([hRecurrence hAutocorrelation hCombined], ...
        {'ROI recurrence','Feature autocorrelation','Combined evidence'}, ...
        'Location', 'best', 'AutoUpdate', 'off', 'Color', 'w', ...
        'TextColor', 'k', 'EdgeColor', 'k');
    title(sprintf('Expected %.2f frames; estimated %.2f frames', ...
        summaryTable.ExpectedPeriodFrames(1), ...
        summaryTable.EstimatedPeriodFrames(1)));
end

exportgraphics(fig, fullfile(outputFolder, ...
    'circle_detection_diagnostic.png'), 'Resolution', 180);
close(fig);
end

function addIntervalMarkers(summaryTable, circleTable)
xline(1, ':', 'S / capture start');
xline(summaryTable.FrameCount(1), ':', 'H / capture stop');
if isfinite(summaryTable.CandidateStartFrame(1))
    xline(summaryTable.CandidateStartFrame(1), '--', 'Activity start');
    xline(summaryTable.CandidateEndFrame(1), '--', 'Activity end');
end
for i = 1:height(circleTable)
    xline(circleTable.StartFrame(i), ':', sprintf('C%d', i));
end
end

function files = listImageFiles(folder)
extensions = {'*.bmp','*.tif','*.tiff','*.png','*.jpg','*.jpeg'};
files = [];
for i = 1:numel(extensions)
    files = [files; dir(fullfile(folder, extensions{i}))]; %#ok<AGROW>
end
if isempty(files)
    return;
end
numbers = inf(numel(files), 1);
for i = 1:numel(files)
    tokens = regexp(files(i).name, '\d+', 'match');
    if ~isempty(tokens)
        numbers(i) = str2double(tokens{end});
    end
end
[~, order] = sortrows([numbers, (1:numel(files))']);
files = files(order);
end

function [meanImage, maxDigital] = buildMeanImage(folder, files)
firstRaw = imread(fullfile(folder, files(1).name));
if isinteger(firstRaw)
    maxDigital = double(intmax(class(firstRaw)));
else
    maxDigital = 1;
end
first = toGrayDouble(firstRaw);
meanImage = zeros(size(first));
for i = 1:numel(files)
    I = readGrayDouble(fullfile(folder, files(i).name));
    assertSameSize(I, first, files(i).name);
    meanImage = meanImage + I;
end
meanImage = meanImage / numel(files);
end

function I = readGrayDouble(path)
I = toGrayDouble(imread(path));
end

function I = toGrayDouble(raw)
if ndims(raw) == 3
    I = 0.2989 * double(raw(:,:,1)) + 0.5870 * double(raw(:,:,2)) + ...
        0.1140 * double(raw(:,:,3));
else
    I = double(raw);
end
end

function roiRect = selectRectangle(I)
fig = figure('Color', 'w', 'Name', 'Select fixed ROI');
imagesc(I); axis image; colormap gray; colorbar;
title({'Draw one fixed ROI containing the complete CircleScan path', ...
    'Click upper-left and lower-right corners'});
[x, y] = ginput(2);
close(fig);
if numel(x) ~= 2 || numel(y) ~= 2
    error('detect_circle_scan_interval:ManualRoiCancelled', ...
        'Manual ROI selection requires exactly two points.');
end
roiRect = [min(x), min(y), abs(diff(x)), abs(diff(y))];
end

function rect = validateRectangle(rect, imageSize)
if ~isnumeric(rect) || numel(rect) ~= 4 || any(~isfinite(rect))
    error('roiRect must be [x y width height].');
end
x1 = max(1, floor(rect(1)));
y1 = max(1, floor(rect(2)));
x2 = min(imageSize(2), ceil(rect(1) + rect(3)));
y2 = min(imageSize(1), ceil(rect(2) + rect(4)));
if x2 <= x1 || y2 <= y1
    error('The selected ROI is empty or outside the image.');
end
rect = [x1, y1, x2 - x1, y2 - y1];
end

function roi = cropByRect(I, rect)
x1 = rect(1); y1 = rect(2);
x2 = x1 + rect(3); y2 = y1 + rect(4);
roi = I(y1:y2, x1:x2);
end

function p = percentileLocal(values, percent)
values = sort(values(isfinite(values)));
if isempty(values)
    p = NaN;
    return;
end
position = 1 + (numel(values) - 1) * percent / 100;
lowerIndex = floor(position);
upperIndex = ceil(position);
if lowerIndex == upperIndex
    p = values(lowerIndex);
else
    weight = position - lowerIndex;
    p = values(lowerIndex) * (1 - weight) + values(upperIndex) * weight;
end
end

function cv = safeCvPercent(values)
averageValue = mean(values, 'omitnan');
if ~isfinite(averageValue) || averageValue == 0
    cv = NaN;
else
    cv = 100 * std(values, 0, 'omitnan') / averageValue;
end
end

function r = correlationLocal(a, b)
valid = isfinite(a) & isfinite(b);
a = a(valid);
b = b(valid);
if numel(a) < 3 || std(a) == 0 || std(b) == 0
    r = NaN;
    return;
end
C = corrcoef(a, b);
r = C(1, 2);
end

function value = clamp01(value)
value = max(0, min(1, value));
end

function assertSameSize(I, referenceImage, name)
if ~isequal(size(I), size(referenceImage))
    error('Image size mismatch: %s', name);
end
end
