function result = paper_target_score_two_cases(inputImage, varargin)

parser = inputParser;
parser.FunctionName = 'paper_target_score_two_cases';
addParameter(parser, 'ShowResult', true, @(v) islogical(v) || isnumeric(v));
addParameter(parser, 'SaveAnnotated', '', @(v) ischar(v) || isstring(v));
addParameter(parser, 'SaveCrop', '', @(v) ischar(v) || isstring(v));
addParameter(parser, 'RingCount', 5, @(v) isnumeric(v) && isscalar(v) && v >= 2);
addParameter(parser, 'ScoreValues', [], @(v) isempty(v) || isnumeric(v));
addParameter(parser, 'MaxBullets', inf, @(v) isnumeric(v) && isscalar(v) && v >= 0);
addParameter(parser, 'ScoreBy', 'touch', @(v) ischar(v) || isstring(v));
parse(parser, varargin{:});

showResult = logical(parser.Results.ShowResult);
saveAnnotated = char(parser.Results.SaveAnnotated);
saveCrop = char(parser.Results.SaveCrop);
ringCount = round(double(parser.Results.RingCount));
scoreValues = parser.Results.ScoreValues;
maxBullets = double(parser.Results.MaxBullets);
scoreBy = lower(char(parser.Results.ScoreBy));

if ~ismember(scoreBy, {'touch', 'center'})
    error('paper_target_score_two_cases:BadScoreBy', ...
        'ScoreBy must be "touch" or "center".');
end

rgb = readTargetImage(inputImage);
rgbDouble = im2double(rgb);

[targetCenter, redRadius, centerDebug] = findRedCentre(rgbDouble);
[outerRadius, outerDebug] = findOuterPrintedCircle(rgbDouble, targetCenter);
[cropRGB, targetMask, cropInfo] = cropCircularTarget(rgb, targetCenter, outerRadius);

[ringRadii, ringDebug] = findPaperRings(cropRGB, cropInfo.Center, cropInfo.OuterRadius, ...
    redRadius, ringCount);

[hitMask, hitStats, hitDebug] = findPaperBullets(cropRGB, targetMask, cropInfo.Center, ...
    cropInfo.OuterRadius, ringRadii);
hitStats = keepLargestHits(hitStats, maxBullets, cropInfo.Center);
hitMask = maskFromStats(size(targetMask), hitStats);

[hitCenters, hitBestRadii, hitRingIndex, hitScores, rangeScores, totalScore] = ...
    scoreBullets(hitStats, cropInfo.Center, ringRadii, scoreValues, scoreBy);

annotatedImage = drawResult(cropRGB, targetMask, cropInfo.Center, cropInfo.OuterRadius, ...
    ringRadii, hitCenters, hitScores, totalScore);

if ~isempty(saveCrop)
    makeFolderForFile(saveCrop);
    [~, ~, cropExt] = fileparts(saveCrop);
    if strcmpi(cropExt, '.png')
        imwrite(cropRGB, saveCrop, 'Alpha', double(targetMask));
    else
        imwrite(cropRGB, saveCrop);
    end
end

if ~isempty(saveAnnotated)
    makeFolderForFile(saveAnnotated);
    imwrite(annotatedImage, saveAnnotated);
end

hitTable = table((1:numel(hitScores)).', hitCenters(:, 1), hitCenters(:, 2), ...
    hitBestRadii(:), hitRingIndex(:), hitScores(:), ...
    'VariableNames', {'Bullet', 'CropX', 'CropY', 'BestRadius', 'RingIndex', 'Score'});

result = struct( ...
    'totalScore', totalScore, ...
    'hitCount', numel(hitScores), ...
    'hitScores', reshape(hitScores, 1, []), ...
    'hitCenters', hitCenters, ...
    'hitBestRadii', reshape(hitBestRadii, 1, []), ...
    'hitRingIndex', reshape(hitRingIndex, 1, []), ...
    'ringRadii', reshape(ringRadii, 1, []), ...
    'rangeScores', reshape(rangeScores, 1, []), ...
    'targetCenterOriginal', targetCenter, ...
    'outerRadiusOriginal', outerRadius, ...
    'cropRect', cropInfo.Rect, ...
    'cropRGB', cropRGB, ...
    'targetMask', targetMask, ...
    'hitMask', hitMask, ...
    'annotatedImage', annotatedImage, ...
    'hitTable', hitTable, ...
    'debug', struct('centre', centerDebug, 'outer', outerDebug, ...
        'rings', ringDebug, 'hits', hitDebug));

