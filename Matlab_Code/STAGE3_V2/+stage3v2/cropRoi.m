function roi = cropRoi(image, rect)
%CROPROI Crop using MATLAB rectangle semantics [x y width height].

rect = round(double(rect(:).'));
if numel(rect) ~= 4 || any(~isfinite(rect))
    error('ROI must be finite [x y width height].');
end
x1 = rect(1);
y1 = rect(2);
x2 = x1 + rect(3);
y2 = y1 + rect(4);
if x1 < 1 || y1 < 1 || x2 > size(image, 2) || y2 > size(image, 1) || ...
        x2 < x1 || y2 < y1
    error('ROI [%g %g %g %g] is outside the image boundary.', rect);
end
roi = image(y1:y2, x1:x2);
end

