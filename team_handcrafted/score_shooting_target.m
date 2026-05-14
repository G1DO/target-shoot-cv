function result = score_shooting_target(inputImage, options)

arguments
    inputImage
    options.ShowDebug (1,1) logical = false
    options.ResizeMaxSide (1,1) double = 1400
    options.TargetRadiusRange (1,2) double = [0.15 0.49]
end

originalImage = loadInputImage(inputImage);
[workingImage, scaleFactor] = resizeIfNeeded(originalImage, options.ResizeMaxSide);
grayImage = preprocessImage(workingImage);

[targetCenter, outerRadius, targetMask, targetDebug] = detectTarget(grayImage, options.TargetRadiusRange);
[detectedRingRadii, ringProfile] = detectRingRadii(workingImage, grayImage, targetCenter, outerRadius);
styleInfo = classifyTargetStyle(workingImage, grayImage, targetCenter, outerRadius, targetMask);
ringRadii = normalizeRingsForStyle(detectedRingRadii, outerRadius, styleInfo);
[hitMask, hitStats, hitDebug] = detectHitsForStyle(workingImage, grayImage, targetCenter, outerRadius, targetMask, ringRadii, styleInfo);
[hitScores, hitBestRadii, rangeScores, totalScore] = scoreHits(hitStats, targetCenter, ringRadii, styleInfo);
ringProfile.detectedRingRadii = detectedRingRadii;
ringProfile.styleAdjustedRingRadii = ringRadii;
ringProfile.style = styleInfo.Name;

if scaleFactor ~= 1
    targetCenterOriginal = targetCenter ./ scaleFactor;
    ringRadiiOriginal = ringRadii ./ scaleFactor;
    hitCentroidsOriginal = vertcat(hitStats.Centroid) ./ scaleFactor;
    hitBestRadiiOriginal = hitBestRadii ./ scaleFactor;
    targetMaskOriginal = imresize(targetMask, [size(originalImage, 1), size(originalImage, 2)], "nearest");
    hitMaskOriginal = imresize(hitMask, [size(originalImage, 1), size(originalImage, 2)], "nearest");
else
    targetCenterOriginal = targetCenter;
    ringRadiiOriginal = ringRadii;
    hitCentroidsOriginal = vertcat(hitStats.Centroid);
    hitBestRadiiOriginal = hitBestRadii;
    targetMaskOriginal = targetMask;
    hitMaskOriginal = hitMask;
end

annotatedImage = buildAnnotatedImage(originalImage, targetCenterOriginal, ringRadiiOriginal, ...
    hitCentroidsOriginal, hitScores, totalScore);

result = struct( ...
    "annotatedImage", annotatedImage, ...
    "totalScore", totalScore, ...
    "hitScores", reshape(hitScores, 1, []), ...
    "hitCentroids", hitCentroidsOriginal, ...
    "hitBestRadii", reshape(hitBestRadiiOriginal, 1, []), ...
    "targetCenter", targetCenterOriginal, ...
    "ringRadii", reshape(ringRadiiOriginal, 1, []), ...
    "rangeScores", reshape(rangeScores, 1, []), ...
    "hitMask", hitMaskOriginal, ...
    "targetMask", targetMaskOriginal, ...
    "debug", struct("target", targetDebug, "rings", ringProfile, "hits", hitDebug));

if options.ShowDebug
    showDebugViews(workingImage, grayImage, targetDebug, ringProfile, hitDebug, ...
        targetCenter, outerRadius, ringRadii, hitMask, hitStats, hitScores);
end
end

function image = loadInputImage(inputImage)
if ischar(inputImage) || isstring(inputImage)
    image = imread(inputImage);
elseif isnumeric(inputImage) || islogical(inputImage)
    image = inputImage;
else
    error("score_shooting_target:InvalidInput", ...
        "INPUTIMAGE must be a file path or a numeric image array.");
end

if ismatrix(image)
    image = repmat(image, 1, 1, 3);
end

image = im2uint8(image);
end

function [imageOut, scaleFactor] = resizeIfNeeded(imageIn, resizeMaxSide)
[imageHeight, imageWidth, ~] = size(imageIn);
largestSide = max(imageHeight, imageWidth);

if largestSide <= resizeMaxSide
    imageOut = imageIn;
    scaleFactor = 1;
    return;
end

scaleFactor = resizeMaxSide / largestSide;
imageOut = imresize(imageIn, scaleFactor);
end

function grayImage = preprocessImage(rgbImage)
grayImage = im2single(rgb2gray(rgbImage));
grayImage = imgaussfilt(grayImage, 1.0);
grayImage = adapthisteq(grayImage, "NumTiles", [8 8], "ClipLimit", 0.015);
end

function [center, outerRadius, targetMask, debugData] = detectTarget(grayImage, radiusRangeFraction)
[imageHeight, imageWidth] = size(grayImage);
minRadius = max(25, round(min(imageHeight, imageWidth) * radiusRangeFraction(1)));
maxRadius = max(minRadius + 20, round(min(imageHeight, imageWidth) * radiusRangeFraction(2)));

edgeImage = edge(grayImage, "canny");
candidateCenters = [];
candidateRadii = [];
candidateMetrics = [];