fprintf('Rings: %d | Bullets: %d | Total score: %d\n', ...
    numel(ringRadii), numel(hitScores), totalScore);
disp(hitTable);

if showResult
    showResultFigure(rgb, cropRGB, targetMask, hitMask, annotatedImage, ...
        targetCenter, outerRadius, cropInfo.Rect);
end
end

function rgb = readTargetImage(inputImage)
if nargin < 1 || isempty(inputImage)
    [fileName, folderName] = uigetfile( ...
        {'*.jpg;*.jpeg;*.png;*.bmp;*.tif;*.tiff', 'Images'; '*.*', 'All files'}, ...
        'Choose paper target image');
    if isequal(fileName, 0)
        error('paper_target_score_two_cases:NoImage', 'No image was selected.');
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

function [center, redRadius, debug] = findRedCentre(rgbDouble)
[imageHeight, imageWidth, ~] = size(rgbDouble);
hsvImage = rgb2hsv(rgbDouble);
hue = hsvImage(:, :, 1);
saturation = hsvImage(:, :, 2);
value = hsvImage(:, :, 3);

redMask = (hue < 0.060 | hue > 0.94) & saturation > 0.30 & value > 0.18;
redMask = imopen(redMask, strel('disk', 1, 0));
redMask = imclose(redMask, strel('disk', 2, 0));
redMask = imfill(redMask, 'holes');
redMask = bwareaopen(redMask, max(5, round(0.0002 * imageHeight * imageWidth)));

stats = regionprops(redMask, 'Area', 'Centroid', 'EquivDiameter', ...
    'Eccentricity', 'Solidity', 'BoundingBox');

if isempty(stats)
    center = [imageWidth imageHeight] / 2;
    redRadius = 0.10 * min(imageWidth, imageHeight);
    debug = struct('Mask', redMask, 'Found', false, 'Scores', []);
    return;
end

imageCenter = [imageWidth imageHeight] / 2;
areas = [stats.Area].';
scores = zeros(numel(stats), 1);
diagLength = hypot(imageWidth, imageHeight);

for index = 1:numel(stats)
    centerPenalty = norm(stats(index).Centroid - imageCenter) / diagLength;
    roundness = max(0, 1 - stats(index).Eccentricity);
    bbox = stats(index).BoundingBox;
    touchesEdge = bbox(1) <= 1 || bbox(2) <= 1 || ...
        bbox(1) + bbox(3) >= imageWidth || bbox(2) + bbox(4) >= imageHeight;

    scores(index) = 0.45 * stats(index).Area / max(areas) + ...
        0.25 * roundness + ...
        0.20 * stats(index).Solidity + ...
        0.10 * (1 - centerPenalty) - ...
        0.40 * touchesEdge;
end

[~, bestIndex] = max(scores);
center = stats(bestIndex).Centroid;
redRadius = stats(bestIndex).EquivDiameter / 2;
debug = struct('Mask', redMask, 'Found', true, 'Scores', scores);
end

function [outerRadius, debug] = findOuterPrintedCircle(rgbDouble, center)
gray = rgb2gray(rgbDouble);
[imageHeight, imageWidth] = size(gray);
maxRadius = floor(distanceToImageBorder(center, imageWidth, imageHeight));

if maxRadius < 15
    outerRadius = maxRadius;
    debug = struct('Radii', [], 'Profile', [], 'Peaks', []);
    return;
end

[radii, profile] = radialEdgeProfile(rgbDouble, center, maxRadius);
minDistance = max(4, round(0.045 * maxRadius));
threshold = median(profile) + 0.45 * robustSpread(profile);
[peakLocations, peakValues] = pickProfilePeaks(profile, minDistance, threshold);
candidateRadii = radii(peakLocations);

outerCandidates = candidateRadii(candidateRadii >= 0.48 * maxRadius);
outerValues = peakValues(candidateRadii >= 0.48 * maxRadius);

if isempty(outerCandidates)
    outerRadius = 0.88 * maxRadius;
