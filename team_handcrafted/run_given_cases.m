function results = run_given_cases()

scriptDir = fileparts(mfilename('fullpath'));
if isempty(scriptDir)
    scriptDir = pwd;
end

cases = {
    'Case1.1.jpg', 2350
    'Case1.2.jpg', 2950
    'Case2.1.jpg', 1000
    'Case2.2.jpg', 2100
    'Case3.1.jpg', 1400
    'Case3.2.png', 3800
    'Case4.1.jpg', 6100
    'Case4.2.jpg', 11950
    'Untitled.jpg' , 000000
};

outputDir = fullfile(scriptDir, 'annotated_results');
if ~exist(outputDir, 'dir')
    mkdir(outputDir);
end

results = table('Size', [size(cases, 1), 6], ...
    'VariableTypes', {'string', 'double', 'double', 'double', 'double', 'double'}, ...
    'VariableNames', {'FileName', 'ExpectedScore', 'DetectedScore', ...
    'Difference', 'HitCount', 'RangeCount'});

fprintf('\n%-12s %10s %10s %10s %6s %7s\n', ...
    'File', 'Expected', 'Detected', 'Diff', 'Hits', 'Ranges');
fprintf('%s\n', repmat('-', 1, 64));

for index = 1:size(cases, 1)
    fileName = cases{index, 1};
    expectedScore = cases{index, 2};
    imagePath = fullfile(scriptDir, fileName);

    if ~exist(imagePath, 'file')
        warning('Missing image: %s', imagePath);
        detectedScore = NaN;
        hitCount = NaN;
        rangeCount = NaN;
    else
        result = score_shooting_target(imagePath);
        detectedScore = result.totalScore;
        hitCount = numel(result.hitScores);
        rangeCount = numel(result.ringRadii);

        [~, baseName, ~] = fileparts(fileName);
        outputPath = fullfile(outputDir, [baseName '_annotated.png']);
        imwrite(result.annotatedImage, outputPath);
    end

    difference = detectedScore - expectedScore;
    results(index, :) = {string(fileName), expectedScore, detectedScore, ...
        difference, hitCount, rangeCount};

    fprintf('%-12s %10.0f %10.0f %+10.0f %6.0f %7.0f\n', ...
        fileName, expectedScore, detectedScore, difference, hitCount, rangeCount);
end

fprintf('%s\n', repmat('-', 1, 64));
fprintf('Annotated images saved in: %s\n\n', outputDir);
end
