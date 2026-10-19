function [value, pixelCount] = topFractionMean(values, fraction)
%TOPFRACTIONMEAN Mean of the exact brightest ceil(fraction*N) values.

values = sort(double(values(isfinite(values))), 'descend');
if isempty(values)
    value = NaN;
    pixelCount = 0;
    return;
end
if ~(isscalar(fraction) && isfinite(fraction) && fraction > 0 && fraction <= 1)
    error('fraction must be in (0, 1].');
end
pixelCount = max(1, ceil(fraction * numel(values)));
value = mean(values(1:pixelCount), 'omitnan');
end