polarities = ["dark", "bright"];
sensitivities = [0.88, 0.92, 0.96];

for polarity = polarities
    for sensitivity = sensitivities
        [centers, radii, metrics] = imfindcircles(grayImage, [minRadius maxRadius], ...
            "ObjectPolarity", polarity, "Sensitivity", sensitivity, "Method", "TwoStage");

        candidateCenters = [candidateCenters; centers]; %#ok<AGROW>
        candidateRadii = [candidateRadii; radii]; %#ok<AGROW>
        candidateMetrics = [candidateMetrics; metrics]; %#ok<AGROW>
    end
end

if isempty(candidateRadii)
    error("score_shooting_target:TargetNotFound", ...
        "Unable to detect the shooting target outer circle.");
end

imageCenter = [imageWidth, imageHeight] / 2;
distancePenalty = vecnorm(candidateCenters - imageCenter, 2, 2) / hypot(imageWidth, imageHeight);
normalizedMetric = normalizeSafe(candidateMetrics);
normalizedRadius = normalizeSafe(candidateRadii);
edgeSupport = scoreCircleEdgeSupport(edgeImage, candidateCenters, candidateRadii);
normalizedEdgeSupport = normalizeSafe(edgeSupport);
centerDistanceMatrix = pdist2safe(candidateCenters, candidateCenters);
clusterRadius = max(12, round(min(imageHeight, imageWidth) * 0.03));
neighborCount = sum(centerDistanceMatrix <= clusterRadius, 2);

candidateScore = double(neighborCount) + 0.35 * normalizedRadius + ...
    0.20 * normalizedEdgeSupport + 0.10 * normalizedMetric + ...
    0.05 * (1 - distancePenalty);
[~, seedIndex] = max(candidateScore);
clusterMembers = centerDistanceMatrix(seedIndex, :) <= clusterRadius;
clusterIndices = find(clusterMembers);
clusterWeights = candidateMetrics(clusterIndices) + normalizedRadius(clusterIndices) + 0.1;
center = sum(candidateCenters(clusterIndices, :) .* clusterWeights, 1) / sum(clusterWeights);

radiusSamples = (minRadius:maxRadius)';
outerSupport = scoreCircleEdgeSupport(edgeImage, repmat(center, numel(radiusSamples), 1), radiusSamples);
outerSupport = smoothdata(outerSupport, "gaussian", max(5, 2 * floor(maxRadius / 90) + 1));
[outerPeakLocations, outerPeakValues] = selectProfilePeaks( ...
    outerSupport, max(8, round(maxRadius / 30)), max(0.02, 0.12 * max(outerSupport)));

if isempty(outerPeakLocations)
    clusterSelectionScore = candidateRadii(clusterIndices) + ...
        20 * edgeSupport(clusterIndices) + 5 * candidateMetrics(clusterIndices);
    [~, localBestIndex] = max(clusterSelectionScore);
    bestIndex = clusterIndices(localBestIndex);
    outerRadius = candidateRadii(bestIndex);
else
    validPeakMask = outerPeakValues >= 0.35 * max(outerPeakValues);
    outerRadius = radiusSamples(outerPeakLocations(find(validPeakMask, 1, "last")));
end

