function [hitCount, totalScore, annotated, perTarget] = detectAndScore(I)
% detectAndScore  Phase 6 GUI inference wrapper.
%
% Lab 8 + Phase 3 + per-class threshold filter (v6.2). The team's GUI calls this.
% I: input image (uint8 RGB or grayscale; this function handles both).

    persistent detector muChannel sigmaChannel T_hit T_ring T_bullseye projectRoot
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
        T_hit = T.bestT_hit;
        T_ring = T.bestT_ring;
        T_bullseye = T.bestT_bullseye;
    end

    addpath(fullfile(projectRoot, 'data_driven', 'phase2a'));
    addpath(fullfile(projectRoot, 'data_driven', 'phase3'));

    I_display = ensureRGB8(I);

    % Preprocess (v1 path: CLAHE + zscore). ✅ Phase 2a/v1 restored helper.
    Ipp = preprocessForDetector(I, muChannel, sigmaChannel);

    % Lab 8 detect pattern ✅: run detector at a low evaluation threshold,
    % then apply Phase 3 per-class threshold extension 🟡.
    [bboxes, scores, labels] = detect(detector, Ipp, 'Threshold', 0.05);
    labelText = string(labels);
    keep_h = (scores >= T_hit) & (labelText == "hit");
    keep_r = (scores >= T_ring) & (labelText == "ring");
    keep_b = (scores >= T_bullseye) & (labelText == "bullseye");
    keep = keep_h | keep_r | keep_b;
    bboxes = bboxes(keep, :);
    scores = scores(keep);
    labels = labels(keep);

    % Score with Phase 3 docx scoring function. ✅ scoreFromDetections unit-tested.
    [hitCount, totalScore, perTarget] = scoreFromDetections(bboxes, labels, scores);

    % Lab 8 visualisation pattern ✅: insertObjectAnnotation overlays boxes.
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
