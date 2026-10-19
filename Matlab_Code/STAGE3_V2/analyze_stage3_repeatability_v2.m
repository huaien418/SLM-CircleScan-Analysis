function outputs = analyze_stage3_repeatability_v2(config, runFeatures)
%ANALYZE_STAGE3_REPEATABILITY_V2 Hierarchical repeatability/separation.

required = ["K" "DatasetID" "RepeatID" "ThicknessUm" "TechnicalID" ...
    "FeatureID" "RunMeanOfCycleMeansDN"];
stage3v2.requireVariables(runFeatures, required, 'runFeatures');
statisticsRoot = fullfile(config.AnalysisRoot, 'statistics');
if ~isfolder(statisticsRoot), mkdir(statisticsRoot); end

featureNames = unique(string(runFeatures.FeatureID), 'stable');
technicalRows = repmat(emptyTechnicalLocal(), 0, 1);
for featureIndex = 1:numel(featureNames)
    featureID = featureNames(featureIndex);
    for repeatIndex = 1:numel(config.RepeatIDs)
        repeatID = string(config.RepeatIDs(repeatIndex));
        for thicknessIndex = 1:numel(config.ThicknessUm)
            thickness = double(config.ThicknessUm(thicknessIndex));
            group = runFeatures(runFeatures.FeatureID == featureID & ...
                runFeatures.RepeatID == repeatID & ...
                runFeatures.ThicknessUm == thickness, :);
            group = sortrows(group, 'TechnicalID');
            row = emptyTechnicalLocal();
            row.FeatureID = featureID;
            row.RepeatID = repeatID;
            row.ThicknessUm = thickness;
            row.AvailableTechnicalRepeatCount = height(group);
            expectedTechnical = string(config.TechnicalIDs(:));
            row.Complete = height(group) == numel(expectedTechnical) && ...
                isequal(string(group.TechnicalID(:)), sort(expectedTechnical));
            if height(group) > 0
                values = double(group.RunMeanOfCycleMeansDN);
                row.BrightnessMeanDN = mean(values, 'omitnan');
                row.BrightnessStandardDeviationDN = std(values, 0, 'omitnan');
                row.TechnicalCvPercent = stage3v2.cvPercent(values);
                row.TechnicalRangeDN = max(values) - min(values);
                row.TechnicalCvPassed = row.Complete && ...
                    row.TechnicalCvPercent <= config.MaximumTechnicalCvPercent;
                for valueIndex = 1:min(3, numel(values))
                    row.(sprintf('BrightnessT%02dDN', valueIndex)) = values(valueIndex);
                end
            end
            technicalRows(end+1, 1) = row; %#ok<AGROW>
        end
    end
end
technicalSummary = struct2table(technicalRows);

preparationRows = repmat(emptyPreparationLocal(), 0, 1);
for featureIndex = 1:numel(featureNames)
    featureID = featureNames(featureIndex);
    for thicknessIndex = 1:numel(config.ThicknessUm)
        thickness = double(config.ThicknessUm(thicknessIndex));
        group = technicalSummary(technicalSummary.FeatureID == featureID & ...
            technicalSummary.ThicknessUm == thickness & ...
            technicalSummary.Complete, :);
        row = emptyPreparationLocal();
        row.FeatureID = featureID;
        row.ThicknessUm = thickness;
        row.IndependentPreparationCount = height(group);
        if ~isempty(group)
            values = double(group.BrightnessMeanDN);
            row.PreparationMeanDN = mean(values, 'omitnan');
            row.PreparationStandardDeviationDN = std(values, 0, 'omitnan');
            row.PreparationCvPercent = stage3v2.cvPercent(values);
            row.MedianTechnicalCvPercent = ...
                median(group.TechnicalCvPercent, 'omitnan');
            row.MaximumTechnicalCvPercent = ...
                max(group.TechnicalCvPercent, [], 'omitnan');
        end
        preparationRows(end+1, 1) = row; %#ok<AGROW>
    end
end
preparationSummary = struct2table(preparationRows);

