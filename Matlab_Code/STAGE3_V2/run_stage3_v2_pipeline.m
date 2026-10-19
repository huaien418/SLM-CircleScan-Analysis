function outputs = run_stage3_v2_pipeline(config, selectedK, rerunExisting)
%RUN_STAGE3_V2_PIPELINE Run the versioned Stage 3 V2 workflow.
%
% First call stops after creating the Global ROI candidate. Approve it with:
%   approve_global_roi_v2(candidateFile)
% Then call this function again to continue the remaining stages.

if nargin < 2, selectedK = []; end
if nargin < 3 || isempty(rerunExisting), rerunExisting = false; end
addpath(char(config.CodeRoot));
addpath(char(config.LegacyCodeRoot));

outputs = struct;
outputs.Config = config;
manifest = build_stage3_manifest_v2(config);
outputs.Manifest = manifest;
if isempty(selectedK), selectedK = 1:height(manifest); end
selectedK = stage3v2.validateSelection(selectedK, height(manifest));

intervalStatus = run_stage3_interval_batch_v2( ...
    config, manifest, selectedK, rerunExisting);
outputs.IntervalStatus = intervalStatus;

approvedRoiFile = fullfile(config.AnalysisRoot, 'roi', ...
    'stage3_v2_global_roi_approved.mat');
if ~isfile(approvedRoiFile)
    candidate = create_global_roi_candidate_v2( ...
        config, manifest, intervalStatus, selectedK);
    outputs.GlobalRoiCandidate = candidate;
    outputs.Status = "WAITING_FOR_GLOBAL_ROI_APPROVAL";
    fprintf('\nPipeline paused intentionally.\n');
    fprintf('Approve the candidate, then run the same pipeline command again.\n');
    return;
end

imageQc = validate_effective_cycle_qc_v2(config, manifest, ...
    intervalStatus, approvedRoiFile, selectedK, rerunExisting);
outputs.ImageQc = imageQc;
motionQc = validate_circlescan_motion_log_v2(config, manifest, selectedK);
outputs.MotionQc = motionQc;
features = extract_stage3_brightness_features_v2(config, manifest, ...
    intervalStatus, imageQc, approvedRoiFile, selectedK, rerunExisting);
outputs.Features = features;

if numel(selectedK) == height(manifest) && ...
        all(features.BatchStatus.BatchStatus ~= "FAILED")
    statistics = analyze_stage3_repeatability_v2(config, features.RunFeatures);
    outputs.Statistics = statistics;
    referenceQc = analyze_reference_drift_v2(config, approvedRoiFile);
    outputs.ReferenceQc = referenceQc;
    outputs.PlotFiles = plot_stage3_results_v2(config, statistics, referenceQc);
    outputs.Audit = audit_stage3_outputs_v2(config);
    requiredFailure = outputs.Audit.Required & ...
        outputs.Audit.Status ~= "PASS";
    if any(requiredFailure)
        outputs.Status = "PIPELINE_COMPLETED_FORMAL_QC_INCOMPLETE";
        fprintf(['\nBrightness analysis completed, but one or more required ' ...
            'formal-QC checks did not pass.\n']);
    else
        outputs.Status = "PIPELINE_COMPLETED";
    end
else
    outputs.Status = "PARTIAL_DATASETS_COMPLETED";
    fprintf(['\nPartial selectedK run completed. Statistics/plots/audit require ' ...
        'all manifest rows without feature failures.\n']);
end
end