else
    strong = outerValues >= 0.35 * max(outerValues);
    outerRadius = max(outerCandidates(strong));
end

outerRadius = min(outerRadius, 0.995 * maxRadius);
debug = struct('Radii', radii, 'Profile', profile, ...
    'PeakRadii', candidateRadii, 'PeakValues', peakValues);
end

function [cropRGB, targetMask, info] = cropCircularTarget(rgb, center, outerRadius)
[imageHeight, imageWidth, ~] = size(rgb);
padding = max(5, round(0.080 * outerRadius));

x1 = max(1, floor(center(1) - outerRadius - padding));
y1 = max(1, floor(center(2) - outerRadius - padding));
x2 = min(imageWidth, ceil(center(1) + outerRadius + padding));
y2 = min(imageHeight, ceil(center(2) + outerRadius + padding));

cropRGB = rgb(y1:y2, x1:x2, :);
centerCrop = center - [x1 y1] + 1;
[cropHeight, cropWidth, ~] = size(cropRGB);
[xGrid, yGrid] = meshgrid(1:cropWidth, 1:cropHeight);
distanceFromCenter = hypot(xGrid - centerCrop(1), yGrid - centerCrop(2));
targetMask = distanceFromCenter <= outerRadius;

for channel = 1:3
    channelData = cropRGB(:, :, channel);
    channelData(~targetMask) = 255;
    cropRGB(:, :, channel) = channelData;
end

info = struct('Center', centerCrop, 'OuterRadius', outerRadius, ...
    'Rect', [x1 y1 x2 - x1 + 1 y2 - y1 + 1]);
end

function [ringRadii, debug] = findPaperRings(cropRGB, center, outerRadius, redRadiusOriginal, ringCount)
rgbDouble = im2double(cropRGB);
[radii, profile] = radialEdgeProfile(rgbDouble, center, floor(outerRadius));

minDistance = max(3, round(0.055 * outerRadius));
threshold = median(profile) + 0.35 * robustSpread(profile);
[peakLocations, peakValues] = pickProfilePeaks(profile, minDistance, threshold);
candidateRadii = radii(peakLocations);
candidateScores = peakValues;

valid = candidateRadii >= 0.070 * outerRadius & candidateRadii <= 1.010 * outerRadius;
candidateRadii = candidateRadii(valid);
candidateScores = candidateScores(valid);

redRadius = estimateRedRadiusInCrop(rgbDouble, center, outerRadius);
if ~isfinite(redRadius) && isfinite(redRadiusOriginal)
    redRadius = redRadiusOriginal;
end

if isfinite(redRadius)
    candidateRadii = [candidateRadii(:); redRadius];
    candidateScores = [candidateScores(:); max([candidateScores(:); profile(:)])];
end

candidateRadii = [candidateRadii(:); outerRadius];
candidateScores = [candidateScores(:); max([candidateScores(:); profile(:)])];
[candidateRadii, candidateScores] = mergeNearbyRadii(candidateRadii, candidateScores, ...
    max(2, round(0.030 * outerRadius)));

ringRadii = chooseFivePaperRings(candidateRadii, candidateScores, outerRadius, ringCount);

debug = struct('Radii', radii, 'Profile', profile, ...
    'CandidateRadii', candidateRadii, 'CandidateScores', candidateScores, ...
    'RedRadius', redRadius);
end

function ringRadii = chooseFivePaperRings(candidateRadii, candidateScores, outerRadius, ringCount)
expected = outerRadius * (1:ringCount).' / ringCount;
ringRadii = expected;

for index = 1:ringCount
    if index == ringCount
        ringRadii(index) = outerRadius;
        continue;
    end

    tolerance = max(4, 0.14 * outerRadius);
    distances = abs(candidateRadii - expected(index));
    nearby = distances <= tolerance;

    if any(nearby)
        localScore = candidateScores ./ (1 + distances);
        localScore(~nearby) = -inf;
        [~, bestIndex] = max(localScore);
        ringRadii(index) = candidateRadii(bestIndex);
    end
end

ringRadii = sort(unique(round(ringRadii(:), 2)), 'ascend');
if numel(ringRadii) < ringCount
    ringRadii = linspace(outerRadius / ringCount, outerRadius, ringCount).';
