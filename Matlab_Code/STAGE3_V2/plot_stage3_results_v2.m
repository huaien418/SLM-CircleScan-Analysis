function plotFiles = plot_stage3_results_v2(config, statistics, referenceQc)
%PLOT_STAGE3_RESULTS_V2 Create formal, colorblind-safe Stage 3 V2 figures.

if nargin < 2 || isempty(statistics)
    statistics = loadStatisticsLocal(config.AnalysisRoot);
end
if nargin < 3
    referenceFile = fullfile(config.AnalysisRoot, 'qc', ...
        'stage3_v2_reference_qc.csv');
    if isfile(referenceFile)
        referenceQc = readtable(referenceFile, 'TextType', 'string');
    else
        referenceQc = table();
    end
end

figureRoot = fullfile(config.AnalysisRoot, 'figures');
formalRoot = fullfile(figureRoot, 'formal');
diagnosticRoot = fullfile(figureRoot, 'diagnostic');
if ~isfolder(formalRoot), mkdir(formalRoot); end
if ~isfolder(diagnosticRoot), mkdir(diagnosticRoot); end
files = strings(0, 1);

technical = statistics.TechnicalRepeatSummary;
preparation = statistics.IndependentPreparationSummary;
paired = statistics.PairedThicknessSummary;
separation = statistics.SeparationSummary;
primary = string(config.PrimaryFeature);
primaryTechnical = technical(technical.FeatureID == primary & technical.Complete, :);
primaryPaired = paired(paired.FeatureID == primary & paired.Complete, :);
primaryPreparation = preparation(preparation.FeatureID == primary, :);

% 1. Paired independent preparations.
fig = newFigureLocal('Paired 40-80 preparations');
hold on;
colors = colororder(gca);
for repeatIndex = 1:height(primaryPaired)
    plot([primaryPaired.LowThicknessUm(repeatIndex), ...
        primaryPaired.HighThicknessUm(repeatIndex)], ...
        [primaryPaired.LowMeanDN(repeatIndex), primaryPaired.HighMeanDN(repeatIndex)], ...
        '-o', 'LineWidth', 1.8, 'MarkerSize', 7, ...
        'Color', colors(mod(repeatIndex-1, size(colors,1))+1, :), ...
        'DisplayName', char(primaryPaired.RepeatID(repeatIndex)));
end
grid on; xlabel('Powder thickness (um)'); ylabel(primary + " (DN)");
title('Independent re-powdering pairs: 40 vs 80 um');
legend('Location', 'best'); set(gca, 'XTick', unique([primaryPaired.LowThicknessUm; ...
    primaryPaired.HighThicknessUm]));
file = fullfile(formalRoot, '01_primary_feature_paired_40_80.png');
exportgraphics(fig, file, 'Resolution', 180); close(fig); files(end+1) = file; %#ok<AGROW>

% 2. Technical repeats within each powder bed.
fig = newFigureLocal('Technical repeats'); hold on;
thicknesses = sort(unique(primaryTechnical.ThicknessUm));
for thicknessIndex = 1:numel(thicknesses)
    group = primaryTechnical(primaryTechnical.ThicknessUm == thicknesses(thicknessIndex), :);
    for rowIndex = 1:height(group)
        values = [group.BrightnessT01DN(rowIndex), ...
            group.BrightnessT02DN(rowIndex), group.BrightnessT03DN(rowIndex)];
        x = thicknesses(thicknessIndex) + [-0.8 0 0.8];
        plot(x, values, '-o', 'LineWidth', 1.2, 'MarkerSize', 6, ...
            'Color', colors(mod(rowIndex-1, size(colors,1))+1, :), ...
            'HandleVisibility', 'off');
    end
end
grid on; xlabel('Powder thickness (um)'); ylabel(primary + " (DN)");
title('T01-T03 within-bed technical repeats'); set(gca, 'XTick', thicknesses);
file = fullfile(formalRoot, '02_primary_feature_technical_repeats.png');
exportgraphics(fig, file, 'Resolution', 180); close(fig); files(end+1) = file; %#ok<AGROW>

% 3. Independent-preparation mean and SD.
fig = newFigureLocal('Independent preparation mean and SD');
errorbar(primaryPreparation.ThicknessUm, primaryPreparation.PreparationMeanDN, ...
    primaryPreparation.PreparationStandardDeviationDN, '-o', ...
    'LineWidth', 2, 'MarkerSize', 8, 'Color', [0 0.4470 0.7410]);
