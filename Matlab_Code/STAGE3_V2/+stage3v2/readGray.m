function [image, maxDigital] = readGray(path)
%READGRAY Read an image as double grayscale without normalizing DN values.

raw = imread(char(string(path)));
if ndims(raw) == 3
    if size(raw, 3) ~= 3
        error('Unsupported image channel count: %s', char(string(path)));
    end
    image = 0.2989 * double(raw(:,:,1)) + ...
        0.5870 * double(raw(:,:,2)) + 0.1140 * double(raw(:,:,3));
else
    image = double(raw);
end

if isinteger(raw)
    maxDigital = double(intmax(class(raw)));
else
    finiteValues = image(isfinite(image));
    if isempty(finiteValues)
        error('Image contains no finite pixels: %s', char(string(path)));
    end
    observedMaximum = max(finiteValues);
    if observedMaximum <= 1
        maxDigital = 1;
    elseif observedMaximum <= 255
        maxDigital = 255;
    elseif observedMaximum <= 65535
        maxDigital = 65535;
    else
        maxDigital = observedMaximum;
    end
end
end