elseif numel(ringRadii) > ringCount
    ringRadii = ringRadii(end - ringCount + 1:end);
end
ringRadii(end) = outerRadius;
end

function [hitMask, hitStats, debug] = findPaperBullets(cropRGB, targetMask, center, outerRadius, ringRadii)
rgbDouble = im2double(cropRGB);
gray = rgb2gray(rgbDouble);
hsvImage = rgb2hsv(rgbDouble);
hue = hsvImage(:, :, 1);
saturation = hsvImage(:, :, 2);
value = hsvImage(:, :, 3);
[imageHeight, imageWidth] = size(gray);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

lineMask = printedLineMask(size(gray), center, outerRadius, ringRadii);
insideScoreArea = targetMask & distanceFromCenter <= 0.66 * outerRadius;

blackness = 1 - max(rgbDouble, [], 3);
redInk = (hue < 0.060 | hue > 0.94) & saturation > 0.28 & value > 0.16 & ...
    distanceFromCenter <= 0.42 * outerRadius;
localRadius = max(2, round(0.038 * outerRadius));
background = imclose(gray, strel('disk', localRadius, 0));
darkResponse = max(0, background - gray);

safePixels = insideScoreArea & ~lineMask;
if nnz(safePixels) < 20
    safePixels = insideScoreArea;
end

grayThreshold = min(0.34, prctile(gray(safePixels), 7.5));
responseValues = darkResponse(safePixels);
responseThreshold = max(prctile(responseValues, 97.5), ...
    median(responseValues) + 3.0 * robustSpread(responseValues));

darkCore = gray <= 0.40 & blackness >= 0.08;
candidateMask = insideScoreArea & darkCore & ...
    (gray <= grayThreshold | darkResponse >= responseThreshold);

candidateMask(lineMask & darkResponse < 0.10) = false;
candidateMask = imclose(candidateMask, strel('disk', 1, 0));
candidateMask = bwareaopen(candidateMask, max(2, round(0.00010 * pi * outerRadius ^ 2)));

stats = regionprops(candidateMask, 'Area', 'Centroid', 'EquivDiameter', ...
    'Eccentricity', 'Solidity', 'Perimeter', 'BoundingBox', ...
    'PixelIdxList', 'PixelList');

keep = false(numel(stats), 1);
minArea = max(2, round(0.00012 * pi * outerRadius ^ 2));
maxArea = max(12, round(0.028 * pi * outerRadius ^ 2));
minDiameter = max(1.5, 0.010 * outerRadius);
maxDiameter = max(minDiameter + 1, 0.20 * outerRadius);

for index = 1:numel(stats)
    bbox = stats(index).BoundingBox;
    extent = stats(index).Area / max(1, bbox(3) * bbox(4));
    if stats(index).Perimeter > 0
        circularity = 4 * pi * stats(index).Area / (stats(index).Perimeter ^ 2);
    else
        circularity = 0;
    end

    axisRatio = max(bbox(3), bbox(4)) / max(1, min(bbox(3), bbox(4)));
    centerDistanceFraction = norm(stats(index).Centroid - center) / max(outerRadius, eps);
    pixels = stats(index).PixelIdxList;
    darkRatio = nnz(darkCore(pixels)) / max(1, numel(pixels));
    redOverlap = nnz(redInk(pixels)) / max(1, numel(pixels));
    lineOverlap = nnz(lineMask(pixels)) / max(1, numel(pixels));
    meanGray = mean(gray(pixels));
    minGray = min(gray(pixels));

    keep(index) = stats(index).Area >= minArea && stats(index).Area <= maxArea && ...
        stats(index).EquivDiameter >= minDiameter && stats(index).EquivDiameter <= maxDiameter && ...
        stats(index).Solidity >= 0.18 && extent >= 0.10 && circularity >= 0.035 && ...
        axisRatio <= 4.2 && centerDistanceFraction <= 0.86 && darkRatio >= 0.35 && ...
        (lineOverlap <= 0.55 || ...
            (axisRatio <= 2.2 && stats(index).Area <= max(10, 0.005 * pi * outerRadius ^ 2) && meanGray <= 0.28) || ...
            (minGray <= 0.13 && axisRatio <= 2.7)) && ...
        (redOverlap <= 0.45 || ...
            (redOverlap <= 0.65 && minGray <= 0.13 && meanGray <= 0.24));
