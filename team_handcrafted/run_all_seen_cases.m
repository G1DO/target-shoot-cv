function run_all_seen_cases()
% RUN_ALL_SEEN_CASES Score the 17 SEEN test images with the team's handcrafted pipeline.
%   Routes Case 2 -> paper_target_score_two_cases, Case 4 -> score_case4_splatter_targets,
%   everything else -> score_shooting_target. Writes handcrafted_seen_results.csv and
%   one annotated PNG per image to annotated_seen_results/.

scriptDir   = fileparts(mfilename('fullpath'));
projectRoot = fileparts(scriptDir);

seenRoot     = fullfile(projectRoot, '2 Shooting Target Score', 'SEEN TESTS');
expectedCsv  = fullfile(projectRoot, 'data_driven', 'phase0', 'phase0_expected_scores.csv');
outCsv       = fullfile(scriptDir, 'handcrafted_seen_results.csv');
annotatedDir = fullfile(scriptDir, 'annotated_seen_results');

if ~exist(annotatedDir, 'dir'); mkdir(annotatedDir); end

items = {
    'Case 1/1.1.jpg',          'default'
    'Case 1/1.2.jpg',          'default'
    'Case 2/2.1.jpg',          'case2'
    'Case 2/4.2.jpg',          'case2'
    'Case 3/3.1.jpg',          'default'
    'Case 3/3.2.png',          'default'
    'Case 4/4.1.jpg',          'case4'
    'Case 4/4.2.jpg',          'case4'
    'Bonus/Case 5/5.1.png',    'default'
    'Bonus/Case 5/5.2.png',    'default'
    'Bonus/Case 6/6.1.jpg',    'default'
    'Bonus/Case 6/6.2.jpg',    'default'
    'Bonus/Case 6/6.3.jpg',    'default'
    'Bonus/Case 7/7.1.jpg',    'default'
    'Bonus/Case 7/7.2.jpg',    'default'
    'Bonus/Case 8/8.1.jpg',    'default'
    'Bonus/Case 8/8.2.jpg',    'default'
};

expTbl = readtable(expectedCsv, 'TextType', 'string');
keys   = cellstr(strrep(expTbl.file, '\', '/'));
vals   = num2cell(expTbl.score_best);
expMap = containers.Map(keys, vals);

nRows = size(items, 1);
rows  = cell(nRows, 6);

fprintf('\n%-26s %10s %10s %10s %6s %7s\n', 'File', 'Expected', 'Predicted', 'AbsErr', 'Hits', 'Ranges');
fprintf('%s\n', repmat('-', 1, 78));

for i = 1:nRows
    relPath  = items{i, 1};
    kind     = items{i, 2};
    fullPath = fullfile(seenRoot, relPath);

    expected = NaN;
    key = strrep(relPath, '\', '/');
    if isKey(expMap, key)
        expected = expMap(key);
    end

    pred = NaN; hc = NaN; rc = NaN; img = [];
    if ~isfile(fullPath)
        warning('Missing image: %s', fullPath);
    else
        try
            switch kind
                case 'case2'
                    result = paper_target_score_two_cases(fullPath, 'ShowResult', false);
                    pred = result.totalScore;
                    hc   = result.hitCount;
                    rc   = numel(result.ringRadii);
                case 'case4'
                    result = score_case4_splatter_targets(fullPath, 'ShowResult', false);
                    pred = result.totalScore;
                    hc   = result.hitCount;
                    rc   = result.rangeCount;
                otherwise
                    result = score_shooting_target(fullPath);
                    pred = result.totalScore;
                    hc   = numel(result.hitScores);
                    rc   = numel(result.ringRadii);
            end
            img = result.annotatedImage;
        catch ME
            warning('Scoring failed on %s: %s', relPath, ME.message);
        end
    end

    ae = NaN;
    if ~isnan(expected) && ~isnan(pred)
        ae = abs(expected - pred);
    end
    rows(i, :) = {relPath, expected, pred, hc, rc, ae};

    if ~isempty(img)
        pngName = flatName(relPath);
        imwrite(img, fullfile(annotatedDir, pngName));
    end
    close all

    fprintf('%-26s %10.0f %10.0f %10.0f %6.0f %7.0f\n', relPath, expected, pred, ae, hc, rc);
end

T = cell2table(rows, 'VariableNames', ...
    {'filename', 'expected_score', 'predicted_score', 'hit_count', 'range_count', 'absolute_error'});
writetable(T, outCsv);

valid = ~isnan(T.absolute_error);
if any(valid)
    expVec  = T.expected_score(valid);
    tolBand = max(0.1 * abs(expVec), 50);
    passCount = sum(T.absolute_error(valid) <= tolBand);
    mae       = mean(T.absolute_error(valid));
    [worstAE, worstIdx] = max(T.absolute_error(valid));
    validRows = T(valid, :);

    fprintf('\nPASS (|err| <= max(10%% , 50)): %d / %d\n', passCount, nnz(valid));
    fprintf('MAE: %.1f\n', mae);
    fprintf('Worst: %s  AE=%.0f (expected %.0f, predicted %.0f)\n', ...
        validRows.filename{worstIdx}, worstAE, ...
        validRows.expected_score(worstIdx), validRows.predicted_score(worstIdx));
else
    fprintf('\nNo valid rows.\n');
end

fprintf('\nWrote: %s\n', outCsv);
fprintf('Annotated PNGs in: %s\n', annotatedDir);
end

function name = flatName(relPath)
name = relPath;
name = strrep(name, '/', '_');
name = strrep(name, '\', '_');
name = strrep(name, ' ', '_');
[~, b, ~] = fileparts(name);
prefix = regexprep(name, '[^/\\]+$', '');
prefix = regexprep(prefix, '[/\\]$', '');
if isempty(prefix)
    name = [b '.png'];
else
    name = [prefix '_' b '.png'];
end
end