pairedRows = repmat(emptyPairedLocal(), 0, 1);
lowThickness = min(config.ThicknessUm);
highThickness = max(config.ThicknessUm);
for featureIndex = 1:numel(featureNames)
    featureID = featureNames(featureIndex);
    for repeatIndex = 1:numel(config.RepeatIDs)
        repeatID = string(config.RepeatIDs(repeatIndex));
        low = technicalSummary(technicalSummary.FeatureID == featureID & ...
            technicalSummary.RepeatID == repeatID & ...
            technicalSummary.ThicknessUm == lowThickness & ...
            technicalSummary.Complete, :);
        high = technicalSummary(technicalSummary.FeatureID == featureID & ...
            technicalSummary.RepeatID == repeatID & ...
            technicalSummary.ThicknessUm == highThickness & ...
            technicalSummary.Complete, :);
        row = emptyPairedLocal();
        row.FeatureID = featureID;
        row.RepeatID = repeatID;
        row.LowThicknessUm = lowThickness;
        row.HighThicknessUm = highThickness;
        row.Complete = height(low) == 1 && height(high) == 1;
        if row.Complete
            row.LowMeanDN = low.BrightnessMeanDN;
            row.HighMeanDN = high.BrightnessMeanDN;
            row.LowMinusHighDN = row.LowMeanDN - row.HighMeanDN;
            row.DropPercent = 100 * row.LowMinusHighDN / row.LowMeanDN;
            row.ExpectedDirectionPassed = row.LowMinusHighDN > 0;
        end
        pairedRows(end+1, 1) = row; %#ok<AGROW>
    end
end
pairedSummary = struct2table(pairedRows);

separationRows = repmat(emptySeparationLocal(), 0, 1);
for featureIndex = 1:numel(featureNames)
    featureID = featureNames(featureIndex);
    low = preparationSummary(preparationSummary.FeatureID == featureID & ...
        preparationSummary.ThicknessUm == lowThickness, :);
    high = preparationSummary(preparationSummary.FeatureID == featureID & ...
        preparationSummary.ThicknessUm == highThickness, :);
    paired = pairedSummary(pairedSummary.FeatureID == featureID & ...
        pairedSummary.Complete, :);
    technical = technicalSummary(technicalSummary.FeatureID == featureID & ...
        technicalSummary.Complete, :);
    row = emptySeparationLocal();
    row.FeatureID = featureID;
    row.IsPrimaryFeature = featureID == string(config.PrimaryFeature);
    row.LowThicknessUm = lowThickness;
    row.HighThicknessUm = highThickness;
    if height(low) == 1 && height(high) == 1
        row.LowMeanDN = low.PreparationMeanDN;
        row.HighMeanDN = high.PreparationMeanDN;
        row.LowPreparationSdDN = low.PreparationStandardDeviationDN;
        row.HighPreparationSdDN = high.PreparationStandardDeviationDN;
        denominator = hypot(row.LowPreparationSdDN, row.HighPreparationSdDN);
        if denominator > 0
            row.SeparationS = abs(row.LowMeanDN - row.HighMeanDN) / denominator;
        elseif row.LowMeanDN ~= row.HighMeanDN
            row.SeparationS = Inf;
        else
            row.SeparationS = 0;
        end
    end
    row.DirectionAgreementCount = sum(paired.ExpectedDirectionPassed);
    row.CompletePairCount = height(paired);
    differences = double(paired.LowMinusHighDN);
    row.MeanPairedDifferenceDN = mean(differences, 'omitnan');
    [row.PairedDifferenceCiLowDN, row.PairedDifferenceCiHighDN] = ...
        meanCi95Local(differences);
    row.MedianTechnicalCvPercent = ...
        median(technical.TechnicalCvPercent, 'omitnan');
    row.DirectionGatePassed = row.DirectionAgreementCount >= ...
        config.MinimumDirectionAgreementCount;
    row.SeparationGatePassed = row.SeparationS >= config.MinimumSeparationS;
    row.TechnicalCvGatePassed = row.MedianTechnicalCvPercent <= ...
        config.MaximumTechnicalCvPercent;
    row.EndpointValidationPassed = row.DirectionGatePassed && ...
        row.SeparationGatePassed && row.TechnicalCvGatePassed && ...
        row.CompletePairCount == numel(config.RepeatIDs);
    separationRows(end+1, 1) = row; %#ok<AGROW>
end
separationSummary = struct2table(separationRows);

