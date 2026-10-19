function plotFiles = plot_stage3_sequence_review_v2(config, outputFolder)
%PLOT_STAGE3_SEQUENCE_REVIEW_V2 Plot existing continuous-sequence CSV results.
% Does not recompute features, change gates, or modify original CSVs/images.
% Usage: plotFiles = plot_stage3_sequence_review_v2(config);
% Four figures: paired means/drop, T01-T03, acquisition order, mean +/- SD.
% The 40/80 conditions within one R are paired stages, not independent beds.

if nargin < 1 || ~isstruct(config) || ~isfield(config, 'AnalysisRoot')
    error('Supply the existing Stage 3 configuration.');
end
if nargin < 2 || strlength(string(outputFolder)) == 0
    stamp = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss_SSS'));
    outputFolder = fullfile(config.AnalysisRoot, 'figures', ...
        ['sequence_review_matlab_' stamp]);
end
if isfolder(outputFolder)
    error('Output directory already exists. Select a new directory to preserve prior figures.');
end
root = config.AnalysisRoot;
primary = string(config.PrimaryFeature);
runs = readtable(fullfile(root, 'features', 'stage3_v2_run_features.csv'), 'TextType', 'string');
manifest = readtable(fullfile(root, 'config', 'stage3_v2_manifest.csv'), 'TextType', 'string');
technical = readtable(fullfile(root, 'statistics', 'technical_repeat_summary.csv'), 'TextType', 'string');
paired = readtable(fullfile(root, 'statistics', 'paired_thickness_summary.csv'), 'TextType', 'string');
prep = readtable(fullfile(root, 'statistics', 'independent_preparation_summary.csv'), 'TextType', 'string');
sep = readtable(fullfile(root, 'statistics', 'separation_summary.csv'), 'TextType', 'string');
runs = runs(string(runs.FeatureID) == primary, :);
technical = technical(string(technical.FeatureID) == primary, :);
paired = paired(string(paired.FeatureID) == primary, :);
prep = sortrows(prep(string(prep.FeatureID) == primary, :), 'ThicknessUm');
sep = sep(string(sep.FeatureID) == primary, :);
repeats = string(config.RepeatIDs(:));
thickness = sort(double(config.ThicknessUm(:)));
nR = numel(repeats);
if ~isequal(thickness, [40;80]) || numel(config.TechnicalIDs) ~= 3 || nR > 5
    error('This review layout supports 40/80 um, T01-T03, and up to five sequences.');
end
if height(runs) ~= nR*6 || height(technical) ~= nR*2 || height(paired) ~= nR || ...
        height(prep) ~= 2 || height(sep) ~= 1 || any(~isfinite(runs.RunMeanOfCycleMeansDN))
    error('Complete, finite primary-feature statistics are required.');
end
for i = 1:height(technical)
    g = runs(runs.RepeatID == technical.RepeatID(i) & ...
        runs.ThicknessUm == technical.ThicknessUm(i), :);
    if height(g) ~= 3 || abs(mean(g.RunMeanOfCycleMeansDN) - technical.BrightnessMeanDN(i)) > 1e-8
        error('Technical summary and run values do not agree.');
    end
end
mkdir(outputFolder);
colors = [0 .447 .698; .835 .369 0; .067 .067 .067; .651 .216 .537; 0 .522 .416];
markers = {'o','s','^','d','x'};
styles = {'-','--',':','-.','--'};
twoColors = colors(1:2,:);
files = strings(4,1);

% 1. Pair each sequence's three-capture means; show signed percent decrease.
fig = newFigureLocal('Continuous sequence pairs', [80 80 1400 650]);
layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(layout); hold(ax, 'on');
for i = 1:nR
    p = paired(paired.RepeatID == repeats(i), :);
    plot(ax, [p.LowThicknessUm p.HighThicknessUm], [p.LowMeanDN p.HighMeanDN], ...
        'Color', colors(i,:), 'Marker', markers{i}, 'LineStyle', styles{i}, ...
        'LineWidth', 2, 'MarkerSize', 9, 'DisplayName', char(repeats(i)));
