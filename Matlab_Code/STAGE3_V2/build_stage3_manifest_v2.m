function manifest = build_stage3_manifest_v2(config)
%BUILD_STAGE3_MANIFEST_V2 Build a generic Stage 3 V2 dataset manifest.
%
% Expected image-folder examples:
%   root\R01\40um_T01
%   root\R01\40um\T01
%
% Optional AcquisitionOrderFile columns:
%   DatasetID, AcquisitionOrder, LogRunID, LogFile

requireConfigLocal(config);
root = char(config.ExperimentRoot);
if ~isfolder(root)
    error('Experiment root not found: %s', root);
end

orderMap = table();
if strlength(string(config.AcquisitionOrderFile)) > 0
    if ~isfile(config.AcquisitionOrderFile)
        error('AcquisitionOrderFile not found: %s', config.AcquisitionOrderFile);
    end
    orderMap = readtable(config.AcquisitionOrderFile, 'TextType', 'string');
    stage3v2.requireVariables(orderMap, ...
        ["DatasetID" "AcquisitionOrder"], 'AcquisitionOrderFile');
end

logMap = table();
if strlength(string(config.LogMapFile)) > 0
    if ~isfile(config.LogMapFile)
        error('LogMapFile not found: %s', config.LogMapFile);
    end
    logMap = readtable(config.LogMapFile, 'TextType', 'string');
    stage3v2.requireVariables(logMap, ["DatasetID" "LogFile"], 'LogMapFile');
end

rowCount = numel(config.RepeatIDs) * numel(config.ThicknessUm) * ...
    numel(config.TechnicalIDs);
rows = repmat(emptyRowLocal(), rowCount, 1);
problems = strings(0, 1);
rowIndex = 0;

for repeatIndex = 1:numel(config.RepeatIDs)
    repeatID = string(config.RepeatIDs(repeatIndex));
    for thicknessIndex = 1:numel(config.ThicknessUm)
        thickness = double(config.ThicknessUm(thicknessIndex));
        for technicalIndex = 1:numel(config.TechnicalIDs)
            technicalID = string(config.TechnicalIDs(technicalIndex));
            rowIndex = rowIndex + 1;
            datasetID = repeatID + "_" + string(thickness) + "um_" + technicalID;
            imageFolder = resolveImageFolderLocal(root, repeatID, ...
                thickness, technicalID);

            row = emptyRowLocal();
            row.K = rowIndex;
            row.DatasetID = datasetID;
            row.AcquisitionOrder = rowIndex;
            row.RepeatID = repeatID;
            row.ThicknessUm = thickness;
            row.TechnicalID = technicalID;
            row.ParameterID = string(config.ParameterID);
            row.RadiusMm = double(config.RadiusMm);
            row.VelocityMmS = double(config.VelocityMmS);
            row.CenterXmm = double(config.CenterXmm);
            row.CenterYmm = double(config.CenterYmm);
            row.PlatformHeightMm = double(config.BasePlatformHeightMm) - ...
                (thickness - double(config.BaseThicknessUm)) / 1000;
            row.CameraHz = double(config.CameraHz);
            row.ExposureUs = double(config.ExposureUs);
            row.RequestedCycleCount = double(config.RequestedCycleCount);
            row.ExpectedPeriodFrames = double(config.ExpectedPeriodFrames);
            row.ExpectedTotalCycleFrames = double(config.ExpectedTotalCycleFrames);
            row.ImageFolder = string(imageFolder);
            row.DarkFolder = string(config.DarkFolderBeginning);
            row.LogFile = "";
            row.LogRunID = NaN;
            row.IncludeInBrightnessAnalysis = true;

            if isfolder(imageFolder)
                files = stage3v2.listImages(imageFolder);
                row.ImageCount = numel(files);
                if isempty(files)
                    problems(end+1) = datasetID + ": no supported images"; %#ok<AGROW>
                else
                    row.FirstImageName = string(files(1).name);
                    row.LastImageName = string(files(end).name);
                end
            else
                row.ImageCount = 0;
                problems(end+1) = datasetID + ": image folder missing"; %#ok<AGROW>
            end

            if ~isempty(orderMap)
                match = orderMap(orderMap.DatasetID == datasetID, :);
                if height(match) ~= 1
                    problems(end+1) = datasetID + ...
                        ": AcquisitionOrderFile must contain exactly one row"; %#ok<AGROW>
                else
                    row.AcquisitionOrder = double(match.AcquisitionOrder(1));
                    if ismember('LogRunID', match.Properties.VariableNames)
                        row.LogRunID = double(match.LogRunID(1));
                    end
                    if ismember('LogFile', match.Properties.VariableNames)
                        row.LogFile = string(match.LogFile(1));
                    end
                end
            end
            if ~isempty(logMap)
                match = logMap(logMap.DatasetID == datasetID, :);
                if height(match) == 1
                    row.LogFile = string(match.LogFile(1));
                    if ismember('LogRunID', match.Properties.VariableNames)
                        row.LogRunID = double(match.LogRunID(1));
                    end
                elseif height(match) > 1
                    problems(end+1) = datasetID + ": duplicate LogMapFile rows"; %#ok<AGROW>
                end
            end
            if strlength(row.LogFile) > 0 && ~isfile(row.LogFile)
                problems(end+1) = datasetID + ": mapped LogFile missing"; %#ok<AGROW>
            end

            rows(rowIndex) = row;
        end
    end
