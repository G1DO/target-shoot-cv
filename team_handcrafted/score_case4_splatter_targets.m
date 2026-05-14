function result = score_case4_splatter_targets(inputImage, varargin)

parser = inputParser;
parser.FunctionName = 'score_case4_splatter_targets';
addParameter(parser, 'ShowResult', true, @(v) islogical(v) || isnumeric(v));
addParameter(parser, 'SaveAnnotated', '', @(v) ischar(v) || isstring(v));
addParameter(parser, 'MaxHits', inf, @(v) isnumeric(v) && isscalar(v) && v >= 0);
addParameter(parser, 'ScoreBy', 'touch', @(v) ischar(v) || isstring(v));
parse(parser, varargin{:});

showResult = logical(parser.Results.ShowResult);
saveAnnotated = char(parser.Results.SaveAnnotated);
maxHits = double(parser.Results.MaxHits);
scoreBy = lower(char(parser.Results.ScoreBy));

if ~ismember(scoreBy, {'touch', 'center'})
    error('score_case4_splatter_targets:BadScoreBy', ...
        'ScoreBy must be "touch" or "center".');
end

rgb = readCase4Image(inputImage);
[imageHeight, imageWidth, ~] = size(rgb);
isLargeAdhesive = max(imageHeight, imageWidth) >= 250;

if isLargeAdhesive
    geometry = runCase4Geometry(inputImage, true);

    center = double(geometry.targetCenter);
    ringRadii = double(geometry.ringRadii(:)).';
    ringRadii = forceCase4RingCount(ringRadii, 6);
    targetMask = geometry.targetMask;
    [hitMask, hitStats, hitDebug] = detectLargeAdhesiveSplatterHits( ...
        rgb, center, ringRadii, targetMask);
else
    geometry = runCase4Geometry(inputImage, false);

    center = double(geometry.targetCenter);
    ringRadii = double(geometry.ringRadii(:)).';
    targetMask = geometry.targetMask;
    hitMask = logical(geometry.hitMask);
    hitStats = regionprops(hitMask, 'Area', 'Centroid', 'PixelIdxList', 'PixelList');
    hitDebug = struct('Mode', 'small-target-base-detector');
end

hitStats = limitCase4Hits(hitStats, maxHits, center);
hitMask = maskFromCase4Stats(size(targetMask), hitStats);

[hitCenters, hitBestRadii, hitRingIndex, hitScores, rangeScores, totalScore] = ...
    scoreCase4Hits(hitStats, center, ringRadii, scoreBy);

annotatedImage = annotateCase4(rgb, center, ringRadii, hitCenters, hitScores, ...
    totalScore, targetMask);

if ~isempty(saveAnnotated)
    makeCase4Folder(saveAnnotated);
    imwrite(annotatedImage, saveAnnotated);
end

hitTable = table((1:numel(hitScores)).', hitCenters(:, 1), hitCenters(:, 2), ...
    hitBestRadii(:), hitRingIndex(:), hitScores(:), ...
    'VariableNames', {'Hit', 'X', 'Y', 'BestRadius', 'RingIndex', 'Score'});

result = struct( ...
    'totalScore', totalScore, ...
    'hitCount', numel(hitScores), ...
    'hitScores', reshape(hitScores, 1, []), ...
    'hitCenters', hitCenters, ...
    'hitBestRadii', reshape(hitBestRadii, 1, []), ...
    'hitRingIndex', reshape(hitRingIndex, 1, []), ...
    'ringRadii', reshape(ringRadii, 1, []), ...
    'rangeScores', reshape(rangeScores, 1, []), ...
    'rangeCount', numel(ringRadii), ...
    'targetCenter', center, ...
    'targetMask', targetMask, ...
    'hitMask', hitMask, ...
    'annotatedImage', annotatedImage, ...
    'hitTable', hitTable, ...
    'debug', struct('geometry', geometry.debug, 'hits', hitDebug));

fprintf('Rings: %d | Bullets: %d | Total score: %d\n', ...
    result.rangeCount, result.hitCount, result.totalScore);
disp(hitTable);

if showResult
    figure('Name', 'Case 4 Splatter Target Score', 'Color', 'w', 'NumberTitle', 'off');
    imshow(annotatedImage);
    title(sprintf('Total score: %d | Hits: %d | Rings: %d', ...
        totalScore, numel(hitScores), numel(ringRadii)));
end
end

function geometry = runCase4Geometry(inputImage, isLargeAdhesive)
if isLargeAdhesive
    try
        geometry = score_shooting_target(inputImage, ...
            'ShowResult', false, ...
            'TargetMode', 'adhesive');
        return;
    catch
        geometry = score_shooting_target(inputImage, 'ShowDebug', false);
        return;
    end
end

