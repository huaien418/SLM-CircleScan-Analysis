function value = percentile(values, percent)
%PERCENTILE Toolbox-independent linearly interpolated percentile.

values = sort(double(values(isfinite(values))));
if isempty(values)
    value = NaN;
    return;
end
if ~(isscalar(percent) && isfinite(percent) && percent >= 0 && percent <= 100)
    error('percent must be between 0 and 100.');
end
position = 1 + (numel(values) - 1) * percent / 100;
lowerIndex = floor(position);
upperIndex = ceil(position);
if lowerIndex == upperIndex
    value = values(lowerIndex);
else
    weight = position - lowerIndex;
    value = values(lowerIndex) * (1 - weight) + values(upperIndex) * weight;
end
end

