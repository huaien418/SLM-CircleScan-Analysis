function value = cvPercent(values)
%CVPERCENT Sample coefficient of variation in percent.

values = double(values(:));
values = values(isfinite(values));
if numel(values) < 2
    value = NaN;
    return;
end
meanValue = mean(values);
if meanValue <= 0
    value = NaN;
else
    value = 100 * std(values, 0) / meanValue;
end
end

