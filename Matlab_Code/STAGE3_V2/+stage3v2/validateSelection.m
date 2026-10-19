function selectedK = validateSelection(selectedK, runCount)
%VALIDATESELECTION Validate row indices for a batch function.

if nargin < 1 || isempty(selectedK)
    selectedK = 1:runCount;
end
if ~isnumeric(selectedK) || isempty(selectedK) || ...
        any(~isfinite(selectedK)) || any(selectedK ~= round(selectedK)) || ...
        any(selectedK < 1) || any(selectedK > runCount)
    error('selectedK must contain integer row indices from 1 to %d.', runCount);
end
selectedK = unique(selectedK(:).', 'stable');
end