technicalFile = fullfile(statisticsRoot, 'technical_repeat_summary.csv');
preparationFile = fullfile(statisticsRoot, 'independent_preparation_summary.csv');
pairedFile = fullfile(statisticsRoot, 'paired_thickness_summary.csv');
separationFile = fullfile(statisticsRoot, 'separation_summary.csv');
writetable(technicalSummary, technicalFile);
writetable(preparationSummary, preparationFile);
writetable(pairedSummary, pairedFile);
writetable(separationSummary, separationFile);

outputs = struct('TechnicalRepeatSummary', technicalSummary, ...
    'IndependentPreparationSummary', preparationSummary, ...
    'PairedThicknessSummary', pairedSummary, ...
    'SeparationSummary', separationSummary, ...
    'TechnicalFile', string(technicalFile), ...
    'PreparationFile', string(preparationFile), ...
    'PairedFile', string(pairedFile), ...
    'SeparationFile', string(separationFile));

fprintf('\n=== Stage 3 V2 repeatability analysis completed ===\n');
disp(separationSummary(:, {'FeatureID','IsPrimaryFeature', ...
    'DirectionAgreementCount','CompletePairCount','SeparationS', ...
    'MedianTechnicalCvPercent','EndpointValidationPassed'}));
fprintf('Separation summary: %s\n', separationFile);
end

function [low, high] = meanCi95Local(values)
values = double(values(:)); values = values(isfinite(values));
n = numel(values);
if n < 2
    low = NaN; high = NaN; return;
end
critical = tCritical95Local(n - 1);
margin = critical * std(values, 0) / sqrt(n);
low = mean(values) - margin;
high = mean(values) + margin;
end

function value = tCritical95Local(df)
tableValues = [12.706 4.303 3.182 2.776 2.571 2.447 2.365 2.306 ...
    2.262 2.228 2.201 2.179 2.160 2.145 2.131 2.120 2.110 2.101 ...
    2.093 2.086 2.080 2.074 2.069 2.064 2.060 2.056 2.052 2.048 ...
    2.045 2.042];
if df <= numel(tableValues), value = tableValues(max(1, df)); else, value = 1.96; end
end

function row = emptyTechnicalLocal()
row = struct('FeatureID', "", 'RepeatID', "", 'ThicknessUm', NaN, ...
    'AvailableTechnicalRepeatCount', NaN, 'BrightnessT01DN', NaN, ...
    'BrightnessT02DN', NaN, 'BrightnessT03DN', NaN, ...
    'BrightnessMeanDN', NaN, 'BrightnessStandardDeviationDN', NaN, ...
    'TechnicalCvPercent', NaN, 'TechnicalRangeDN', NaN, ...
    'Complete', false, 'TechnicalCvPassed', false);
end

function row = emptyPreparationLocal()
row = struct('FeatureID', "", 'ThicknessUm', NaN, ...
    'IndependentPreparationCount', NaN, 'PreparationMeanDN', NaN, ...
    'PreparationStandardDeviationDN', NaN, 'PreparationCvPercent', NaN, ...
    'MedianTechnicalCvPercent', NaN, 'MaximumTechnicalCvPercent', NaN);
end

function row = emptyPairedLocal()
row = struct('FeatureID', "", 'RepeatID', "", 'LowThicknessUm', NaN, ...
    'HighThicknessUm', NaN, 'LowMeanDN', NaN, 'HighMeanDN', NaN, ...
    'LowMinusHighDN', NaN, 'DropPercent', NaN, ...
    'ExpectedDirectionPassed', false, 'Complete', false);
end

function row = emptySeparationLocal()
row = struct('FeatureID', "", 'IsPrimaryFeature', false, ...
    'LowThicknessUm', NaN, 'HighThicknessUm', NaN, ...
    'LowMeanDN', NaN, 'HighMeanDN', NaN, ...
    'LowPreparationSdDN', NaN, 'HighPreparationSdDN', NaN, ...
    'SeparationS', NaN, 'DirectionAgreementCount', NaN, ...
    'CompletePairCount', NaN, 'MeanPairedDifferenceDN', NaN, ...
    'PairedDifferenceCiLowDN', NaN, 'PairedDifferenceCiHighDN', NaN, ...
    'MedianTechnicalCvPercent', NaN, 'DirectionGatePassed', false, ...
    'SeparationGatePassed', false, 'TechnicalCvGatePassed', false, ...
    'EndpointValidationPassed', false);
end

