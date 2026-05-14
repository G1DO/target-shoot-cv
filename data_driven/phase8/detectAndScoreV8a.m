function [hitCount, totalScore, annotated, perTarget] = detectAndScoreV8a(I)
% detectAndScoreV8a  Path A Experiment A1 wrapper (plan_v8_path_A_pure_ML §3).
%
% Same API as data_driven/phase6/detectAndScore.m — the GUI can opt-in by
% changing one call site. Differences from the legacy wrapper:
%
%   1. detect() is called at threshold=0.01 (matches the cache used by the
%      ceiling sweep that produced the winning combo). The legacy wrapper
%      uses 0.05; both rely on score-threshold filtering downstream so the
%      lower seed threshold is what enables per-class tuning to pick up
%      lower-confidence boxes when wanted.
%   2. Per-class score thresholds are loaded as bestT_hit_v8a /
%      bestT_ring_v8a / bestT_bullseye_v8a from phase3/best_thresholds.mat
%      (Exp A1 winners). The legacy bestT_hit / bestT_ring / bestT_bullseye
%      fields are left in place so detectAndScore.m keeps its current
%      behaviour.
%   3. Class-wise IoU NMS is applied after the per-class score filter, with
%      bestNMS_hit_v8a / bestNMS_ring_v8a / bestNMS_bullseye_v8a from the
%      same .mat file. This reproduces phase5/ceiling_exp1_sweep.csv exactly
%      for the chosen combo.
%
% Citations:
%   ✅ Lab 8 `detect(..., 'Threshold', ...)` — `yolo_vehicle.mlx`
%   ✅ L09 s33–44 — PR/AP-driven per-class threshold selection
%   🟡 Class-wise NMS extends the L09 single-NMS pattern to per-class IoU
%      (project-specific; flagged as extension in the report)
%   ✅ Pipeline matches `data_driven/phase5/run_ceiling_experiments.m`

    persistent detector muChannel sigmaChannel ...
        T_hit T_ring T_bullseye NMS_hit NMS_ring NMS_bullseye projectRoot

    if isempty(detector)
        thisDir = fileparts(mfilename('fullpath'));
        dataDrivenDir = fileparts(thisDir);
        projectRoot = fileparts(dataDrivenDir);
        addpath(fullfile(dataDrivenDir, 'phase2a'));
        addpath(fullfile(dataDrivenDir, 'phase3'));

        S = load(fullfile(projectRoot, 'models', 'yolov2_pretrained.mat'), 'detector');
        detector = S.detector;

        C = load(fullfile(projectRoot, 'models', 'channel_stats.mat'), ...
            'muChannel', 'sigmaChannel');
        muChannel = C.muChannel;
        sigmaChannel = C.sigmaChannel;

        T = load(fullfile(dataDrivenDir, 'phase3', 'best_thresholds.mat'));
        T_hit = T.bestT_hit_v8a;
        T_ring = T.bestT_ring_v8a;
        T_bullseye = T.bestT_bullseye_v8a;
        NMS_hit = T.bestNMS_hit_v8a;
        NMS_ring = T.bestNMS_ring_v8a;
        NMS_bullseye = T.bestNMS_bullseye_v8a;
    end

    addpath(fullfile(projectRoot, 'data_driven', 'phase2a'));
    addpath(fullfile(projectRoot, 'data_driven', 'phase3'));

    I_display = ensureRGB8(I);
    Ipp = preprocessForDetector(I, muChannel, sigmaChannel);

    [bboxes, scores, labels] = detect(detector, Ipp, 'Threshold', 0.01);

    labelText = string(labels);
    keep = ((labelText == "hit")      & scores >= T_hit) | ...
           ((labelText == "ring")     & scores >= T_ring) | ...
           ((labelText == "bullseye") & scores >= T_bullseye);
    bboxes = bboxes(keep, :);
    scores = scores(keep);
    labels = labels(keep);

    [bboxes, scores, labels] = classwiseNms(bboxes, scores, labels, ...
        NMS_hit, NMS_ring, NMS_bullseye);

    [hitCount, totalScore, perTarget] = scoreFromDetections(bboxes, labels, scores);

    if ~isempty(bboxes)
        labelStrings = cellstr(compose("%s %.2f", string(labels), scores));
        annotated = insertObjectAnnotation(I_display, 'rectangle', bboxes, ...
            labelStrings, 'TextBoxOpacity', 0.7, 'FontSize', 14);
    else
        annotated = I_display;
    end
    annotated = insertText(annotated, [10 10], ...
        sprintf('Hits: %d  Score: %d', hitCount, totalScore), ...
        'FontSize', 18, 'BoxColor', 'white', 'BoxOpacity', 0.85);
end

function I = ensureRGB8(I)
    if size(I, 3) == 1
        I = repmat(I, 1, 1, 3);
    elseif size(I, 3) > 3
        I = I(:, :, 1:3);
    end
    if ~isa(I, 'uint8')
        I = im2uint8(I);
    end
end

function [outBoxes, outScores, outLabels] = classwiseNms(boxes, scores, labels, nmsHit, nmsRing, nmsBull)
    outBoxes = zeros(0, 4);
    outScores = zeros(0, 1);
    outLabels = labels([]);
    classes = ["hit", "ring", "bullseye"];
    thresholds = [nmsHit, nmsRing, nmsBull];
    labelText = string(labels);
    for c = 1:numel(classes)
        idx = find(labelText == classes(c));
        if isempty(idx)
            continue;
        end
        keepLocal = nmsIndices(boxes(idx, :), scores(idx), thresholds(c));
        kept = idx(keepLocal);
        outBoxes  = [outBoxes;  boxes(kept, :)]; %#ok<AGROW>
        outScores = [outScores; scores(kept)];   %#ok<AGROW>
        outLabels = [outLabels; labels(kept)];   %#ok<AGROW>
    end
end

function keep = nmsIndices(boxes, scores, threshold)
    if isempty(boxes)
        keep = [];
        return;
    end
    [~, order] = sort(scores, 'descend');
    keep = [];
    while ~isempty(order)
        i = order(1);
        keep(end + 1, 1) = i; %#ok<AGROW>
        if numel(order) == 1
            break;
        end
        rest = order(2:end);
        ious = bboxIoU(boxes(i, :), boxes(rest, :));
        order = rest(ious <= threshold);
    end
end

function iou = bboxIoU(box, boxes)
    xA = max(box(1), boxes(:, 1));
    yA = max(box(2), boxes(:, 2));
    xB = min(box(1) + box(3), boxes(:, 1) + boxes(:, 3));
    yB = min(box(2) + box(4), boxes(:, 2) + boxes(:, 4));
    interW = max(0, xB - xA);
    interH = max(0, yB - yA);
    interArea = interW .* interH;
    unionArea = box(3) * box(4) + boxes(:, 3) .* boxes(:, 4) - interArea;
    iou = interArea ./ max(unionArea, eps);
end
