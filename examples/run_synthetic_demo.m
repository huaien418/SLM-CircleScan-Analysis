function result = run_synthetic_demo()
%RUN_SYNTHETIC_DEMO Exercise software contracts using generated sample data.
% No experiment images, hardware, external downloads or credentials are used.
% Interval detection is mocked; this is not a real-detector end-to-end test.

originalPath = path;
pathCleanup = onCleanup(@() path(originalPath)); %#ok<NASGU>
repositoryRoot = fileparts(fileparts(mfilename('fullpath')));
sharedRoot = fullfile(repositoryRoot, 'Matlab_Code');
v2Root = fullfile(sharedRoot, 'STAGE3_V2');
addpath(sharedRoot, v2Root, fullfile(v2Root, 'tests'));

expectedDetector = fullfile(sharedRoot, 'detect_circle_scan_interval.m');
assert(strcmpi(which('detect_circle_scan_interval'), expectedDetector), ...
    'The real detector must be selected before running the smoke test.');
beforeTest = path;
result = test_stage3_v2_smoke();
assert(strcmp(path, beforeTest), ...
    'The smoke test must restore the caller MATLAB path.');
assert(strcmpi(which('detect_circle_scan_interval'), expectedDetector), ...
    'The fake detector must not remain selected after the smoke test.');
result.TestPathRestored = true;
fprintf('Test path restored; real detector selected after the smoke test.\n');
fprintf('Generated files are in the temporary study folder printed above.\n');
end
