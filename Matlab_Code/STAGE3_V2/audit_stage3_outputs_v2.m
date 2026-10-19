function audit = audit_stage3_outputs_v2(config)
%AUDIT_STAGE3_OUTPUTS_V2 Read-only integrity audit of Stage 3 V2 outputs.

analysisRoot = char(config.AnalysisRoot);
motionRequired = configFlagLocal(config, ...
    'RequireMotionLogForFormalValidation', true);
endDarkRequired = configFlagLocal(config, ...
    'RequireEndDarkForFormalValidation', false);
nakedRequired = configFlagLocal(config, ...
    'RequireNakedReferenceForFormalValidation', false);
rows = repmat(emptyAuditRowLocal(), 0, 1);
rows(end+1, 1) = fileCheckLocal('CONFIG', ...
    fullfile(analysisRoot, 'config', 'stage3_v2_config.mat'), true); %#ok<AGROW>
rows(end+1, 1) = fileCheckLocal('MANIFEST', ...
    fullfile(analysisRoot, 'config', 'stage3_v2_manifest.csv'), true); %#ok<AGROW>
rows(end+1, 1) = fileCheckLocal('APPROVED_ROI', ...
    fullfile(analysisRoot, 'roi', 'stage3_v2_global_roi_approved.mat'), true); %#ok<AGROW>
rows(end+1, 1) = fileCheckLocal('INTERVAL_STATUS', ...
    fullfile(analysisRoot, 'batch_status', 'stage3_v2_interval_status.csv'), true); %#ok<AGROW>
rows(end+1, 1) = fileCheckLocal('IMAGE_QC', ...
    fullfile(analysisRoot, 'batch_status', 'stage3_v2_image_qc_status.csv'), true); %#ok<AGROW>
rows(end+1, 1) = fileCheckLocal('RUN_FEATURES', ...
    fullfile(analysisRoot, 'features', 'stage3_v2_run_features.csv'), true); %#ok<AGROW>
rows(end+1, 1) = fileCheckLocal('SEPARATION', ...
    fullfile(analysisRoot, 'statistics', 'separation_summary.csv'), true); %#ok<AGROW>
rows(end+1, 1) = fileCheckLocal('MOTION_QC', ...
    fullfile(analysisRoot, 'qc', 'stage3_v2_motion_qc.csv'), motionRequired); %#ok<AGROW>
rows(end+1, 1) = fileCheckLocal('REFERENCE_QC', ...
    fullfile(analysisRoot, 'qc', 'stage3_v2_reference_qc.csv'), ...
    endDarkRequired || nakedRequired); %#ok<AGROW>

expectedDatasets = numel(config.RepeatIDs) * numel(config.ThicknessUm) * ...
    numel(config.TechnicalIDs);
manifestFile = fullfile(analysisRoot, 'config', 'stage3_v2_manifest.csv');
if isfile(manifestFile)
    manifest = readtable(manifestFile, 'TextType', 'string');
    rows(end+1, 1) = valueCheckLocal('MANIFEST_ROW_COUNT', ...
        height(manifest) == expectedDatasets, true, ...
        sprintf('Expected %d; found %d.', expectedDatasets, height(manifest))); %#ok<AGROW>
    rows(end+1, 1) = valueCheckLocal('UNIQUE_DATASET_ID', ...
        numel(unique(manifest.DatasetID)) == height(manifest), true, ...
        'DatasetID must be unique.'); %#ok<AGROW>
end

intervalFile = fullfile(analysisRoot, 'batch_status', ...
    'stage3_v2_interval_status.csv');
if isfile(intervalFile)
    interval = readtable(intervalFile, 'TextType', 'string');
    rows(end+1, 1) = valueCheckLocal('INTERVAL_ROW_COUNT', ...
        height(interval) == expectedDatasets, true, ...
        sprintf('Expected %d; found %d.', expectedDatasets, height(interval))); %#ok<AGROW>
    rows(end+1, 1) = valueCheckLocal('COMPLETE_CYCLE_COUNT', ...
        all(interval.CompleteCycleCount >= config.RequestedCycleCount), true, ...
        'Every formal dataset must contain the requested cycles.'); %#ok<AGROW>
end

imageQcFile = fullfile(analysisRoot, 'batch_status', ...
    'stage3_v2_image_qc_status.csv');