end

hitStats = stats(keep);
hitMask = maskFromStats(size(candidateMask), hitStats);

debug = struct('CandidateMask', candidateMask, 'LineMask', lineMask, ...
    'DarkCore', darkCore, 'DarkResponse', darkResponse, 'RedInk', redInk, ...
    'GrayThreshold', grayThreshold, 'ResponseThreshold', responseThreshold, ...
    'CandidateCount', numel(stats), 'HitCount', numel(hitStats));
end

function lineMask = printedLineMask(imageSize, center, outerRadius, ringRadii)
imageHeight = imageSize(1);
imageWidth = imageSize(2);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

lineWidth = max(1.0, 0.010 * outerRadius);
lineMask = false(imageHeight, imageWidth);
for index = 1:numel(ringRadii)
    lineMask = lineMask | abs(distanceFromCenter - ringRadii(index)) <= lineWidth;
end

crossWidth = max(1.0, 0.010 * outerRadius);
lineMask = lineMask | ...
    (abs(xGrid - center(1)) <= crossWidth & distanceFromCenter <= outerRadius) | ...
    (abs(yGrid - center(2)) <= crossWidth & distanceFromCenter <= outerRadius);

lineMask = imdilate(lineMask, strel('disk', max(1, round(0.004 * outerRadius)), 0));
end

function [hitCenters, hitBestRadii, hitRingIndex, hitScores, rangeScores, totalScore] = ...
    scoreBullets(hitStats, center, ringRadii, scoreValues, scoreBy)
hitCenters = statsCentroids(hitStats);
ringCount = numel(ringRadii);

if isempty(scoreValues)
    rangeScores = zeros(1, ringCount);
    rangeScores(1) = 400;
    if ringCount >= 2
        rangeScores(2:end) = 350 - 50 * max(0, (1:(ringCount - 1)) - 2);
    end
else
    rangeScores = double(scoreValues(:)).';
    if numel(rangeScores) ~= ringCount
        error('paper_target_score_two_cases:BadScoreValues', ...
            'ScoreValues must contain one value for every ring.');
    end
end

hitScores = zeros(1, numel(hitStats));
hitBestRadii = zeros(1, numel(hitStats));
hitRingIndex = nan(1, numel(hitStats));

for index = 1:numel(hitStats)
    if strcmp(scoreBy, 'center')
        pixels = double(hitStats(index).Centroid);
    else
        pixels = double(hitStats(index).PixelList);
    end

    radialDistance = hypot(pixels(:, 1) - center(1), pixels(:, 2) - center(2));
    bestRadius = min(radialDistance);
    hitBestRadii(index) = bestRadius;

    ringIndex = find(bestRadius <= ringRadii(:), 1, 'first');
    if ~isempty(ringIndex)
        hitRingIndex(index) = ringIndex;
        hitScores(index) = rangeScores(ringIndex);
    end
end

totalScore = sum(hitScores);
end

function annotatedImage = drawResult(cropRGB, targetMask, center, outerRadius, ringRadii, hitCenters, hitScores, totalScore)
annotatedImage = cropRGB;

for channel = 1:3
    channelData = annotatedImage(:, :, channel);
    channelData(~targetMask) = 245;
    annotatedImage(:, :, channel) = channelData;
end

ringLineWidth = max(2, round(0.008 * outerRadius));
drawOuterRadius = max(1, outerRadius - ringLineWidth - 1);
drawRadii = min(ringRadii(:), drawOuterRadius);
ringShapes = [repmat(center(1), numel(drawRadii), 1), ...
    repmat(center(2), numel(drawRadii), 1), 2 * drawRadii(:)];
annotatedImage = insertShape(annotatedImage, 'Circle', ringShapes, ...
    'Color', 'yellow', 'LineWidth', ringLineWidth);

if ~isempty(hitCenters)
    markerRadius = max(4, round(0.035 * outerRadius));
    hitShapes = [hitCenters, repmat(markerRadius, size(hitCenters, 1), 1)];
    annotatedImage = insertShape(annotatedImage, 'Circle', hitShapes, ...
        'Color', 'red', 'LineWidth', max(2, round(0.008 * outerRadius)));

    fontSize = max(10, round(0.045 * outerRadius));
    for index = 1:size(hitCenters, 1)
        annotatedImage = insertText(annotatedImage, hitCenters(index, :) + [markerRadius 0], ...
            sprintf('%d', hitScores(index)), 'FontSize', fontSize, ...
            'BoxColor', 'black', 'BoxOpacity', 0.60, 'TextColor', 'white');
    end
