function [hitCount, totalScore, perTarget] = scoreFromDetections(bboxes, labels, scores)
% scoreFromDetections  Convert detector boxes to shooting-target score.
%
% Plan v6.2 §4 / plan_v5 §5.8 (✅ Verified): score arithmetic is pure
% MATLAB post-processing after YOLOv2 detection. Labelling guide §3.3
% (✅ Verified) defines ring boxes as nested discs, so sorting by area
% recovers the inward-to-outward score order. scores is retained for the
% required signature and future tie-breaking, but the docx scoring rule uses
% geometry, not confidence.

    if nargin < 3
        scores = [];
    end
    %#ok<NASGU>

    if isempty(bboxes)
        bboxes = zeros(0, 4);
    end
    labelText = string(labels);
    labelText = labelText(:);

    isBullseye = labelText == "bullseye";
    isRing = labelText == "ring";
    isHit = labelText == "hit";

    bullseyes = double(bboxes(isBullseye, :));
    rings = double(bboxes(isRing, :));
    hits = double(bboxes(isHit, :));
    hitCount = size(hits, 1);

    if isempty(bullseyes)
        % Silhouette branch (✅ plan_v5 §5.8): if no bullseye is detected,
        % score is the hit count. This avoids inventing ranges for silhouettes.
        totalScore = hitCount;
        perTarget = struct([]);
        return;
    end

    bsCentroids = boxCentres(bullseyes);
    ringTarget = assignToNearestBullseye(rings, bsCentroids);
    hitTarget = assignToNearestBullseye(hits, bsCentroids);

    totalScore = 0;
    perTarget = repmat(struct('bullseye', [], 'N', 0, ...
        'hitCount', 0, 'score', 0), size(bullseyes, 1), 1);

    for t = 1:size(bullseyes, 1)
        myBs = bullseyes(t, :);
        myRings = rings(ringTarget == t, :);
        myHits = hits(hitTarget == t, :);

        N = 1 + size(myRings, 1);
        bullseyeValue = 100 * N;

        ringAreas = myRings(:, 3) .* myRings(:, 4);
        [~, ringOrder] = sort(ringAreas, 'ascend');
        myRings = myRings(ringOrder, :);
        ringValues = bullseyeValue - 50 * (1:size(myRings, 1))';

        zones = [myBs; myRings];
        zoneValues = [bullseyeValue; ringValues];
        zoneAreas = zones(:, 3) .* zones(:, 4);
        [~, zoneOrder] = sort(zoneAreas, 'ascend');
        zones = zones(zoneOrder, :);
        zoneValues = zoneValues(zoneOrder);

        targetScore = 0;
        for h = 1:size(myHits, 1)
            hitCentre = boxCentres(myHits(h, :));
            for z = 1:size(zones, 1)
                if pointInsideBox(hitCentre, zones(z, :))
                    % Smallest enclosing zone wins (✅ docx best-score rule).
                    targetScore = targetScore + zoneValues(z);
                    break;
                end
            end
        end

        totalScore = totalScore + targetScore;
        perTarget(t).bullseye = myBs;
        perTarget(t).N = N;
        perTarget(t).hitCount = size(myHits, 1);
        perTarget(t).score = targetScore;
    end
end

function centres = boxCentres(boxes)
    if isempty(boxes)
        centres = zeros(0, 2);
        return;
    end
    centres = boxes(:, 1:2) + boxes(:, 3:4) ./ 2;
end

function targetIdx = assignToNearestBullseye(boxes, bsCentroids)
    if isempty(boxes)
        targetIdx = zeros(0, 1);
        return;
    end
    centres = boxCentres(boxes);
    % Multi-target clustering follows the pdist2 nearest-centre rule from
    % plan_v5 §5.8 (✅). ❓ pdist2 is unavailable without Statistics Toolbox
    % in this install, so use the same squared-Euclidean distance locally.
    if exist('pdist2', 'file') == 2
        d = pdist2(centres, bsCentroids);
    else
        d = localPdist2(centres, bsCentroids);
    end
    [~, targetIdx] = min(d, [], 2);
end

function d = localPdist2(a, b)
    d = zeros(size(a, 1), size(b, 1));
    for i = 1:size(a, 1)
        delta = b - a(i, :);
        d(i, :) = sum(delta .^ 2, 2)';
    end
end

function tf = pointInsideBox(point, box)
    tf = point(1) >= box(1) && point(1) <= box(1) + box(3) && ...
        point(2) >= box(2) && point(2) <= box(2) + box(4);
end
