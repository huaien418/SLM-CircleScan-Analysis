function files = listImages(folder)
%LISTIMAGES Return naturally sorted supported image files.

folder = char(string(folder));
if ~isfolder(folder)
    error('Image folder not found: %s', folder);
end

extensions = {'*.bmp','*.tif','*.tiff','*.png','*.jpg','*.jpeg'};
files = [];
for extensionIndex = 1:numel(extensions)
    files = [files; dir(fullfile(folder, extensions{extensionIndex}))]; %#ok<AGROW>
end
if isempty(files)
    return;
end

names = string({files.name}).';
numberToken = regexp(names, '\d+', 'match');
lastNumber = nan(numel(names), 1);
for fileIndex = 1:numel(names)
    if ~isempty(numberToken{fileIndex})
        lastNumber(fileIndex) = str2double(numberToken{fileIndex}{end});
    end
end
fallback = (1:numel(names)).';
sortNumber = lastNumber;
sortNumber(~isfinite(sortNumber)) = 1e12 + fallback(~isfinite(sortNumber));
sortTable = table(sortNumber, lower(names), ...
    'VariableNames', {'SortNumber','LowerName'});
[~, order] = sortrows(sortTable, {'SortNumber','LowerName'});
files = files(order);
end
