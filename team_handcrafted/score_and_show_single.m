function score_and_show_single(imagePath)
    % 1. Get the parts of the filename
    [imgDir, baseName, ext] = fileparts(imagePath);
    
    % If the image is in the current folder, imgDir will be empty.
    % We default it to the current directory (pwd).
    if isempty(imgDir)
        imgDir = pwd;
    end
    
    outputDir = fullfile(imgDir, 'annotated_results');
    
    % Ensure the output directory exists
    if ~exist(outputDir, 'dir')
        mkdir(outputDir);
    end

    % 2. Run the core algorithm (score_shooting_target)
    % This must return a struct with .totalScore, .hitScores, .ringRadii, and .annotatedImage
    result = score_shooting_target(imagePath);
    
    detectedScore = result.totalScore;
    hitCount = numel(result.hitScores);
    rangeCount = numel(result.ringRadii);
    
    % 3. Save the annotated image
    % We construct the full path specifically to avoid 'Filename must be supplied' errors
    outputPath = fullfile(outputDir, [baseName '_annotated' ext]); 
    imwrite(result.annotatedImage, outputPath);

    % 4. Print results to Command Window (Matching your batch style)
    fprintf('\n%-12s %10s %10s %6s %7s\n', 'File', 'Expected', 'Detected', 'Hits', 'Ranges');
    fprintf('%s\n', repmat('-', 1, 55));
    fprintf('%-12s %10s %10.0f %6.0f %7.0f\n', ...
        [baseName ext], 'N/A', detectedScore, hitCount, rangeCount);
    fprintf('%s\n\n', repmat('-', 1, 55));

    % 5. Display the result in a figure
    fig = figure('Name', ['Target Analysis: ' baseName], 'NumberTitle', 'off', 'Color', 'w');
    imshow(result.annotatedImage);
    title(sprintf('File: %s\nScore: %.0f | Hits: %d', [baseName ext], detectedScore, hitCount));
end