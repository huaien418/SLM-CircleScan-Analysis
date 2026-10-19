function roiDefinition = approve_global_roi_v2(candidateFile, roiRect)
%APPROVE_GLOBAL_ROI_V2 Save an explicitly user-approved Global ROI.
%
%   approve_global_roi_v2(candidateFile)          % inspect and accept/edit
%   approve_global_roi_v2(candidateFile, [x y w h])

if nargin < 1 || strlength(string(candidateFile)) == 0
    [name, folder] = uigetfile('*.mat', 'Select V2 Global ROI candidate');
    if isequal(name, 0), error('No candidate file was selected.'); end
    candidateFile = fullfile(folder, name);
end
if ~isfile(candidateFile)
    error('Candidate file not found: %s', char(string(candidateFile)));
end
data = load(candidateFile, 'candidate', 'meanImages');
if ~isfield(data, 'candidate') || ~isfield(data.candidate, 'roiRect')
    error('Candidate MAT does not contain the expected candidate structure.');
end
candidate = data.candidate;

if nargin < 2 || isempty(roiRect)
    fig = figure('Color', 'white', 'Name', 'Approve Stage 3 V2 Global ROI');
    imagesc(data.meanImages{1}); axis image; colormap turbo; hold on;
    rectangle('Position', candidate.roiRect, 'EdgeColor', 'r', 'LineWidth', 2);
    title({'Red rectangle = candidate Global ROI', ...
        'Inspect coverage, then answer in the Command Window'});
    drawnow;
    entered = input(sprintf(['Press Enter to accept [%d %d %d %d], or enter ' ...
        '[x y width height]: '], candidate.roiRect));
    close(fig);
    if isempty(entered)
        roiRect = candidate.roiRect;
    else
        roiRect = entered;
    end
end

roiRect = round(double(roiRect(:).'));
if numel(roiRect) ~= 4 || any(~isfinite(roiRect))
    error('roiRect must be finite [x y width height].');
end
x2 = roiRect(1) + roiRect(3);
y2 = roiRect(2) + roiRect(4);
if roiRect(1) < 1 || roiRect(2) < 1 || roiRect(3) < 0 || roiRect(4) < 0 || ...
        x2 > candidate.imageSize(2) || y2 > candidate.imageSize(1)
    error('Approved ROI exceeds image boundaries.');
end

roiDefinition = struct;
roiDefinition.roiRect = roiRect;
roiDefinition.approvalStatus = "APPROVED_BY_USER_VISUAL_REVIEW";
roiDefinition.approvedAt = string(datetime('now', ...
    'Format', 'yyyy-MM-dd HH:mm:ss'));
roiDefinition.sourceCandidateFile = string(candidateFile);
roiDefinition.actualPixelCount = (roiRect(3) + 1) * (roiRect(4) + 1);
roiDefinition.version = "STAGE3_V2_GLOBAL_ROI_APPROVAL_1.0";

outputFolder = fileparts(candidateFile);
approvedFile = fullfile(outputFolder, 'stage3_v2_global_roi_approved.mat');
approvalFile = fullfile(outputFolder, 'stage3_v2_global_roi_approval.csv');
save(approvedFile, 'roiDefinition');
approvalTable = struct2table(roiDefinition, 'AsArray', true);
writetable(approvalTable, approvalFile);

fprintf('\n=== Stage 3 V2 Global ROI approved ===\n');
fprintf('roiRect = [%d %d %d %d]\n', roiRect);
fprintf('Actual pixels: %d\n', roiDefinition.actualPixelCount);
fprintf('Approved ROI: %s\n', approvedFile);
end