end

manifest = struct2table(rows);
manifest = sortrows(manifest, {'AcquisitionOrder','K'});
if numel(unique(manifest.DatasetID)) ~= height(manifest)
    problems(end+1) = "DatasetID values are not unique"; %#ok<AGROW>
end
if numel(unique(manifest.AcquisitionOrder)) ~= height(manifest)
    problems(end+1) = "AcquisitionOrder values are not unique"; %#ok<AGROW>
end
if strlength(string(config.DarkFolderBeginning)) == 0 || ...
        ~isfolder(config.DarkFolderBeginning)
    problems(end+1) = "matching beginning dark-frame folder is missing"; %#ok<AGROW>
end

if ~isempty(problems) && ~logical(config.AllowIncompleteManifest)
    fprintf('\nManifest preflight problems:\n');
    fprintf(' - %s\n', problems);
    error(['Stage 3 V2 manifest was not written. Fix the listed paths or ' ...
        'set AllowIncompleteManifest=true for planning only.']);
end

configFolder = fullfile(config.AnalysisRoot, 'config');
if ~isfolder(configFolder)
    mkdir(configFolder);
end
manifestFile = fullfile(configFolder, 'stage3_v2_manifest.csv');
writetable(manifest, manifestFile);
save(fullfile(configFolder, 'stage3_v2_manifest.mat'), 'manifest');

fprintf('\n=== Stage 3 V2 manifest created ===\n');
fprintf('Datasets: %d\n', height(manifest));
fprintf('Independent preparations: %d\n', numel(config.RepeatIDs));
fprintf('Thicknesses: %s um\n', strjoin(string(config.ThicknessUm), ', '));
fprintf('Technical captures per bed: %d\n', numel(config.TechnicalIDs));
fprintf('Output: %s\n', manifestFile);
disp(manifest(:, {'K','DatasetID','AcquisitionOrder','RepeatID', ...
    'ThicknessUm','TechnicalID','ImageCount','PlatformHeightMm'}));
if ~isempty(problems)
    fprintf('\nPlanning-only manifest warnings:\n');
    fprintf(' - %s\n', problems);
end
end

function folder = resolveImageFolderLocal(root, repeatID, thickness, technicalID)
candidates = [ ...
    string(fullfile(root, repeatID, sprintf('%dum_%s', thickness, technicalID))), ...
    string(fullfile(root, repeatID, sprintf('%dum%s', thickness, technicalID))), ...
    string(fullfile(root, repeatID, sprintf('%dum', thickness), technicalID)), ...
    string(fullfile(root, repeatID, sprintf('%s_%dum_%s', repeatID, thickness, technicalID)))];
exists = arrayfun(@(path) isfolder(path), candidates);
if nnz(exists) > 1
    error('Multiple image folders match %s %dum %s.', ...
        repeatID, thickness, technicalID);
elseif nnz(exists) == 1
    folder = char(candidates(find(exists, 1)));
else
    folder = char(candidates(1));
end
end

function requireConfigLocal(config)
required = {'ExperimentRoot','AnalysisRoot','ThicknessUm','RepeatIDs', ...
    'TechnicalIDs','ParameterID','RadiusMm','VelocityMmS','CameraHz', ...
    'ExposureUs','RequestedCycleCount','ExpectedPeriodFrames', ...
    'ExpectedTotalCycleFrames','DarkFolderBeginning', ...
    'BaseThicknessUm','BasePlatformHeightMm','AllowIncompleteManifest'};
missing = setdiff(required, fieldnames(config));
if ~isempty(missing)
    error('Config is missing fields: %s', strjoin(missing, ', '));
end
end

function row = emptyRowLocal()
row = struct('K', NaN, 'DatasetID', "", 'AcquisitionOrder', NaN, ...
    'RepeatID', "", 'ThicknessUm', NaN, 'TechnicalID', "", ...
    'ParameterID', "", 'RadiusMm', NaN, 'VelocityMmS', NaN, ...
    'CenterXmm', NaN, 'CenterYmm', NaN, 'PlatformHeightMm', NaN, ...
    'CameraHz', NaN, 'ExposureUs', NaN, 'RequestedCycleCount', NaN, ...
    'ExpectedPeriodFrames', NaN, 'ExpectedTotalCycleFrames', NaN, ...
    'ImageFolder', "", 'ImageCount', NaN, 'FirstImageName', "", ...
    'LastImageName', "", 'DarkFolder', "", 'LogRunID', NaN, ...
    'LogFile', "", 'IncludeInBrightnessAnalysis', false);
end