if isfile(imageQcFile)
    imageQc = readtable(imageQcFile, 'TextType', 'string');
    uniqueRois = unique(imageQc(:, {'RoiX','RoiY','RoiWidth','RoiHeight'}), ...
        'rows');
    sameRoi = height(uniqueRois) == 1;
    rows(end+1, 1) = valueCheckLocal('ONE_GLOBAL_ROI', sameRoi, true, ...
        'All datasets must use one approved Global ROI.'); %#ok<AGROW>
    rows(end+1, 1) = valueCheckLocal('IMAGE_QC_ROW_COUNT', ...
        height(imageQc) == expectedDatasets, true, ...
        sprintf('Expected %d; found %d.', expectedDatasets, height(imageQc))); %#ok<AGROW>
end

runFile = fullfile(analysisRoot, 'features', 'stage3_v2_run_features.csv');
if isfile(runFile)
    runFeatures = readtable(runFile, 'TextType', 'string');
    primaryRows = runFeatures.FeatureID == string(config.PrimaryFeature);
    rows(end+1, 1) = valueCheckLocal('PRIMARY_FEATURE_PRESENT', ...
        sum(primaryRows) == expectedDatasets, true, ...
        sprintf('Expected %d %s rows; found %d.', expectedDatasets, ...
        config.PrimaryFeature, sum(primaryRows))); %#ok<AGROW>
end

cycleFile = fullfile(analysisRoot, 'features', 'stage3_v2_cycle_features.csv');
if isfile(cycleFile)
    cycleFeatures = readtable(cycleFile, 'TextType', 'string');
    primary = cycleFeatures(cycleFeatures.FeatureID == string(config.PrimaryFeature), :);
    datasetIDs = unique(primary.DatasetID, 'stable');
    cycleCounts = zeros(numel(datasetIDs), 1);
    for datasetIndex = 1:numel(datasetIDs)
        cycleCounts(datasetIndex) = sum(primary.DatasetID == datasetIDs(datasetIndex));
    end
    rows(end+1, 1) = valueCheckLocal('FIVE_PRIMARY_CYCLES_PER_DATASET', ...
        numel(datasetIDs) == expectedDatasets && ...
        all(cycleCounts == config.RequestedCycleCount), true, ...
        'Primary feature must contain one row per requested cycle.'); %#ok<AGROW>
end

motionFile = fullfile(analysisRoot, 'qc', 'stage3_v2_motion_qc.csv');
if isfile(motionFile)
    motionQc = readtable(motionFile, 'TextType', 'string');
    rowCountPassed = height(motionQc) == expectedDatasets;
    commandPassed = rowCountPassed && ...
        ismember('CommandPathValid', motionQc.Properties.VariableNames) && ...
        all(logical(motionQc.CommandPathValid));
    rows(end+1, 1) = valueCheckLocal('MOTION_QC_ROW_COUNT', ...
        rowCountPassed, motionRequired, ...
        sprintf('Expected %d; found %d.', expectedDatasets, height(motionQc))); %#ok<AGROW>
    rows(end+1, 1) = valueCheckLocal('ALL_COMMAND_PATHS_VALID', ...
        commandPassed, motionRequired, ...
        ['Command geometry must pass for every dataset when motion logs ' ...
        'are required. Response evidence remains a separate field.']); %#ok<AGROW>
end

referenceFile = fullfile(analysisRoot, 'qc', 'stage3_v2_reference_qc.csv');
if isfile(referenceFile)
    referenceQc = readtable(referenceFile, 'TextType', 'string');
    dark = referenceQc(referenceQc.ReferenceType == "DARK", :);
    naked = referenceQc(referenceQc.ReferenceType == "NAKED", :);
    darkAvailable = height(dark) == 1 && ...
        dark.ReferenceQcStatus ~= "NOT_AVAILABLE" && ...
        dark.ReferenceQcStatus ~= "FAILED";
    nakedAvailable = height(naked) == 1 && ...
        naked.ReferenceQcStatus ~= "NOT_AVAILABLE" && ...
        naked.ReferenceQcStatus ~= "FAILED";
    rows(end+1, 1) = valueCheckLocal('END_DARK_REFERENCE_AVAILABLE', ...
        darkAvailable, endDarkRequired, ...
        'End dark is optional unless explicitly required in config.'); %#ok<AGROW>
    rows(end+1, 1) = valueCheckLocal('NAKED_REFERENCE_AVAILABLE', ...
        nakedAvailable, nakedRequired, ...
        'Naked-bed references are optional unless explicitly required in config.'); %#ok<AGROW>
