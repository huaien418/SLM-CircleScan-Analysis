function [meanImage, maxDigital, files] = meanImage(folder, selectedIndices)
%MEANIMAGE Calculate a mean image using a numerically stable update.

files = stage3v2.listImages(folder);
if isempty(files)
    error('No supported images found in: %s', char(string(folder)));
end
if nargin < 2 || isempty(selectedIndices)
    selectedIndices = 1:numel(files);
end
if any(selectedIndices < 1) || any(selectedIndices > numel(files)) || ...
        any(selectedIndices ~= round(selectedIndices))
    error('selectedIndices contains an invalid image index.');
end

meanImage = [];
maxDigital = NaN;
for position = 1:numel(selectedIndices)
    fileIndex = selectedIndices(position);
    [image, currentMax] = stage3v2.readGray( ...
        fullfile(folder, files(fileIndex).name));
    if isempty(meanImage)
        meanImage = zeros(size(image));
        maxDigital = currentMax;
    elseif ~isequal(size(image), size(meanImage))
        error('Image size changed in folder: %s', char(string(folder)));
    end
    meanImage = meanImage + (image - meanImage) / position;
    maxDigital = max(maxDigital, currentMax);
end
end