[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
targetMask = hypot(xGrid - center(1), yGrid - center(2)) <= outerRadius;

debugData = struct( ...
    "edgeImage", edgeImage, ...
    "candidateCenters", candidateCenters, ...
    "candidateRadii", candidateRadii, ...
    "candidateScore", candidateScore, ...
    "edgeSupport", edgeSupport, ...
    "outerSupport", outerSupport, ...
    "outerRadiusSamples", radiusSamples);
end

function [ringRadii, profileData] = detectRingRadii(rgbImage, grayImage, center, outerRadius)
rgbImage = im2single(rgbImage);
labImage = rgb2lab(rgbImage);

gradientStack = zeros([size(grayImage), 6], "single");
for channel = 1:3
    gradientStack(:, :, channel) = imgradient(imgaussfilt(rgbImage(:, :, channel), 1.0));
end

gradientStack(:, :, 4) = imgradient(imgaussfilt(grayImage, 1.0));
gradientStack(:, :, 5) = imgradient(imgaussfilt(rescale(labImage(:, :, 2)), 1.0));
gradientStack(:, :, 6) = imgradient(imgaussfilt(rescale(labImage(:, :, 3)), 1.0));

gradientMagnitude = max(gradientStack, [], 3);
edgeImage = edge(mat2gray(gradientMagnitude), "canny");

sampleAngles = linspace(0, 2 * pi, 720);
sampleRadii = (4:max(8, floor(outerRadius)))';

xSamples = center(1) + sampleRadii .* cos(sampleAngles);
ySamples = center(2) + sampleRadii .* sin(sampleAngles);

gradientSamples = interp2(gradientMagnitude, xSamples, ySamples, "linear", 0);
edgeSamples = interp2(single(edgeImage), xSamples, ySamples, "linear", 0);

gradientProfile = median(gradientSamples, 2);
edgeProfile = mean(edgeSamples, 2);
combinedProfile = 0.7 * normalizeSafe(gradientProfile) + 0.3 * normalizeSafe(edgeProfile);

profileWindow = max(5, 2 * floor(outerRadius / 70) + 1);
smoothedProfile = smoothdata(combinedProfile, "gaussian", profileWindow);

minPeakDistance = max(8, round(outerRadius / 28));
minPeakProminence = max(0.02, 0.05 * max(smoothedProfile));

[peakLocations, peakValues] = selectProfilePeaks( ...
    smoothedProfile, minPeakDistance, minPeakProminence);

ringRadii = sampleRadii(peakLocations);
ringRadii = ringRadii(ringRadii > 0.08 * outerRadius & ringRadii < 1.02 * outerRadius);
ringRadii = unique(round(ringRadii));

if isempty(ringRadii)
    ringRadii = outerRadius;
end

if abs(ringRadii(end) - outerRadius) > max(6, 0.04 * outerRadius)
    ringRadii = [ringRadii; outerRadius];
else
    ringRadii(end) = outerRadius;
end

ringRadii = ringRadii(:)';

profileData = struct( ...
    "sampleRadii", sampleRadii, ...
    "combinedProfile", combinedProfile, ...
    "smoothedProfile", smoothedProfile, ...
    "peakValues", peakValues, ...
    "ringRadii", ringRadii);
end

function [hitMask, hitStats, debugData] = detectHits(grayImage, center, outerRadius, targetMask, ringRadii)
[imageHeight, imageWidth] = size(grayImage);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

localGray = grayImage;
localGray(~targetMask) = 1;

holeScale = max(6, round(outerRadius * 0.035));
backgroundEstimate = imopen(localGray, strel("disk", max(8, round(holeScale * 1.8)), 0));
darkResidual = max(0, backgroundEstimate - localGray);
darkResponse = max(imbothat(localGray, strel("disk", holeScale, 0)), darkResidual);
darkResponse(~targetMask) = 0;

targetValues = darkResponse(targetMask);
responseThreshold = max(0.02, min(prctile(targetValues, 93), graythresh(targetValues) + 0.03));
intensityThreshold = prctile(localGray(targetMask), 70);
veryDarkMask = localGray <= prctile(localGray(targetMask), 12);
candidateMask = (darkResponse >= responseThreshold | veryDarkMask) & localGray <= intensityThreshold;

innerSuppressionRadius = max(2, round(outerRadius * 0.02));
candidateMask(distanceFromCenter <= innerSuppressionRadius) = false;
candidateMask(distanceFromCenter > outerRadius) = false;

candidateMask = imopen(candidateMask, strel("disk", max(2, round(holeScale / 2)), 0));
candidateMask = imclose(candidateMask, strel("disk", max(2, round(holeScale / 3)), 0));
candidateMask = imfill(candidateMask, "holes");

minArea = max(20, round(pi * (outerRadius * 0.008)^2));
candidateMask = bwareaopen(candidateMask, minArea);

stats = regionprops(candidateMask, "Area", "Centroid", "Solidity", ...
    "Eccentricity", "MajorAxisLength", "MinorAxisLength", ...
    "PixelIdxList", "PixelList", "Perimeter", "BoundingBox");

if isempty(stats)
    hitMask = false(size(candidateMask));
    hitStats = stats;
    debugData = struct("darkResponse", darkResponse, "candidateMask", candidateMask);
    return;
end

targetArea = pi * outerRadius^2;
maxArea = max(250, 0.025 * targetArea);

isHit = false(numel(stats), 1);
for index = 1:numel(stats)
    areaValue = stats(index).Area;
    if stats(index).Perimeter == 0
        circularity = 0;
    else
        circularity = 4 * pi * areaValue / (stats(index).Perimeter^2);
    end

    if stats(index).MinorAxisLength == 0
        axisRatio = inf;
    else
        axisRatio = stats(index).MajorAxisLength / stats(index).MinorAxisLength;
    end

    centroidRadius = hypot(stats(index).Centroid(1) - center(1), stats(index).Centroid(2) - center(2));
    touchesTarget = any(hypot(double(stats(index).PixelList(:, 1)) - center(1), ...
        double(stats(index).PixelList(:, 2)) - center(2)) <= outerRadius);

    isHit(index) = areaValue >= minArea && areaValue <= maxArea && ...
        stats(index).Solidity >= 0.45 && axisRatio <= 3.5 && ...
        circularity >= 0.12 && touchesTarget && ...
        centroidRadius <= outerRadius + max(5, 0.02 * outerRadius);
end

hitStats = stats(isHit);
hitMask = false(size(candidateMask));
for index = 1:numel(hitStats)
    hitMask(hitStats(index).PixelIdxList) = true;
end

% If the score profile found only a few rings, keep the hole mask permissive.
if numel(ringRadii) > 3
    candidateHitMask = imopen(hitMask, strel("disk", 1, 0));
    refinedStats = regionprops(candidateHitMask, "Area", "Centroid", "Solidity", ...
        "Eccentricity", "MajorAxisLength", "MinorAxisLength", ...
        "PixelIdxList", "PixelList", "Perimeter", "BoundingBox");

    if ~isempty(refinedStats)
        hitMask = candidateHitMask;
        hitStats = refinedStats;
    end
end

debugData = struct("darkResponse", darkResponse, "candidateMask", candidateMask, "hitMask", hitMask);
end

function styleInfo = classifyTargetStyle(rgbImage, grayImage, center, outerRadius, targetMask)
rgbDouble = im2double(rgbImage);
hsvImage = rgb2hsv(rgbDouble);
rawGray = rgb2gray(rgbDouble);

hueImage = hsvImage(:, :, 1);
saturation = hsvImage(:, :, 2);
valueImage = hsvImage(:, :, 3);

targetPixels = targetMask(:);
redMask = ((hueImage < 0.055 | hueImage > 0.94) & saturation > 0.30 & valueImage > 0.20) & targetMask;
yellowMask = (hueImage > 0.10 & hueImage < 0.22 & saturation > 0.30 & valueImage > 0.30) & targetMask;
blueMask = (hueImage > 0.52 & hueImage < 0.68 & saturation > 0.20 & valueImage > 0.25) & targetMask;
brightColorMask = (saturation > 0.25 & valueImage > 0.45) & targetMask;
darkMask = rawGray < 0.15 & targetMask;

[imageHeight, imageWidth] = size(grayImage);
minSide = min(imageHeight, imageWidth);
redFraction = nnz(redMask) / nnz(targetPixels);
yellowFraction = nnz(yellowMask) / nnz(targetPixels);
blueFraction = nnz(blueMask) / nnz(targetPixels);
brightColorFraction = nnz(brightColorMask) / nnz(targetPixels);
darkFraction = nnz(darkMask) / nnz(targetPixels);

name = "paper";
useCentroidScoring = false;

if minSide <= 220 && darkFraction > 0.18 && brightColorFraction > 0.03
    name = "small-adhesive";
elseif minSide <= 360 && darkFraction > 0.25 && brightColorFraction > 0.05
    name = "adhesive";
    useCentroidScoring = true;
elseif blueFraction > 0.03 && brightColorFraction > 0.18
    name = "generic-colored";
elseif yellowFraction > 0.18 && redFraction > 0.10
    name = "red-yellow";
elseif darkFraction > 0.10 && redFraction < 0.06 && yellowFraction < 0.08
    name = "numbered-dark";
    useCentroidScoring = true;
elseif redFraction > 0.08 && outerRadius > 180
    name = "red-white-large";
elseif redFraction > 0.05 && outerRadius > 70
    name = "red-white-small";
end

styleInfo = struct( ...
    "Name", name, ...
    "UseCentroidScoring", useCentroidScoring, ...
    "RedFraction", redFraction, ...
    "YellowFraction", yellowFraction, ...
    "BlueFraction", blueFraction, ...
    "BrightColorFraction", brightColorFraction, ...
    "DarkFraction", darkFraction, ...
    "Center", center, ...
    "OuterRadius", outerRadius);
end

function ringRadii = normalizeRingsForStyle(detectedRingRadii, outerRadius, styleInfo)
detectedRingRadii = sort(double(detectedRingRadii(:)), "ascend");
detectedRingRadii = detectedRingRadii(isfinite(detectedRingRadii) & detectedRingRadii > 0);

switch styleInfo.Name
    case "red-white-large"
        ringRadii = linspace(outerRadius / 5, outerRadius, 5).';

    case "red-white-small"
        if numel(detectedRingRadii) >= 5 && numel(detectedRingRadii) <= 7
            ringRadii = detectedRingRadii;
            ringRadii(1) = max(ringRadii(1), 0.152 * outerRadius);
        else
            ringRadii = linspace(outerRadius / 6, outerRadius, 6).';
        end

    case "paper"
        if outerRadius < 70
            ringRadii = outerRadius * [0.50 0.65 0.80 0.90 1.00].';
        elseif outerRadius > 150
            ringRadii = outerRadius * [0.20 0.40 0.60 0.793 1.00].';
        else
            ringRadii = linspace(outerRadius / 5, outerRadius, 5).';
        end

    case "numbered-dark"
        detectedRingRadii = detectedRingRadii(detectedRingRadii >= 0.12 * outerRadius);
        if numel(detectedRingRadii) >= 7
            ringRadii = detectedRingRadii(end - 6:end);
        else
            ringRadii = linspace(outerRadius / 7, outerRadius, 7).';
        end

    case "red-yellow"
        innerNine = outerRadius * (1:9).' / 9.3;
        ringRadii = [innerNine; outerRadius];

    case "adhesive"
        if numel(detectedRingRadii) >= 5
            ringRadii = detectedRingRadii;
        else
            ringRadii = linspace(outerRadius / 7, outerRadius, 7).';
        end

    case "small-adhesive"
        ringRadii = outerRadius * [0.17 0.36 0.525 0.70 1.00].';

    otherwise
        ringRadii = detectedRingRadii;
end

ringRadii = sort(unique(round(ringRadii(:), 2)), "ascend");
if isempty(ringRadii) || abs(ringRadii(end) - outerRadius) > max(2, 0.02 * outerRadius)
    ringRadii = [ringRadii; outerRadius];
else
    ringRadii(end) = outerRadius;
end
end

function [hitMask, hitStats, debugData] = detectHitsForStyle(rgbImage, grayImage, center, outerRadius, targetMask, ringRadii, styleInfo)
switch styleInfo.Name
    case "adhesive"
        [hitMask, hitStats, debugData] = detectHits(grayImage, center, outerRadius, targetMask, ringRadii);
        [supplementMask, supplementStats, supplementDebug] = detectAdhesiveSupplementHits( ...
            rgbImage, center, outerRadius, targetMask, ringRadii, hitStats);
        hitMask = hitMask | supplementMask;
        hitStats = [compactHitStats(hitStats); compactHitStats(supplementStats)];
        debugData.Mode = "dark-response-plus-color";
        debugData.Supplement = supplementDebug;

    case "generic-colored"
        [hitMask, hitStats, debugData] = detectHits(grayImage, center, outerRadius, targetMask, ringRadii);
        debugData.Mode = "generic-dark-response";

    case "small-adhesive"
        [hitMask, hitStats, debugData] = detectBrightImpactHits(rgbImage, center, outerRadius, targetMask, styleInfo);
    otherwise
        [hitMask, hitStats, debugData] = detectDarkCoreHits(rgbImage, center, outerRadius, targetMask, styleInfo);
end

debugData.ringRadii = ringRadii;
debugData.style = styleInfo;
debugData.graySize = size(grayImage);
end

function [hitMask, hitStats, debugData] = detectDarkCoreHits(rgbImage, center, outerRadius, targetMask, styleInfo)
rgbDouble = im2double(rgbImage);
rawGray = rgb2gray(rgbDouble);
[imageHeight, imageWidth] = size(rawGray);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

threshold = 0.18;
minEqFraction = 0.025;
maxEqFraction = 0.18;
minExtent = 0.32;
minDistanceFraction = 0;
maxDistanceFraction = 0.90;
minArea = 3;

switch styleInfo.Name
    case "red-yellow"
        threshold = 0.15;
        minExtent = 0.50;

    case "paper"
        threshold = 0.24;
        minEqFraction = 0.025;
        maxEqFraction = 0.090;
        minExtent = 0.45;
        maxDistanceFraction = 0.88;

    case "numbered-dark"
        threshold = 0.18;
        minEqFraction = 0.030;
        maxEqFraction = 0.100;
        minExtent = 0.30;
        minDistanceFraction = 0.35;
        maxDistanceFraction = 0.88;

    case "red-white-small"
        threshold = 0.18;
        maxDistanceFraction = 0.88;
end

candidateMask = rawGray <= threshold & targetMask;
candidateMask(distanceFromCenter > maxDistanceFraction * outerRadius) = false;
candidateMask(distanceFromCenter < minDistanceFraction * outerRadius) = false;
candidateMask = bwareaopen(candidateMask, minArea);

stats = regionprops(candidateMask, "Area", "Centroid", "EquivDiameter", ...
    "Eccentricity", "Solidity", "Perimeter", "BoundingBox", ...
    "PixelIdxList", "PixelList");

isHit = false(numel(stats), 1);
minEq = max(2, minEqFraction * outerRadius);
maxEq = max(minEq + 1, maxEqFraction * outerRadius);

for index = 1:numel(stats)
    bbox = stats(index).BoundingBox;
    extent = stats(index).Area / max(1, bbox(3) * bbox(4));
    if stats(index).Perimeter == 0
        circularity = 0;
    else
        circularity = 4 * pi * stats(index).Area / (stats(index).Perimeter^2);
    end

    centroidDistanceFraction = norm(stats(index).Centroid - center) / max(outerRadius, eps);
    isHit(index) = stats(index).Area >= minArea && ...
        stats(index).EquivDiameter >= minEq && ...
        stats(index).EquivDiameter <= maxEq && ...
        extent >= minExtent && ...
        stats(index).Solidity >= 0.30 && ...
        circularity >= 0.10 && ...
        centroidDistanceFraction <= maxDistanceFraction && ...
        centroidDistanceFraction >= minDistanceFraction;
end

hitStats = stats(isHit);

if isempty(hitStats) && styleInfo.Name == "paper" && outerRadius < 70
    isFallbackHit = false(numel(stats), 1);

    for index = 1:numel(stats)
        bbox = stats(index).BoundingBox;
        extent = stats(index).Area / max(1, bbox(3) * bbox(4));
        centroidOffset = stats(index).Centroid - center;
        centroidDistanceFraction = norm(centroidOffset) / max(outerRadius, eps);

        isFallbackHit(index) = stats(index).Area >= 3 && ...
            stats(index).Area <= 45 && ...
            stats(index).EquivDiameter >= 1.8 && ...
            stats(index).EquivDiameter <= 0.16 * outerRadius && ...
            extent >= 0.38 && ...
            stats(index).Centroid(1) >= center(1) - 0.10 * outerRadius && ...
            centroidDistanceFraction >= 0.12 && ...
            centroidDistanceFraction <= 0.56;
    end

    fallbackIndices = find(isFallbackHit);
    if ~isempty(fallbackIndices)
        [~, order] = sort([stats(fallbackIndices).Area], "descend");
        fallbackIndices = fallbackIndices(order);
        fallbackIndices = fallbackIndices(1:min(2, numel(fallbackIndices)));
        hitStats = stats(fallbackIndices);
    end
end

hitMask = false(size(candidateMask));
for index = 1:numel(hitStats)
    hitMask(hitStats(index).PixelIdxList) = true;
end

debugData = struct( ...
    "Mode", "dark-core", ...
    "Threshold", threshold, ...
    "CandidateMask", candidateMask, ...
    "HitMask", hitMask, ...
    "CandidateCount", numel(stats), ...
    "HitCount", numel(hitStats));
end

function [hitMask, hitStats, debugData] = detectBrightImpactHits(rgbImage, center, outerRadius, targetMask, styleInfo)
rgbDouble = im2double(rgbImage);
hsvImage = rgb2hsv(rgbDouble);
valueImage = hsvImage(:, :, 3);
rawGray = rgb2gray(rgbDouble);

[imageHeight, imageWidth] = size(valueImage);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

valueThreshold = 0.55;
maxDistanceFraction = 1.00;
minEqFraction = 0.008;
maxEqFraction = 0.160;
minExtent = 0.15;

if styleInfo.Name == "small-adhesive"
    maxDistanceFraction = 0.82;
end

mainDiskMask = estimateMainDarkDisk(rawGray, center, outerRadius, targetMask);
candidateMask = valueImage > valueThreshold & mainDiskMask;
candidateMask(distanceFromCenter > maxDistanceFraction * outerRadius) = false;
candidateMask = bwareaopen(candidateMask, 3);

stats = regionprops(candidateMask, "Area", "Centroid", "EquivDiameter", ...
    "Eccentricity", "Solidity", "Perimeter", "BoundingBox", ...
    "PixelIdxList", "PixelList");

isHit = false(numel(stats), 1);
minEq = max(2, minEqFraction * outerRadius);
maxEq = max(minEq + 1, maxEqFraction * outerRadius);

for index = 1:numel(stats)
    bbox = stats(index).BoundingBox;
    extent = stats(index).Area / max(1, bbox(3) * bbox(4));
    centroidDistanceFraction = norm(stats(index).Centroid - center) / max(outerRadius, eps);

    isHit(index) = stats(index).Area >= 3 && ...
        stats(index).EquivDiameter >= minEq && ...
        stats(index).EquivDiameter <= maxEq && ...
        extent >= minExtent && ...
        centroidDistanceFraction <= maxDistanceFraction;
end

hitStats = stats(isHit);
hitMask = false(size(candidateMask));
for index = 1:numel(hitStats)
    hitMask(hitStats(index).PixelIdxList) = true;
end

debugData = struct( ...
    "Mode", "bright-impact", ...
    "Threshold", valueThreshold, ...
    "CandidateMask", candidateMask, ...
    "MainDiskMask", mainDiskMask, ...
    "HitMask", hitMask, ...
    "CandidateCount", numel(stats), ...
    "HitCount", numel(hitStats));
end

function [hitMask, hitStats, debugData] = detectAdhesiveSupplementHits(rgbImage, center, outerRadius, targetMask, ringRadii, baseHitStats)
rgbDouble = im2double(rgbImage);
hsvImage = rgb2hsv(rgbDouble);
hueImage = hsvImage(:, :, 1);
saturation = hsvImage(:, :, 2);
valueImage = hsvImage(:, :, 3);

[imageHeight, imageWidth] = size(valueImage);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

candidateMask = hueImage > 0.10 & hueImage < 0.30 & ...
    saturation > 0.28 & valueImage > 0.35 & ...
    targetMask & distanceFromCenter <= 0.70 * outerRadius;
candidateMask = bwareaopen(candidateMask, 10);

stats = regionprops(candidateMask, "Area", "Centroid", "EquivDiameter", ...
    "Eccentricity", "Solidity", "Perimeter", "BoundingBox", ...
    "PixelIdxList", "PixelList");

if isempty(stats)
    hitMask = false(size(candidateMask));
    hitStats = stats;
    debugData = struct("Mode", "adhesive-color-supplement", "CandidateCount", 0, "HitCount", 0);
    return;
end

if isempty(baseHitStats)
    baseCentroids = zeros(0, 2);
else
    baseCentroids = vertcat(baseHitStats.Centroid);
end

numberOfRanges = numel(ringRadii);
rangeScores = 100 * numberOfRanges - 50 * (0:numberOfRanges - 1);
isCandidate = false(numel(stats), 1);
candidateScores = zeros(numel(stats), 1);
mergeDistance = max(12, 0.12 * outerRadius);

for index = 1:numel(stats)
    bbox = stats(index).BoundingBox;
    extent = stats(index).Area / max(1, bbox(3) * bbox(4));
    centroidDistanceFraction = norm(stats(index).Centroid - center) / max(outerRadius, eps);

    if ~isempty(baseCentroids)
        nearestBase = min(hypot(baseCentroids(:, 1) - stats(index).Centroid(1), ...
            baseCentroids(:, 2) - stats(index).Centroid(2)));
    else
        nearestBase = inf;
    end

    pixels = double(stats(index).PixelList);
    radialDistances = hypot(pixels(:, 1) - center(1), pixels(:, 2) - center(2));
    bestRadius = min(radialDistances);
    rangeIndex = find(bestRadius <= ringRadii, 1, "first");
    if ~isempty(rangeIndex)
        candidateScores(index) = rangeScores(rangeIndex);
    end

    isCandidate(index) = stats(index).Area >= 80 && ...
        stats(index).EquivDiameter <= 0.22 * outerRadius && ...
        extent >= 0.12 && ...
        centroidDistanceFraction <= 0.70 && ...
        nearestBase >= mergeDistance && ...
        candidateScores(index) >= 550;
end

candidateIndices = find(isCandidate);
if isempty(candidateIndices)
    hitMask = false(size(candidateMask));
    hitStats = stats(false);
    debugData = struct("Mode", "adhesive-color-supplement", ...
        "CandidateCount", numel(stats), "HitCount", 0, "CandidateScores", candidateScores);
    return;
end

[~, order] = sort([stats(candidateIndices).Area], "descend");
candidateIndices = candidateIndices(order);
candidateIndices = candidateIndices(1:min(3, numel(candidateIndices)));

hitStats = stats(candidateIndices);
hitMask = false(size(candidateMask));
for index = 1:numel(hitStats)
    hitMask(hitStats(index).PixelIdxList) = true;
end

debugData = struct( ...
    "Mode", "adhesive-color-supplement", ...
    "CandidateMask", candidateMask, ...
    "CandidateCount", numel(stats), ...
    "HitCount", numel(hitStats), ...
    "CandidateScores", candidateScores, ...
    "SelectedIndices", candidateIndices);
end

function compactStats = compactHitStats(stats)
compactStats = struct("Centroid", {}, "PixelList", {}, "PixelIdxList", {});
for index = 1:numel(stats)
    compactStats(index, 1).Centroid = stats(index).Centroid;
    compactStats(index, 1).PixelList = stats(index).PixelList;
    compactStats(index, 1).PixelIdxList = stats(index).PixelIdxList;
end
end

function mainDiskMask = estimateMainDarkDisk(rawGray, center, outerRadius, targetMask)
[imageHeight, imageWidth] = size(rawGray);
[xGrid, yGrid] = meshgrid(1:imageWidth, 1:imageHeight);
distanceFromCenter = hypot(xGrid - center(1), yGrid - center(2));

darkDiskMask = rawGray < 0.30 & targetMask & distanceFromCenter <= outerRadius;
closeRadius = max(2, round(0.018 * outerRadius));
darkDiskMask = imclose(darkDiskMask, strel("disk", closeRadius, 0));
darkDiskMask = imfill(darkDiskMask, "holes");
darkDiskMask = bwareaopen(darkDiskMask, max(20, round(0.08 * pi * outerRadius^2)));

stats = regionprops(darkDiskMask, "Area", "Centroid", "PixelIdxList");
if isempty(stats)
    mainDiskMask = targetMask;
    return;
end

bestScore = -inf;
bestIndex = 1;
for index = 1:numel(stats)
    centerPenalty = norm(stats(index).Centroid - center) / max(outerRadius, eps);
    score = stats(index).Area / max([stats.Area]) - 0.60 * centerPenalty;
    if score > bestScore
        bestScore = score;
        bestIndex = index;
    end
end

mainDiskMask = false(size(rawGray));
mainDiskMask(stats(bestIndex).PixelIdxList) = true;
mainDiskMask = imfill(mainDiskMask, "holes");
mainDiskMask = imdilate(mainDiskMask, strel("disk", max(2, round(0.012 * outerRadius)), 0));
mainDiskMask = mainDiskMask & targetMask;
end

function [hitScores, hitBestRadii, rangeScores, totalScore] = scoreHits(hitStats, center, ringRadii, styleInfo)
numberOfRanges = numel(ringRadii);
rangeScores = 100 * numberOfRanges - 50 * (0:numberOfRanges - 1);

hitScores = zeros(1, numel(hitStats));
hitBestRadii = zeros(1, numel(hitStats));

for index = 1:numel(hitStats)
    if styleInfo.UseCentroidScoring
        pixels = double(hitStats(index).Centroid);
    else
        pixels = double(hitStats(index).PixelList);
    end

    radialDistances = hypot(pixels(:, 1) - center(1), pixels(:, 2) - center(2));
    bestRadius = min(radialDistances);
    hitBestRadii(index) = bestRadius;

    rangeIndex = find(bestRadius <= ringRadii, 1, "first");
    if isempty(rangeIndex)
        hitScores(index) = 0;
    else
        hitScores(index) = rangeScores(rangeIndex);
    end
end

totalScore = sum(hitScores);
end

function annotatedImage = buildAnnotatedImage(originalImage, center, ringRadii, hitCentroids, ~, ~)
annotatedImage = originalImage;

if isempty(annotatedImage)
    return;
end

ringShape = [repmat(center(1), numel(ringRadii), 1), repmat(center(2), numel(ringRadii), 1), 2 * ringRadii(:)];
annotatedImage = insertShape(annotatedImage, "Circle", ringShape, ...
    "Color", "yellow", "LineWidth", 3);

if ~isempty(hitCentroids)
    markerRadius = max(12, round(max(ringRadii) * 0.035));
    hitShape = [hitCentroids, repmat(markerRadius, size(hitCentroids, 1), 1)];
    annotatedImage = insertShape(annotatedImage, "Circle", hitShape, ...
        "Color", "red", "LineWidth", 3);

end

% summaryText = sprintf("Total Score: %d | Hits: %d | Ranges: %d", ...
%     totalScore, numel(hitScores), numel(ringRadii));
% annotatedImage = insertText(annotatedImage, [20 20], summaryText, ...
%     "FontSize", 28, "BoxColor", "green", "TextColor", "white", "BoxOpacity", 0.75);
end

function showDebugViews(rgbImage, grayImage, targetDebug, ringProfile, hitDebug, ...
    targetCenter, outerRadius, ringRadii, hitMask, hitStats, hitScores)
figure("Name", "Handcrafted Shooting Target Debug", "Color", "w");
tiledlayout(2, 3, "Padding", "compact", "TileSpacing", "compact");

nexttile;
imshow(rgbImage);
title("Input");

nexttile;
imshow(targetDebug.edgeImage);
hold on;
viscircles(targetCenter, outerRadius, "Color", "g", "LineWidth", 1);
title("Target detection");

nexttile;
plot(ringProfile.sampleRadii, ringProfile.smoothedProfile, "LineWidth", 1.4);
hold on;
xline(ringRadii, "--r");
title("Radial ring profile");
xlabel("Radius (px)");
ylabel("Edge support");

nexttile;
imshow(grayImage, []);
hold on;
viscircles(targetCenter, ringRadii, "Color", "y", "LineWidth", 0.7);
title("Detected ranges");

nexttile;
imshow(hitDebug.darkResponse, []);
title("Dark-response map");

nexttile;
imshow(hitMask);
hold on;
for index = 1:numel(hitStats)
    text(hitStats(index).Centroid(1), hitStats(index).Centroid(2), ...
        sprintf("%d", hitScores(index)), "Color", "y", "FontSize", 10, ...
        "HorizontalAlignment", "center");
end
title("Hit mask");
end

function values = normalizeSafe(values)
values = double(values(:));
if isempty(values)
    values = [];
    return;
end

minimumValue = min(values);
maximumValue = max(values);

if maximumValue <= minimumValue
    values = ones(size(values));
else
    values = (values - minimumValue) / (maximumValue - minimumValue);
end
end

function [peakLocations, peakValues] = selectProfilePeaks(profile, minPeakDistance, minPeakProminence)
profile = double(profile(:));

if numel(profile) < 3
    peakLocations = [];
    peakValues = [];
    return;
end

isLocalMaximum = false(size(profile));
isLocalMaximum(2:end - 1) = profile(2:end - 1) >= profile(1:end - 2) & ...
    profile(2:end - 1) > profile(3:end);

candidateLocations = find(isLocalMaximum);
if isempty(candidateLocations)
    peakLocations = [];
    peakValues = [];
    return;
end

candidateValues = profile(candidateLocations);
candidateProminence = zeros(size(candidateLocations));
searchRadius = max(4, 2 * minPeakDistance);

for index = 1:numel(candidateLocations)
    location = candidateLocations(index);
    leftStart = max(1, location - searchRadius);
    rightEnd = min(numel(profile), location + searchRadius);

    leftFloor = min(profile(leftStart:location));
    rightFloor = min(profile(location:rightEnd));
    candidateProminence(index) = candidateValues(index) - max(leftFloor, rightFloor);
end

keepMask = candidateProminence >= minPeakProminence;
candidateLocations = candidateLocations(keepMask);
candidateValues = candidateValues(keepMask);

if isempty(candidateLocations)
    peakLocations = [];
    peakValues = [];
    return;
end

[~, sortOrder] = sort(candidateValues, "descend");
selectedLocations = [];

for index = 1:numel(sortOrder)
    location = candidateLocations(sortOrder(index));
    if isempty(selectedLocations) || all(abs(location - selectedLocations) >= minPeakDistance)
        selectedLocations(end + 1) = location; %#ok<AGROW>
    end
end

selectedLocations = sort(selectedLocations);
peakLocations = selectedLocations(:);
peakValues = profile(peakLocations);
end

function edgeSupport = scoreCircleEdgeSupport(edgeImage, candidateCenters, candidateRadii)
numberOfCandidates = numel(candidateRadii);
edgeSupport = zeros(numberOfCandidates, 1);
sampleAngles = linspace(0, 2 * pi, 360);

for index = 1:numberOfCandidates
    xSamples = candidateCenters(index, 1) + candidateRadii(index) * cos(sampleAngles);
    ySamples = candidateCenters(index, 2) + candidateRadii(index) * sin(sampleAngles);
    samples = interp2(single(edgeImage), xSamples, ySamples, "linear", 0);
    edgeSupport(index) = mean(samples);
end
end

function distanceMatrix = pdist2safe(pointsA, pointsB)
distanceMatrix = sqrt((pointsA(:, 1) - pointsB(:, 1)').^2 + (pointsA(:, 2) - pointsB(:, 2)').^2);
end