end
styleAxesLocal(ax); xticks(ax, thickness); xlim(ax, [thickness(1)-5 thickness(2)+5]);
xlabel(ax, '累積名義總粉厚 (μm)'); ylabel(ax, primary + " (DN)");
title(ax, 'A. 同輪配對平均值；每點為三次重拍平均'); legend(ax, 'Location', 'best');
ax = nexttile(layout); bar(ax, 1:height(paired), paired.DropPercent, 'FaceColor', twoColors(1,:));
styleAxesLocal(ax); xticks(ax, 1:height(paired)); xticklabels(ax, paired.RepeatID);
ylabel(ax, '相對本輪40 μm平均的下降幅度 (%)');
title(ax, 'B. (40 μm平均－80 μm平均) / 40 μm平均');
if all(paired.DropPercent >= 0), ylim(ax, [0 max(1,max(paired.DropPercent)*1.25)]); end
for i=1:height(paired)
    text(ax, i, paired.DropPercent(i), sprintf(' %.2f%%', paired.DropPercent(i)), ...
        'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'Color', 'black');
end
title(layout, '連續鋪粉40→80 μm；配對線不是連續厚度校準，左圖Y軸非零起點', 'Color', 'black');
files(1) = savePlotLocal(fig, outputFolder, '01_paired_40_80');

% 2. Each marker is a capture mean. No error bars; report sample CV of T01-T03.
fig = newFigureLocal('Within-bed technical repeats', [40 80 1700 650]);
layout = tiledlayout(fig, 1, nR, 'TileSpacing', 'compact', 'Padding', 'compact');
values = runs.RunMeanOfCycleMeansDN;
pad = max(1, (max(values)-min(values))*.10);
for i=1:nR
    ax=nexttile(layout); hold(ax,'on'); handles=gobjects(2,1); cv=zeros(2,1);
    for h=1:2
        t=technical(technical.RepeatID==repeats(i) & technical.ThicknessUm==thickness(h),:);
        v=[t.BrightnessT01DN t.BrightnessT02DN t.BrightnessT03DN];
        handles(h)=plot(ax,1:3,v,'Color',twoColors(h,:), 'Marker',markers{h}, ...
            'LineStyle',styles{h},'LineWidth',1.8,'MarkerSize',8);
        cv(h)=t.TechnicalCvPercent;
    end
    styleAxesLocal(ax); xlim(ax,[.7 3.3]); ylim(ax,[min(values)-pad max(values)+pad]);
    xticks(ax,1:3); xticklabels(ax,{'T01','T02','T03'});
    title(ax,repeats(i));
    xlabel(ax,sprintf('重拍CV：40 μm %.2f%%\n80 μm %.2f%%',cv(1),cv(2)));
    if i==1
        ylabel(ax,primary+" (DN)");
        legend(ax,handles,{'40 μm','80 μm'},'Location','best');
    end
end
title(layout,'同粉床T01～T03；每點為五圈平均，CV不是五圈內CV；各面板共用Y軸', 'Color','black');
files(2)=savePlotLocal(fig,outputFolder,'02_within_bed_T01_T03');

% 3. Manifest order is not elapsed time. Connect only each three-capture cell.
fig=newFigureLocal('Acquisition-order review',[60 80 1500 650]);
ax=axes('Parent',fig); hold(ax,'on'); seen=false(2,1);
for i=1:nR
    for h=1:2
        g=sortrows(runs(runs.RepeatID==repeats(i) & runs.ThicknessUm==thickness(h),:),'TechnicalID');
        order=zeros(height(g),1);
        for j=1:height(g)
            m=manifest(string(manifest.DatasetID)==string(g.DatasetID(j)),:);
            if height(m)~=1, error('Dataset has no unique manifest order.'); end
            order(j)=m.AcquisitionOrder;
        end
        p=plot(ax,order,g.RunMeanOfCycleMeansDN,'Color',twoColors(h,:), ...
            'Marker',markers{h},'LineStyle',styles{h},'LineWidth',1.8,'MarkerSize',8, ...
            'DisplayName',sprintf('%g μm',thickness(h)));
        if seen(h), p.HandleVisibility='off'; end
        seen(h)=true;
    end
    if i>1, xline(ax,(i-1)*6+.5,':','Color',[.5 .5 .5],'HandleVisibility','off'); end
end
styleAxesLocal(ax); xticks(ax,1:height(runs)); xlim(ax,[.5 height(runs)+.5]);
ylim(ax,[min(values)-pad max(values)+pad]); legend(ax,'Location','best');
xlabel(ax,'Manifest拍攝順序（不是實際時間；每6次為一輪）'); ylabel(ax,primary+" (DN)");
title(ax,{'40 μm T01→T03，再80 μm T01→T03；每輪結束才清粉重建', ...
    '僅連接同床三次重拍；不能單憑順序圖認定時間漂移，Y軸非零起點'});
files(3)=savePlotLocal(fig,outputFolder,'03_acquisition_order');

% 4. Points are sequence means; error bars are across-sequence sample SD.
fig=newFigureLocal('Between-sequence brightness distributions',[80 80 1300 680]);
layout=tiledlayout(fig,1,2,'TileSpacing','compact','Padding','compact');
ax=nexttile(layout); hold(ax,'on');
jitter=linspace(-.14,.14,nR);
for h=1:2
    group=technical(technical.ThicknessUm==thickness(h),:);
    for i=1:nR
        t=group(group.RepeatID==repeats(i),:);
        plot(ax,h+jitter(i),t.BrightnessMeanDN,'LineStyle','none','Marker',markers{i}, ...
            'Color',twoColors(h,:),'MarkerSize',8,'HandleVisibility','off');
        text(ax,h+jitter(i),t.BrightnessMeanDN,repeats(i),'Color','black', ...
            'VerticalAlignment','bottom','HorizontalAlignment','center','FontSize',11);
    end
    errorbar(ax,h+.30,prep.PreparationMeanDN(h),prep.PreparationStandardDeviationDN(h), ...
        'kd','LineStyle','none','LineWidth',1.8,'MarkerSize',9,'MarkerFaceColor','black');
end
styleAxesLocal(ax); xticks(ax,[1 2]); xticklabels(ax,{'40 μm','80 μm'}); xlim(ax,[.5 2.7]);
ylabel(ax,primary+" (DN)"); title(ax,'點＝各輪三次平均；黑色＝五輪平均±樣本SD');
ax=nexttile(layout); axis(ax,'off');
lines={sprintf('S = |μ40 - μ80| / sqrt(s40^2 + s80^2)'), ...
    sprintf('μ40 = %.3f DN; μ80 = %.3f DN',sep.LowMeanDN,sep.HighMeanDN), ...
    sprintf('s40 = %.3f DN; s80 = %.3f DN',sep.LowPreparationSdDN,sep.HighPreparationSdDN), ...
    sprintf('S = %.2f；目前先導門檻 = %.2f',sep.SeparationS,config.MinimumSeparationS), ...
    '同向下降不等於跨輪絕對亮度已能分層。', ...
    '誤差棒不是SEM、95% CI或單次拍攝不確定度。', ...
    'S不是分類正確率或顯著性檢定。'};
text(ax,.02,.94,lines,'Units','normalized','VerticalAlignment','top', ...
    'Color','black','FontSize',16,'FontName','Microsoft JhengHei','Interpreter','none');
title(layout,'跨輪描述分布（n=5條序列）；不是未知厚度的外部驗證結果', 'Color','black');
files(4)=savePlotLocal(fig,outputFolder,'04_between_sequence_distribution');

plotFiles=table(files,'VariableNames',{'PlotFile'});
writetable(plotFiles,fullfile(outputFolder,'plot_index.csv'));
fprintf('\n=== Continuous-sequence review figures created ===\n%s\n',outputFolder);
disp(plotFiles);
end

function fig=newFigureLocal(name,position)
fig=figure('Visible','off','Color','white','Name',name,'Position',position);
set(fig,'DefaultAxesColor','white','DefaultAxesXColor','black', ...
    'DefaultAxesYColor','black','DefaultAxesFontName','Microsoft JhengHei', ...
    'DefaultAxesFontSize',14,'DefaultTextColor','black', ...
    'DefaultTextFontName','Microsoft JhengHei');
end

function styleAxesLocal(ax)
set(ax,'Color','white','XColor','black','YColor','black', ...
    'FontName','Microsoft JhengHei','FontSize',14,'LineWidth',1, ...
    'GridColor',[.6 .6 .6],'GridAlpha',.25);
grid(ax,'on'); box(ax,'off');
end

function file=savePlotLocal(fig,folder,name)
file=string(fullfile(folder,[name '.png']));
exportgraphics(fig,file,'Resolution',180);
savefig(fig,fullfile(folder,[name '.fig']));
close(fig);
end
