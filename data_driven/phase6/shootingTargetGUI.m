function app = shootingTargetGUI(mode)
% shootingTargetGUI  App-Designer-style GUI for the shooting-target detector.
%
% Buttons:
%   1. BROWSE single image
%   2. BROWSE ALL SEEN cases
%   3. ACQUIRE image from camera
%
% All routes call detectAndScoreV8final.m (the V8a alias for V8final).
% Optional mode="demo" drives the same callbacks and writes screenshots.

    if nargin < 1
        mode = "interactive";
    else
        mode = string(mode);
    end

    scriptDir = fileparts(mfilename('fullpath'));
    dataDrivenDir = fileparts(scriptDir);
    projectRoot = fileparts(dataDrivenDir);
    phase6Dir = scriptDir;
    seenDir = fullfile(dataDrivenDir, 'data', 'seen');
    seenPanelsDir = fullfile(phase6Dir, 'seen_panels');
    ensureDir(seenPanelsDir);

    addpath(phase6Dir);
    addpath(fullfile(dataDrivenDir, 'phase2a'));
    addpath(fullfile(dataDrivenDir, 'phase3'));
    addpath(fullfile(dataDrivenDir, 'phase8'));

    seenState = struct('files', strings(0, 1), 'images', {{}}, ...
        'annotated', {{}}, 'hitCounts', [], 'scores', [], 'index', 0);

    fig = uifigure('Name', 'Shooting Target Score - Data Driven', ...
        'Position', [100 100 1180 760], 'Visible', 'on');
    grid = uigridlayout(fig, [2 2]);
    grid.RowHeight = {112, '1x'};
    grid.ColumnWidth = {260, '1x'};
    grid.Padding = [12 12 12 12];
    grid.RowSpacing = 10;
    grid.ColumnSpacing = 12;

    controlPanel = uipanel(grid, 'Title', 'Controls');
    controlPanel.Layout.Row = [1 2];
    controlPanel.Layout.Column = 1;
    controlGrid = uigridlayout(controlPanel, [10 1]);
    controlGrid.RowHeight = {42, 42, 42, 28, 28, 42, 42, '1x', 28, 28};
    controlGrid.Padding = [10 10 10 10];

    btnSingle = uibutton(controlGrid, 'push', 'Text', 'BROWSE single', ...
        'ButtonPushedFcn', @onBrowseSingle);
    btnSeen = uibutton(controlGrid, 'push', 'Text', 'BROWSE ALL SEEN', ...
        'ButtonPushedFcn', @onBrowseAllSeen);
    btnCamera = uibutton(controlGrid, 'push', 'Text', 'ACQUIRE camera', ...
        'ButtonPushedFcn', @onAcquireCamera);

    scoreLabel = uilabel(controlGrid, 'Text', 'Hits: -    Score: -', ...
        'FontWeight', 'bold');
    statusLabel = uilabel(controlGrid, 'Text', 'Ready.', ...
        'WordWrap', 'on');

    navGrid = uigridlayout(controlGrid, [1 2]);
    navGrid.Layout.Row = 6;
    navGrid.ColumnWidth = {'1x', '1x'};
    btnPrev = uibutton(navGrid, 'push', 'Text', 'Prev', ...
        'Enable', 'off', 'ButtonPushedFcn', @onPrevSeen);
    btnNext = uibutton(navGrid, 'push', 'Text', 'Next', ...
        'Enable', 'off', 'ButtonPushedFcn', @onNextSeen);

    seenLabel = uilabel(controlGrid, 'Text', 'Seen case: -', 'WordWrap', 'on');
    seenLabel.Layout.Row = 7;
    caveatLabel = uilabel(controlGrid, 'Text', ...
        ['CAVEAT: SEEN cases were included in training per TA permission. ', ...
        'UNSEEN evidence is Phase 5a.'], 'WordWrap', 'on');
    caveatLabel.Layout.Row = 9;
    cameraLabel = uilabel(controlGrid, 'Text', ...
        'Camera button falls back to a stub image if webcam is unavailable. ❓', ...
        'WordWrap', 'on');
    cameraLabel.Layout.Row = 10;

    titleLabel = uilabel(grid, 'Text', 'No image loaded', ...
        'FontSize', 18, 'FontWeight', 'bold');
    titleLabel.Layout.Row = 1;
    titleLabel.Layout.Column = 2;

    axPanel = uipanel(grid, 'Title', 'Annotated result');
    axPanel.Layout.Row = 2;
    axPanel.Layout.Column = 2;
    ax = uiaxes(axPanel, 'Position', [10 10 880 590]);
    ax.XTick = [];
    ax.YTick = [];
    ax.Box = 'on';
    axis(ax, 'image');

    app = struct();
    app.Figure = fig;
    app.Axes = ax;
    app.Buttons = struct('Single', btnSingle, 'Seen', btnSeen, ...
        'Camera', btnCamera, 'Prev', btnPrev, 'Next', btnNext);
    app.Labels = struct('Title', titleLabel, 'Score', scoreLabel, ...
        'Status', statusLabel, 'Seen', seenLabel);

    if mode == "demo"
        runDemo();
    end

    function onBrowseSingle(~, ~)
        [fileName, folder] = uigetfile({'*.jpg;*.jpeg;*.png', ...
            'Image files (*.jpg, *.jpeg, *.png)'}, 'Select target image');
        if isequal(fileName, 0)
            statusLabel.Text = 'Browse cancelled.';
            return;
        end
        runSingleImage(fullfile(folder, fileName), "BROWSE single");
    end

    function onBrowseAllSeen(~, ~)
        files = listSeenImages(seenDir);
        if isempty(files)
            statusLabel.Text = 'No SEEN images found.';
            return;
        end

        statusLabel.Text = sprintf('Processing %d SEEN images...', numel(files));
        drawnow;

        seenState.files = string(files(:));
        seenState.images = cell(numel(files), 1);
        seenState.annotated = cell(numel(files), 1);
        seenState.hitCounts = zeros(numel(files), 1);
        seenState.scores = zeros(numel(files), 1);
        seenState.index = 1;

        for i = 1:numel(files)
            I = imread(files{i});
            [hitCount, totalScore, annotated] = detectAndScoreV8final(I);
            seenState.images{i} = I;
            seenState.annotated{i} = annotated;
            seenState.hitCounts(i) = hitCount;
            seenState.scores(i) = totalScore;
            [~, baseName, ~] = fileparts(files{i});
            imwrite(annotated, fullfile(seenPanelsDir, baseName + ".png"));
        end

        btnPrev.Enable = 'on';
        btnNext.Enable = 'on';
        showSeenIndex(1);
        statusLabel.Text = sprintf('Processed all %d SEEN cases. Panels saved.', numel(files));
    end

    function onAcquireCamera(~, ~)
        try
            % ❓ Webcam support depends on installed support package and hardware.
            cam = webcam;
            I = snapshot(cam);
            clear cam;
            runAcquiredImage(I, "ACQUIRE camera", 'Camera snapshot acquired.');
        catch ME
            fprintf('Camera not available - stub image used. %s\n', ME.message);
            files = listSeenImages(seenDir);
            if isempty(files)
                I = uint8(255 * ones(416, 416, 3));
            else
                I = imread(files{1});
            end
            runAcquiredImage(I, "ACQUIRE camera (stub)", ...
                'Camera not available - stub image used.');
        end
    end

    function onPrevSeen(~, ~)
        if seenState.index > 1
            showSeenIndex(seenState.index - 1);
        end
    end

    function onNextSeen(~, ~)
        if seenState.index < numel(seenState.files)
            showSeenIndex(seenState.index + 1);
        end
    end

    function runSingleImage(imagePath, sourceLabel)
        I = imread(imagePath);
        [hitCount, totalScore, annotated] = detectAndScoreV8final(I);
        [~, name, ext] = fileparts(imagePath);
        renderAnnotated(annotated, sourceLabel + ": " + string([name ext]), ...
            hitCount, totalScore, 'Single-image inference complete.');
    end

    function runAcquiredImage(I, sourceLabel, statusText)
        [hitCount, totalScore, annotated] = detectAndScoreV8final(I);
        renderAnnotated(annotated, sourceLabel, hitCount, totalScore, statusText);
        try
            imwrite(annotated, fullfile(phase6Dir, 'live_demo_screenshot.png'));
        catch
        end
    end

    function showSeenIndex(idx)
        seenState.index = idx;
        annotated = seenState.annotated{idx};
        [~, name, ext] = fileparts(char(seenState.files(idx)));
        renderAnnotated(annotated, "BROWSE ALL SEEN: " + string([name ext]), ...
            seenState.hitCounts(idx), seenState.scores(idx), ...
            sprintf('SEEN case %d of %d.', idx, numel(seenState.files)));
        seenLabel.Text = sprintf('Seen case: %d / %d', idx, numel(seenState.files));
        btnPrev.Enable = matlab.lang.OnOffSwitchState(idx > 1);
        btnNext.Enable = matlab.lang.OnOffSwitchState(idx < numel(seenState.files));
    end

    function renderAnnotated(annotated, titleText, hitCount, totalScore, statusText)
        cla(ax);
        imshow(annotated, 'Parent', ax);
        axis(ax, 'image');
        ax.XTick = [];
        ax.YTick = [];
        titleLabel.Text = char(join(string(titleText), " "));
        scoreLabel.Text = sprintf('Hits: %d    Score: %d', hitCount, totalScore);
        statusLabel.Text = char(join(string(statusText), " "));
        drawnow;
    end

    function runDemo()
        screenshotDir = phase6Dir;
        files = listSeenImages(seenDir);
        if isempty(files)
            error('shootingTargetGUI:noSeenImages', 'No SEEN images found for demo.');
        end

        runSingleImage(files{1}, "BROWSE single demo");
        saveGuiScreenshot(fig, fullfile(screenshotDir, 'gui_state_single.png'));

        onBrowseAllSeen([], []);
        saveGuiScreenshot(fig, fullfile(screenshotDir, 'gui_state_all_seen.png'));

        onAcquireCamera([], []);
        saveGuiScreenshot(fig, fullfile(screenshotDir, 'gui_state_camera.png'));

        close(fig);
    end
end

function files = listSeenImages(seenDir)
    imageFiles = [dir(fullfile(seenDir, 'Case_*.jpg')); ...
        dir(fullfile(seenDir, 'Case_*.jpeg')); ...
        dir(fullfile(seenDir, 'Case_*.png')); ...
        dir(fullfile(seenDir, 'Bonus_*.jpg')); ...
        dir(fullfile(seenDir, 'Bonus_*.jpeg')); ...
        dir(fullfile(seenDir, 'Bonus_*.png'))];
    [~, order] = sort({imageFiles.name});
    imageFiles = imageFiles(order);
    files = cell(numel(imageFiles), 1);
    for i = 1:numel(imageFiles)
        files{i} = fullfile(imageFiles(i).folder, imageFiles(i).name);
    end
end

function saveGuiScreenshot(fig, path)
    drawnow;
    pause(0.2);
    try
        exportapp(fig, path);
    catch
        frame = getframe(fig);
        imwrite(frame.cdata, path);
    end
end

function ensureDir(path)
    if ~exist(path, 'dir')
        mkdir(path);
    end
end
