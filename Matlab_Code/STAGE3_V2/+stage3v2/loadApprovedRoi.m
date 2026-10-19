function roi = loadApprovedRoi(path)
%LOADAPPROVEDROI Load an explicitly approved V2 Global ROI.

if ~isfile(path)
    error('Approved Global ROI file not found: %s', char(string(path)));
end
data = load(path);
if isfield(data, 'roiDefinition')
    definition = data.roiDefinition;
    if ~isfield(definition, 'roiRect') || ~isfield(definition, 'approvalStatus')
        error('ROI definition is incomplete: %s', char(string(path)));
    end
    roiRect = definition.roiRect;
    approvalStatus = string(definition.approvalStatus);
elseif isfield(data, 'roiRect') && isfield(data, 'approvalStatus')
    roiRect = data.roiRect;
    approvalStatus = string(data.approvalStatus);
else
    error('Approved ROI file lacks roiRect/approvalStatus: %s', char(string(path)));
end
if approvalStatus ~= "APPROVED_BY_USER_VISUAL_REVIEW"
    error('ROI is not marked APPROVED_BY_USER_VISUAL_REVIEW.');
end
roi = struct('roiRect', double(roiRect(:).'), ...
    'approvalStatus', approvalStatus, 'sourceFile', string(path));
end