end

audit = struct2table(rows);
auditRoot = fullfile(analysisRoot, 'audit');
if ~isfolder(auditRoot), mkdir(auditRoot); end
auditFile = fullfile(auditRoot, 'stage3_v2_audit.csv');
writetable(audit, auditFile);
writeLimitsLocal(fullfile(auditRoot, 'stage3_v2_method_and_limits.txt'), config);

requiredFailure = audit.Required & audit.Status ~= "PASS";
fprintf('\n=== Stage 3 V2 audit ===\n');
disp(audit);
if any(requiredFailure)
    fprintf('Overall: INCOMPLETE_OR_FAILED (%d required checks)\n', ...
        sum(requiredFailure));
else
    fprintf('Overall: STATIC_OUTPUT_CONTRACT_PASSED\n');
    fprintf('This does not prove the physical thickness model is valid.\n');
end
fprintf('Audit CSV: %s\n', auditFile);
end

function row = fileCheckLocal(checkID, path, required)
row = emptyAuditRowLocal(); row.CheckID = string(checkID); row.Required = required;
if isfile(path)
    row.Status = "PASS"; row.Details = "Found: " + string(path);
elseif required
    row.Status = "FAIL"; row.Details = "Missing: " + string(path);
else
    row.Status = "NOT_AVAILABLE"; row.Details = "Optional file missing: " + string(path);
end
end

function row = valueCheckLocal(checkID, passed, required, details)
row = emptyAuditRowLocal(); row.CheckID = string(checkID); row.Required = required;
if passed
    row.Status = "PASS";
elseif required
    row.Status = "FAIL";
else
    row.Status = "NOT_AVAILABLE";
end
row.Details = string(details);
end

function writeLimitsLocal(path, config)
fileID = fopen(path, 'w');
if fileID < 0, error('Could not write method-and-limits file: %s', path); end
cleanup = onCleanup(@() fclose(fileID));
fprintf(fileID, 'Stage 3 V2 method and limits\n');
fprintf(fileID, 'Config version: %s\n', config.ConfigVersion);
fprintf(fileID, 'Primary feature: %s\n', config.PrimaryFeature);
fprintf(fileID, 'Top1MeanDN is calculated after dark correction.\n');
fprintf(fileID, 'Run brightness is the equal-weight mean of cycle means.\n');
fprintf(fileID, 'T01-T03 are technical captures, not independent preparations.\n');
fprintf(fileID, 'R01-R05 are intended independent re-powdering preparations.\n');
fprintf(fileID, 'Image-period evidence does not prove a geometric XY circle.\n');
fprintf(fileID, 'Command validity does not prove hardware response validity.\n');
fprintf(fileID, 'Motion log required for formal validation: %d.\n', ...
    configFlagLocal(config, 'RequireMotionLogForFormalValidation', true));
fprintf(fileID, 'End dark required for formal validation: %d.\n', ...
    configFlagLocal(config, 'RequireEndDarkForFormalValidation', false));
fprintf(fileID, 'Naked reference required for formal validation: %d.\n', ...
    configFlagLocal(config, 'RequireNakedReferenceForFormalValidation', false));
fprintf(fileID, 'Saturation is assessed on raw pixels before dark correction.\n');
fprintf(fileID, 'Feature comparison is screening evidence; no automatic winner is selected.\n');
fprintf(fileID, 'Endpoint validation gates: direction >= %d/%d, S >= %.3g, technical CV <= %.3g%%.\n', ...
    config.MinimumDirectionAgreementCount, numel(config.RepeatIDs), ...
    config.MinimumSeparationS, config.MaximumTechnicalCvPercent);
end

function row = emptyAuditRowLocal()
row = struct('CheckID', "", 'Required', false, 'Status', "", 'Details', "");
end

function value = configFlagLocal(config, fieldName, defaultValue)
if isfield(config, fieldName)
    value = logical(config.(fieldName));
else
    value = logical(defaultValue);
end
end