grid on; xlabel('Powder thickness (um)'); ylabel(primary + " (DN)");
title('Mean +/- independent-preparation SD');
set(gca, 'XTick', primaryPreparation.ThicknessUm);
file = fullfile(formalRoot, '03_primary_feature_preparation_mean_sd.png');
exportgraphics(fig, file, 'Resolution', 180); close(fig); files(end+1) = file; %#ok<AGROW>

% 4. Feature-screening evidence without auto-ranking.
fig = figure('Visible', 'off', 'Color', 'white', 'Position', [50 50 1400 620]);
layout = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact');
labels = categorical(separation.FeatureID, separation.FeatureID);
ax = nexttile(layout); bar(ax, labels, separation.SeparationS, ...
    'FaceColor', [0 0.4470 0.7410]); grid(ax, 'on');
yline(ax, config.MinimumSeparationS, '--', 'Screening gate');
ylabel(ax, 'Endpoint separation S'); xtickangle(ax, 35);
ax = nexttile(layout); bar(ax, labels, separation.DirectionAgreementCount, ...
    'FaceColor', [0.8500 0.3250 0.0980]); grid(ax, 'on');
yline(ax, config.MinimumDirectionAgreementCount, '--', 'Direction gate');
ylabel(ax, 'Expected-direction repeats'); xtickangle(ax, 35);
ax = nexttile(layout); bar(ax, labels, separation.MedianTechnicalCvPercent, ...
    'FaceColor', [0.4660 0.6740 0.1880]); grid(ax, 'on');
yline(ax, config.MaximumTechnicalCvPercent, '--', 'Technical CV gate');
ylabel(ax, 'Median T01-T03 CV (%)'); xtickangle(ax, 35);
title(layout, ['Feature comparison is screening evidence only; primary = ' char(primary)], ...
    'Color', 'black', 'FontWeight', 'bold');
file = fullfile(formalRoot, '04_feature_screening_comparison.png');
exportgraphics(fig, file, 'Resolution', 180); close(fig); files(end+1) = file; %#ok<AGROW>

% 5. Reference drift, if available.
if ~isempty(referenceQc)
    available = referenceQc.ReferenceQcStatus ~= "NOT_AVAILABLE";
    if any(available)
        data = referenceQc(available, :);
        fig = newFigureLocal('Reference drift');
        values = [data.RoiMeanDriftPercent, data.Top1DriftPercent];
        bar(categorical(data.ReferenceType, data.ReferenceType), values);
        grid on; ylabel('Symmetric beginning/end difference (%)');
        legend({'ROI mean','Top1 mean'}, 'Location', 'best');
        title('Beginning/end reference drift (descriptive, no hard gate)');
        file = fullfile(diagnosticRoot, 'reference_drift.png');
        exportgraphics(fig, file, 'Resolution', 180); close(fig); files(end+1) = file; %#ok<AGROW>
    end
end

% Keep one file per table row. A row-string input would otherwise expand
% into PlotFile_1, PlotFile_2, ... when written to CSV.
plotFiles = table(files(:), 'VariableNames', {'PlotFile'});
writetable(plotFiles, fullfile(figureRoot, 'stage3_v2_plot_index.csv'));
fprintf('\nStage 3 V2 figures: %s\n', figureRoot);
end

function fig = newFigureLocal(name)
fig = figure('Visible', 'off', 'Color', 'white', 'Name', name, ...
    'Position', [80 80 950 650]);
set(fig, 'DefaultAxesColor', 'white', 'DefaultAxesXColor', 'black', ...
    'DefaultAxesYColor', 'black', 'DefaultTextColor', 'black');
colororder([0 0.4470 0.7410; 0.8500 0.3250 0.0980; ...
    0.4660 0.6740 0.1880; 0.4940 0.1840 0.5560; ...
    0.3010 0.7450 0.9330]);
end

function statistics = loadStatisticsLocal(analysisRoot)
root = fullfile(analysisRoot, 'statistics');
files = struct('TechnicalRepeatSummary', 'technical_repeat_summary.csv', ...
    'IndependentPreparationSummary', 'independent_preparation_summary.csv', ...
    'PairedThicknessSummary', 'paired_thickness_summary.csv', ...
    'SeparationSummary', 'separation_summary.csv');
names = fieldnames(files);
statistics = struct;
for index = 1:numel(names)
    path = fullfile(root, files.(names{index}));
    if ~isfile(path), error('Statistics file missing: %s', path); end
    statistics.(names{index}) = readtable(path, 'TextType', 'string');
end
end