try
    geometry = score_shooting_target(inputImage, 'ShowResult', false);
catch
    geometry = score_shooting_target(inputImage, 'ShowDebug', false);
end
end

function ringRadii = forceCase4RingCount(ringRadii, ringCount)
ringRadii = sort(double(ringRadii(:)).', 'ascend');
ringRadii = ringRadii(isfinite(ringRadii) & ringRadii > 0);
if isempty(ringRadii)
    error('score_case4_splatter_targets:NoRings', 'Could not detect target rings.');
end

outerRadius = max(ringRadii);
if numel(ringRadii) > ringCount
    while numel(ringRadii) > ringCount
        if numel(ringRadii) == ringCount + 1
            removeIndex = numel(ringRadii) - 1;
        else
            innerCandidates = 2:(numel(ringRadii) - 1);
            if isempty(innerCandidates)
                removeIndex = numel(ringRadii);
            else
                expected = linspace(ringRadii(1), outerRadius, ringCount);
                distancePenalty = zeros(size(innerCandidates));
                for index = 1:numel(innerCandidates)
                    trial = ringRadii;
                    trial(innerCandidates(index)) = [];
                    distancePenalty(index) = sum(abs(trial - expected));
                end
                [~, bestRemoval] = min(distancePenalty);
                removeIndex = innerCandidates(bestRemoval);
            end
        end
        ringRadii(removeIndex) = [];
    end
elseif numel(ringRadii) < ringCount
    ringRadii = linspace(outerRadius / ringCount, outerRadius, ringCount);
end
end

function rgb = readCase4Image(inputImage)
if nargin < 1 || isempty(inputImage)
    [fileName, folderName] = uigetfile( ...
        {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff', 'Images'; '*.*', 'All files'}, ...
        'Choose Case 4 target image');
    if isequal(fileName, 0)
        error('score_case4_splatter_targets:NoImage', 'No image was selected.');
    end
    inputImage = fullfile(folderName, fileName);
end

if ischar(inputImage) || isstring(inputImage)
    rgb = imread(inputImage);
else
    rgb = inputImage;
end

if ndims(rgb) == 2
    rgb = repmat(rgb, 1, 1, 3);
end

rgb = im2uint8(rgb(:, :, 1:3));
end

function [hitMask, hitStats, debug] = detectLargeAdhesiveSplatterHits(rgb, center, ringRadii, targetMask)
rgbDouble = im2double(rgb);
hsvImage = rgb2hsv(rgbDouble);
hue = hsvImage(:, :, 1);
saturation = hsvImage(:, :, 2);
value = hsvImage(:, :, 3);

[imageHeight, imageWidth] = size(value);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
outerRadius = max(ringRadii);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

redInk = ((hue < 0.055 | hue > 0.94) & saturation > 0.30 & value > 0.20);
targetArea = targetMask & distanceFromCenter <= 0.995 * outerRadius;

yellowScore = double(hue > 0.10 & hue < 0.28) .* double(saturation) .* double(value);
yellowScore(~targetArea | redInk) = 0;
yellowScore = mat2gray(yellowScore);

smoothedScore = imgaussfilt(yellowScore, 0.60);
warningState = warning('off', 'images:imfindcircles:warnForSmallRadius');
[candidateCenters, candidateRadii, candidateMetrics] = imfindcircles( ...
    smoothedScore, [3 11], ...
    'ObjectPolarity', 'bright', ...
    'Sensitivity', 0.94, ...
    'EdgeThreshold', 0.03);
warning(warningState);

if isempty(candidateCenters)
    hitMask = false(size(targetMask));
    hitStats = struct('Centroid', {}, 'PixelIdxList', {}, 'PixelList', {}, 'TouchRadius', {});
    debug = struct('Mode', 'large-adhesive-hough', 'CandidateCount', 0, 'HitCount', 0);
    return;
end

insideTarget = hypot(candidateCenters(:, 1) - center(1), ...
    candidateCenters(:, 2) - center(2)) <= outerRadius;
candidateCenters = candidateCenters(insideTarget, :);
candidateRadii = candidateRadii(insideTarget);
candidateMetrics = candidateMetrics(insideTarget);

lineMask = printedCase4LineMask(size(value), center, outerRadius, ringRadii);
keep = false(size(candidateRadii));
localArea = zeros(size(candidateRadii));
localMean = zeros(size(candidateRadii));
localMax = zeros(size(candidateRadii));

for index = 1:numel(candidateRadii)
    localMask = hypot(xGrid - candidateCenters(index, 1), ...
        yGrid - candidateCenters(index, 2)) <= 7;
    localArea(index) = nnz(yellowScore(localMask) > 0.18);
    localMean(index) = mean(yellowScore(localMask));
    localMax(index) = max(yellowScore(localMask));
    lineFraction = nnz(lineMask(localMask)) / max(1, nnz(localMask));

    keep(index) = localArea(index) >= 80 && ...
        localMean(index) >= 0.25 && ...
        localMax(index) >= 0.55 && ...
        lineFraction <= 0.82;
end

candidateCenters = candidateCenters(keep, :);
candidateRadii = candidateRadii(keep);
candidateMetrics = candidateMetrics(keep);
localArea = localArea(keep);
localMean = localMean(keep);
localMax = localMax(keep);

[candidateCenters, candidateRadii, candidateMetrics, selected] = mergeNearbyCase4Candidates( ...
    candidateCenters, candidateRadii, candidateMetrics, 8);
localArea = localArea(selected);
localMean = localMean(selected);
localMax = localMax(selected);

hitStats = struct('Centroid', {}, 'PixelIdxList', {}, 'PixelList', {}, 'TouchRadius', {});
hitMask = false(size(targetMask));

for index = 1:size(candidateCenters, 1)
    localRadius = max(5, min(9, candidateRadii(index) + 3));
    localMask = hypot(xGrid - candidateCenters(index, 1), ...
        yGrid - candidateCenters(index, 2)) <= localRadius & ...
        yellowScore > 0.18 & targetArea;

    if nnz(localMask) < 3
        localMask = hypot(xGrid - candidateCenters(index, 1), ...
            yGrid - candidateCenters(index, 2)) <= max(3, candidateRadii(index));
    end

    pixelIdxList = find(localMask);
    [pixelY, pixelX] = ind2sub(size(targetMask), pixelIdxList);

    hitStats(index, 1).Centroid = candidateCenters(index, :); %#ok<AGROW>
    hitStats(index, 1).PixelIdxList = pixelIdxList; %#ok<AGROW>
    hitStats(index, 1).PixelList = [pixelX pixelY]; %#ok<AGROW>
    hitStats(index, 1).TouchRadius = max(3, candidateRadii(index)); %#ok<AGROW>
    hitMask(pixelIdxList) = true;
end

debug = struct( ...
    'Mode', 'large-adhesive-hough', ...
    'ScoreImage', yellowScore, ...
    'LineMask', lineMask, ...
    'CandidateCount', numel(keep), ...
    'HitCount', numel(hitStats), ...
    'CandidateMetrics', candidateMetrics, ...
    'LocalArea', localArea, ...
    'LocalMean', localMean, ...
    'LocalMax', localMax);
end

function lineMask = printedCase4LineMask(imageSize, center, outerRadius, ringRadii)
imageHeight = imageSize(1);
imageWidth = imageSize(2);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

lineWidth = max(1.4, 0.022 * outerRadius);
lineMask = false(imageHeight, imageWidth);
for index = 1:numel(ringRadii)
    lineMask = lineMask | abs(distanceFromCenter - ringRadii(index)) <= lineWidth;
end

lineMask = lineMask | ...
    ((abs(xGrid - center(1)) <= lineWidth | abs(yGrid - center(2)) <= lineWidth) & ...
    distanceFromCenter <= outerRadius);
end

function [centers, radii, metrics, selectedOriginalIndices] = mergeNearbyCase4Candidates( ...
    centers, radii, metrics, mergeDistance)
selectedOriginalIndices = [];
if isempty(centers)
    return;
end

[~, order] = sort(metrics, 'descend');
used = false(numel(metrics), 1);
kept = [];

for orderIndex = order(:).'
    if used(orderIndex)
        continue;
    end

    distances = hypot(centers(:, 1) - centers(orderIndex, 1), ...
        centers(:, 2) - centers(orderIndex, 2));
    cluster = find(distances <= mergeDistance);
    used(cluster) = true;
    kept(end + 1, 1) = orderIndex; %#ok<AGROW>
end

kept = sort(kept);
centers = centers(kept, :);
radii = radii(kept);
metrics = metrics(kept);
selectedOriginalIndices = kept;
end

function hitStats = limitCase4Hits(hitStats, maxHits, center)
if isempty(hitStats) || isinf(maxHits)
    return;
end

maxHits = floor(maxHits);
if maxHits <= 0
    hitStats = hitStats([]);
    return;
end

if numel(hitStats) <= maxHits
    return;
end

score = zeros(numel(hitStats), 1);
for index = 1:numel(hitStats)
    areaValue = numel(hitStats(index).PixelIdxList);
    centerBonus = 1 / (1 + norm(hitStats(index).Centroid - center));
    score(index) = areaValue + 20 * centerBonus;
end

[~, order] = sort(score, 'descend');
hitStats = hitStats(order(1:maxHits));
end

function [hitCenters, hitBestRadii, hitRingIndex, hitScores, rangeScores, totalScore] = ...
    scoreCase4Hits(hitStats, center, ringRadii, scoreBy)
ringRadii = sort(double(ringRadii(:)).', 'ascend');
ringCount = numel(ringRadii);
rangeScores = 100 * ringCount - 50 * (0:ringCount - 1);

hitCenters = case4Centroids(hitStats);
hitScores = zeros(1, numel(hitStats));
hitBestRadii = zeros(1, numel(hitStats));
hitRingIndex = nan(1, numel(hitStats));
outerRadius = max(ringRadii);
touchTolerance = max(2, 0.020 * outerRadius);

for index = 1:numel(hitStats)
    centerRadius = norm(double(hitStats(index).Centroid) - center);
    touchRadius = centerRadius;

    if ~strcmp(scoreBy, 'center') && isfield(hitStats, 'PixelList') && ~isempty(hitStats(index).PixelList)
        pixels = double(hitStats(index).PixelList);
        radialDistances = hypot(pixels(:, 1) - center(1), pixels(:, 2) - center(2));
        touchRadius = min(radialDistances);
    end

    ringIndex = find(centerRadius <= ringRadii, 1, 'first');
    scoreRadius = centerRadius;

    if ~strcmp(scoreBy, 'center')
        if isempty(ringIndex)
            ringIndex = find(touchRadius <= ringRadii, 1, 'first');
            scoreRadius = touchRadius;
        elseif ringIndex > 1
            innerBoundary = ringRadii(ringIndex - 1);
            touchesInnerBoundary = touchRadius <= innerBoundary;
            centerNearBoundary = centerRadius - innerBoundary <= touchTolerance;
            if touchesInnerBoundary && centerNearBoundary
                ringIndex = ringIndex - 1;
                scoreRadius = touchRadius;
            end
        end
    end

    hitBestRadii(index) = scoreRadius;

    if ~isempty(ringIndex)
        hitRingIndex(index) = ringIndex;
        hitScores(index) = rangeScores(ringIndex);
    end
end

totalScore = sum(hitScores);
end

function annotatedImage = annotateCase4(rgb, center, ringRadii, hitCenters, hitScores, totalScore, targetMask)
annotatedImage = rgb;
outerRadius = max(ringRadii);

if ~isempty(targetMask) && isequal(size(targetMask), [size(rgb, 1) size(rgb, 2)])
    for channel = 1:3
        channelData = annotatedImage(:, :, channel);
        outsidePixels = channelData(~targetMask);
        channelData(~targetMask) = uint8(0.65 * double(outsidePixels) + 0.35 * 255);
        annotatedImage(:, :, channel) = channelData;
    end
end

ringShapes = [repmat(center(1), numel(ringRadii), 1), ...
    repmat(center(2), numel(ringRadii), 1), 2 * ringRadii(:)];
annotatedImage = insertShape(annotatedImage, 'Circle', ringShapes, ...
    'Color', 'yellow', 'LineWidth', max(2, round(0.010 * outerRadius)));

if ~isempty(hitCenters)
    markerRadius = max(4, round(0.035 * outerRadius));
    hitShapes = [hitCenters, repmat(markerRadius, size(hitCenters, 1), 1)];
    annotatedImage = insertShape(annotatedImage, 'Circle', hitShapes, ...
        'Color', 'red', 'LineWidth', max(2, round(0.012 * outerRadius)));

    fontSize = max(9, round(0.040 * outerRadius));
    for index = 1:size(hitCenters, 1)
        annotatedImage = insertText(annotatedImage, hitCenters(index, :) + [markerRadius 0], ...
            sprintf('%d', hitScores(index)), ...
            'FontSize', fontSize, ...
            'BoxColor', 'black', ...
            'BoxOpacity', 0.62, ...
            'TextColor', 'white');
    end
end

bannerText = sprintf('Score: %d   Bullets: %d   Rings: %d', ...
    totalScore, numel(hitScores), numel(ringRadii));
annotatedImage = insertText(annotatedImage, [8 8], bannerText, ...
    'FontSize', max(10, round(0.045 * outerRadius)), ...
    'BoxColor', 'black', ...
    'BoxOpacity', 0.72, ...
    'TextColor', 'white');
end

function centroids = case4Centroids(stats)
if isempty(stats)
    centroids = zeros(0, 2);
else
    centroids = reshape([stats.Centroid], 2, []).';
end
end

function mask = maskFromCase4Stats(maskSize, stats)
mask = false(maskSize);
for index = 1:numel(stats)
    mask(stats(index).PixelIdxList) = true;
end
end

function makeCase4Folder(filePath)
folder = fileparts(filePath);
if ~isempty(folder) && ~exist(folder, 'dir')
    mkdir(folder);
end
end