end

bannerText = sprintf('Score: %d   Bullets: %d   Rings: %d', ...
    totalScore, numel(hitScores), numel(ringRadii));
annotatedImage = insertText(annotatedImage, [8 8], bannerText, ...
    'FontSize', max(11, round(0.045 * outerRadius)), ...
    'BoxColor', 'black', 'BoxOpacity', 0.72, 'TextColor', 'white');
end

function showResultFigure(originalRGB, cropRGB, targetMask, hitMask, annotatedImage, center, radius, cropRect)
figure('Name', 'Paper Target Score', 'Color', 'w', 'NumberTitle', 'off');
tiledlayout(1, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
imshow(originalRGB);
hold on;
viscircles(center, radius, 'Color', 'c', 'LineWidth', 1.5);
rectangle('Position', cropRect, 'EdgeColor', 'y', 'LineWidth', 1.2, 'LineStyle', '--');
title('Target');

nexttile;
h = imshow(cropRGB);
set(h, 'AlphaData', double(targetMask));
title('Crop');

nexttile;
imshow(hitMask);
title('Bullets');

nexttile;
imshow(annotatedImage);
title('Score');
end

function [radii, profile] = radialEdgeProfile(rgbDouble, center, maxRadius)
gray = rgb2gray(rgbDouble);
hsvImage = rgb2hsv(rgbDouble);
saturation = hsvImage(:, :, 2);

graySmooth = imgaussfilt(gray, 0.75);
satSmooth = imgaussfilt(saturation, 0.75);
edgeMap = edge(graySmooth, 'canny');
gradientSupport = normalizeImage(imgradient(graySmooth)) + ...
    0.55 * normalizeImage(imgradient(satSmooth)) + 0.35 * single(edgeMap);
gradientSupport = normalizeImage(gradientSupport);

radii = (max(3, round(0.035 * maxRadius)):maxRadius).';
angles = linspace(0, 2 * pi, 721);
angles(end) = [];
cosAngles = cos(angles);
sinAngles = sin(angles);
profile = zeros(numel(radii), 1);

for index = 1:numel(radii)
    currentRadius = radii(index);
    xSamples = center(1) + currentRadius * cosAngles;
    ySamples = center(2) + currentRadius * sinAngles;
    profile(index) = mean(interp2(gradientSupport, xSamples, ySamples, 'linear', 0));
end

profile = smoothVector(profile, max(3, round(0.032 * maxRadius)));
end

function redRadius = estimateRedRadiusInCrop(rgbDouble, center, outerRadius)
hsvImage = rgb2hsv(rgbDouble);
hue = hsvImage(:, :, 1);
saturation = hsvImage(:, :, 2);
value = hsvImage(:, :, 3);
[imageHeight, imageWidth] = size(hue);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

redMask = (hue < 0.060 | hue > 0.94) & saturation > 0.30 & value > 0.18 & ...
    distanceFromCenter <= 0.40 * outerRadius;
redMask = imopen(redMask, strel('disk', 1, 0));
redMask = imclose(redMask, strel('disk', 2, 0));
redMask = imfill(redMask, 'holes');
redMask = bwareaopen(redMask, 4);

stats = regionprops(redMask, 'Area', 'Centroid', 'EquivDiameter');
redRadius = NaN;
if isempty(stats)
    return;
end

scores = zeros(numel(stats), 1);
for index = 1:numel(stats)
    centerPenalty = norm(stats(index).Centroid - center) / max(outerRadius, eps);
    scores(index) = stats(index).Area / (0.15 + centerPenalty);
end

[~, bestIndex] = max(scores);
redRadius = stats(bestIndex).EquivDiameter / 2;
end

function [peakLocations, peakValues] = pickProfilePeaks(profile, minDistance, threshold)
profile = double(profile(:));
if numel(profile) < 3
    peakLocations = [];
    peakValues = [];
    return;
end

isLocalPeak = false(size(profile));
isLocalPeak(2:end - 1) = profile(2:end - 1) >= profile(1:end - 2) & ...
    profile(2:end - 1) > profile(3:end);
candidateLocations = find(isLocalPeak & profile >= threshold);

if isempty(candidateLocations)
    peakLocations = [];
    peakValues = [];
    return;
end

[~, order] = sort(profile(candidateLocations), 'descend');
selectedLocations = [];
for orderIndex = order(:).'
    location = candidateLocations(orderIndex);
    if isempty(selectedLocations) || all(abs(selectedLocations - location) >= minDistance)
        selectedLocations(end + 1) = location; %#ok<AGROW>
    end
end

peakLocations = sort(selectedLocations(:));
peakValues = profile(peakLocations);
end

function [mergedRadii, mergedScores] = mergeNearbyRadii(radii, scores, distanceThreshold)
radii = radii(:);
scores = scores(:);
if isempty(radii)
    mergedRadii = [];
    mergedScores = [];
    return;
end

[radii, order] = sort(radii, 'ascend');
scores = scores(order);
mergedRadii = [];
mergedScores = [];
currentRadii = radii(1);
currentScores = scores(1);

for index = 2:numel(radii)
    if radii(index) - currentRadii(end) <= distanceThreshold
        currentRadii(end + 1, 1) = radii(index); %#ok<AGROW>
        currentScores(end + 1, 1) = scores(index); %#ok<AGROW>
    else
        [~, bestIndex] = max(currentScores);
        mergedRadii(end + 1, 1) = currentRadii(bestIndex); %#ok<AGROW>
        mergedScores(end + 1, 1) = currentScores(bestIndex); %#ok<AGROW>
        currentRadii = radii(index);
        currentScores = scores(index);
    end
end

[~, bestIndex] = max(currentScores);
mergedRadii(end + 1, 1) = currentRadii(bestIndex);
mergedScores(end + 1, 1) = currentScores(bestIndex);
end

function hitStats = keepLargestHits(hitStats, maxBullets, center)
if isempty(hitStats) || isinf(maxBullets)
    return;
end

maxBullets = floor(maxBullets);
if maxBullets <= 0
    hitStats = hitStats([]);
    return;
end

if numel(hitStats) <= maxBullets
    return;
end

score = zeros(numel(hitStats), 1);
for index = 1:numel(hitStats)
    centerBonus = 1 / (1 + norm(hitStats(index).Centroid - center));
    score(index) = hitStats(index).Area + 10 * centerBonus;
end
[~, order] = sort(score, 'descend');
hitStats = hitStats(order(1:maxBullets));
end

function centroids = statsCentroids(stats)
if isempty(stats)
    centroids = zeros(0, 2);
else
    centroids = reshape([stats.Centroid], 2, []).';
end
end

function mask = maskFromStats(maskSize, stats)
mask = false(maskSize);
for index = 1:numel(stats)
    mask(stats(index).PixelIdxList) = true;
end
end

function normalized = normalizeImage(values)
values = single(values);
minValue = min(values(:));
maxValue = max(values(:));
if maxValue <= minValue
    normalized = zeros(size(values), 'single');
else
    normalized = (values - minValue) ./ (maxValue - minValue);
end
end

function values = smoothVector(values, windowSize)
windowSize = max(1, round(windowSize));
if mod(windowSize, 2) == 0
    windowSize = windowSize + 1;
end
if windowSize <= 1
    values = values(:);
else
    kernel = ones(windowSize, 1) / windowSize;
    values = conv(values(:), kernel, 'same');
end
end

function spread = robustSpread(values)
values = double(values(:));
if isempty(values)
    spread = 0.01;
    return;
end
centerValue = median(values);
spread = median(abs(values - centerValue));
if spread <= eps
    spread = std(values);
end
if spread <= eps
    spread = 0.01;
end
end

function distance = distanceToImageBorder(center, imageWidth, imageHeight)
distance = min([center(1) - 1, center(2) - 1, imageWidth - center(1), imageHeight - center(2)]);
distance = max(distance, 0);
end

function makeFolderForFile(filePath)
folder = fileparts(filePath);
if ~isempty(folder) && ~exist(folder, 'dir')
    mkdir(folder);
end
end
