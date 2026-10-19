function config = create_stage3_config_v2(experimentRoot, overrides)
%CREATE_STAGE3_CONFIG_V2 Create one explicit configuration for Stage 3 V2.
%
%   config = create_stage3_config_v2('C:\data\next_stage3');
%   config = create_stage3_config_v2(root, struct('ThicknessUm',[40 80]));
%
% This function does not modify any legacy 1002/1003/1005 result.

if nargin < 1 || strlength(string(experimentRoot)) == 0
    selected = uigetdir(pwd, 'Select the new Stage 3 experiment root');
    if isequal(selected, 0)
        error('No experiment root was selected.');
    end
    experimentRoot = selected;
end
if nargin < 2 || isempty(overrides)
    overrides = struct;
end
if ~isstruct(overrides) || ~isscalar(overrides)
    error('overrides must be a scalar struct.');
end

config = struct;
config.ConfigVersion = "STAGE3_V2_1.0";
config.CreatedAt = string(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss'));
config.ExperimentRoot = string(experimentRoot);
config.AnalysisRoot = string(fullfile(experimentRoot, '00_STAGE3_V2_ANALYSIS'));
config.CodeRoot = string(fileparts(mfilename('fullpath')));
config.LegacyCodeRoot = string(fileparts(fileparts(mfilename('fullpath'))));

config.ThicknessUm = [40 80];
config.RepeatIDs = ["R01" "R02" "R03" "R04" "R05"];
config.TechnicalIDs = ["T01" "T02" "T03"];
config.ParameterID = "r1p5_v5";
config.RadiusMm = 1.5;
config.VelocityMmS = 5;
config.CenterXmm = 5;
config.CenterYmm = 5;
config.CameraHz = 80;
config.ExposureUs = 4000;
config.RequestedCycleCount = 5;

config.BaseThicknessUm = 40;
config.BasePlatformHeightMm = 0.510;
config.DarkFolderBeginning = "";
config.DarkFolderEnd = "";
config.NakedBeginningFolder = "";
config.NakedEndFolder = "";
config.ReferenceExposureUs = NaN;
config.LogFolder = "";
config.LogMapFile = "";
config.AcquisitionOrderFile = "";
config.RoiFile = "";
config.IntervalRoiSource = [];

config.PrimaryFeature = "Top1MeanDN";
config.SecondaryFeatures = ["P99DN" "RoiMeanDN"];
config.ExploratoryFeatures = ["P90DN" "P95DN" ...
    "Top10MeanDN" "Top5MeanDN" "MaximumDN"];

config.MaximumSaturationPercent = 0.10;
config.SaturationFractionOfDigitalMax = 0.98;
config.MaximumImagePeriodErrorPercent = 5.0;
config.MinimumCompleteCycleCount = 5;
config.MinimumTop1Snr = 5.0;
config.MaximumTechnicalCvPercent = 5.0;
config.MinimumDirectionAgreementCount = 4;
config.MinimumSeparationS = 2.0;
config.MaximumCommandRadiusErrorPercent = 5.0;
config.MaximumCommandRadiusCvPercent = 5.0;
config.RoiMarginPixels = 8;
config.MaximumRoiCandidateFramesPerRun = 40;
config.MaximumRoiAreaFraction = 0.35;

config.ConfirmAutoRoi = true;
config.MakeFigures = true;
config.RerunExisting = false;
config.AllowIncompleteManifest = false;
config.RequireMotionLogForFormalValidation = true;
config.RequireEndDarkForFormalValidation = false;
config.RequireNakedReferenceForFormalValidation = false;

overrideNames = fieldnames(overrides);
knownNames = fieldnames(config);
for fieldIndex = 1:numel(overrideNames)
    fieldName = overrideNames{fieldIndex};
    if ~ismember(fieldName, knownNames)
        error('Unknown Stage 3 V2 config field: %s', fieldName);
    end
    config.(fieldName) = overrides.(fieldName);
end

validateConfigLocal(config);
config.ExpectedPeriodSeconds = 2 * pi * config.RadiusMm / config.VelocityMmS;
config.ExpectedPeriodFrames = config.CameraHz * config.ExpectedPeriodSeconds;
config.ExpectedTotalCycleFrames = ...
    config.RequestedCycleCount * config.ExpectedPeriodFrames;

if ~isfolder(config.AnalysisRoot)
    mkdir(config.AnalysisRoot);
end
configFolder = fullfile(config.AnalysisRoot, 'config');
if ~isfolder(configFolder)
    mkdir(configFolder);
end
save(fullfile(configFolder, 'stage3_v2_config.mat'), 'config');

fprintf('\n=== Stage 3 V2 config created ===\n');
fprintf('Experiment root: %s\n', config.ExperimentRoot);
fprintf('Thicknesses: %s um\n', strjoin(string(config.ThicknessUm), ', '));
fprintf('Independent preparations: %d\n', numel(config.RepeatIDs));
fprintf('Technical captures per bed: %d\n', numel(config.TechnicalIDs));
fprintf('Expected frames for %d cycles: %.2f\n', ...
    config.RequestedCycleCount, config.ExpectedTotalCycleFrames);
fprintf('Config file: %s\n', ...
    fullfile(configFolder, 'stage3_v2_config.mat'));
end

function validateConfigLocal(config)
positiveFields = {'RadiusMm','VelocityMmS','CameraHz','ExposureUs', ...
    'RequestedCycleCount','BasePlatformHeightMm', ...
    'MaximumSaturationPercent','SaturationFractionOfDigitalMax', ...
    'MaximumImagePeriodErrorPercent','MinimumCompleteCycleCount', ...
    'MinimumTop1Snr','MaximumTechnicalCvPercent', ...
    'MinimumDirectionAgreementCount','MinimumSeparationS', ...
    'RoiMarginPixels','MaximumRoiCandidateFramesPerRun'};
for fieldIndex = 1:numel(positiveFields)
    value = config.(positiveFields{fieldIndex});
    if ~(isnumeric(value) && isscalar(value) && isfinite(value) && value > 0)
        error('config.%s must be a positive finite scalar.', positiveFields{fieldIndex});
    end
end
if isempty(config.ThicknessUm) || any(~isfinite(config.ThicknessUm)) || ...
        any(config.ThicknessUm <= 0) || numel(unique(config.ThicknessUm)) ~= numel(config.ThicknessUm)
    error('config.ThicknessUm must contain unique positive values.');
end
if isempty(config.RepeatIDs) || isempty(config.TechnicalIDs) || ...
        numel(unique(config.RepeatIDs)) ~= numel(config.RepeatIDs) || ...
        numel(unique(config.TechnicalIDs)) ~= numel(config.TechnicalIDs)
    error('RepeatIDs and TechnicalIDs must be nonempty and unique.');
end
if config.MinimumDirectionAgreementCount > numel(config.RepeatIDs)
    error('MinimumDirectionAgreementCount exceeds the number of RepeatIDs.');
end
if config.SaturationFractionOfDigitalMax >= 1 || ...
        config.MaximumRoiAreaFraction <= 0 || config.MaximumRoiAreaFraction >= 1
    error('Saturation/ROI fractions are outside their valid ranges.');
end
logicalFields = {'ConfirmAutoRoi','MakeFigures','RerunExisting', ...
    'AllowIncompleteManifest','RequireMotionLogForFormalValidation', ...
    'RequireEndDarkForFormalValidation', ...
    'RequireNakedReferenceForFormalValidation'};
for fieldIndex = 1:numel(logicalFields)
    value = config.(logicalFields{fieldIndex});
    if ~(isscalar(value) && (islogical(value) || ...
            (isnumeric(value) && isfinite(value) && ismember(value, [0 1]))))
        error('config.%s must be a scalar logical value.', logicalFields{fieldIndex});
    end
end
end
