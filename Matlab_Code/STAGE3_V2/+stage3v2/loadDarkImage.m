function [darkImage, darkFiles] = loadDarkImage(folder, expectedSize)
%LOADDARKIMAGE Load the mean dark image and optionally verify its size.

if nargin < 1 || strlength(string(folder)) == 0
    error('A matching dark-frame folder is required.');
end
[darkImage, ~, darkFiles] = stage3v2.meanImage(folder);
if nargin >= 2 && ~isempty(expectedSize) && ~isequal(size(darkImage), expectedSize)
    error('Dark-frame size does not match the experimental images.');
end
end

