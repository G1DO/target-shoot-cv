function ShootingTargetGUI_Unified()
% ShootingTargetGUI_Unified  Simple 4-button GUI for the delivery spec.
%
%   1. BROWSE single image  -> run BOTH HC and DD; show 2 results.
%   2. BROWSE ALL SEEN (HC) -> iterate 17 SEEN cases (HC only).
%   3. BROWSE ALL SEEN (DD) -> iterate 17 SEEN cases (DD only).
%   4. ACQUIRE camera       -> snapshot, then BOTH pipelines.
%
% Reuses (no modification):
%   - team_handcrafted/score_shooting_target.m
%   - data_driven/phase8/detectAndScoreV8final.m

    thisDir = fileparts(mfilename('fullpath'));
    addpath(fullfile(thisDir, 'team_handcrafted'));
    addpath(fullfile(thisDir, 'data_driven', 'phase2a'));
    addpath(fullfile(thisDir, 'data_driven', 'phase3'));
    addpath(fullfile(thisDir, 'data_driven', 'phase6'));
    addpath(fullfile(thisDir, 'data_driven', 'phase8'));

    seenRoot = fullfile(thisDir, '2 Shooting Target Score', 'SEEN TESTS');
    panelsRoot = fullfile(thisDir, 'unified_gui_panels');
    if ~exist(panelsRoot, 'dir'); mkdir(panelsRoot); end

    seenList = buildSeenList(seenRoot);

    %% Layout
    fig = uifigure('Name', 'Shooting Target Score - Unified GUI', ...
        'Position', [80 60 1320 800], 'Visible', 'on');
    mainGrid = uigridlayout(fig, [3 1]);
    mainGrid.RowHeight = {60, 50, '1x'};
    mainGrid.Padding = [12 12 12 12];
    mainGrid.RowSpacing = 8;

    btnGrid = uigridlayout(mainGrid, [1 4]);
    btnGrid.Layout.Row = 1;
    btnGrid.ColumnSpacing = 10;

    btnSingle = uibutton(btnGrid, 'push', ...
        'Text', '1. BROWSE single image (HC + DD)', ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @onBrowseSingle);
    btnAllHC = uibutton(btnGrid, 'push', ...
        'Text', '2. BROWSE ALL SEEN - Hand-Crafted', ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @onBrowseAllSeenHC);
    btnAllDD = uibutton(btnGrid, 'push', ...
        'Text', '3. BROWSE ALL SEEN - Data-Driven', ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @onBrowseAllSeenDD);
    btnCamera = uibutton(btnGrid, 'push', ...
        'Text', '4. ACQUIRE from camera (HC + DD)', ...
        'FontSize', 13, 'FontWeight', 'bold', ...
        'ButtonPushedFcn', @onAcquireCamera);

    statusLabel = uilabel(mainGrid, ...
        'Text', 'Ready. Click a button.', ...
        'FontSize', 14, 'WordWrap', 'on');
    statusLabel.Layout.Row = 2;

    resultGrid = uigridlayout(mainGrid, [1 2]);
    resultGrid.Layout.Row = 3;
    resultGrid.ColumnWidth = {'1x', '1x'};
    resultGrid.ColumnSpacing = 12;

    panelHC = uipanel(resultGrid, 'Title', 'Hand-Crafted  |  Score: -', ...
        'FontWeight', 'bold', 'FontSize', 14);
    panelHC.Layout.Column = 1;
    axHC = uiaxes(panelHC, 'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.96]);
    axHC.XTick = []; axHC.YTick = []; axHC.Box = 'on';

    panelDD = uipanel(resultGrid, 'Title', 'Data-Driven  |  Score: -', ...
        'FontWeight', 'bold', 'FontSize', 14);
    panelDD.Layout.Column = 2;
    axDD = uiaxes(panelDD, 'Units', 'normalized', 'Position', [0.02 0.02 0.96 0.96]);
    axDD.XTick = []; axDD.YTick = []; axDD.Box = 'on';

    state = struct('screenshotSaved', false, ...
        'cameraActive', false, 'webcam', [], 'cameraTimer', []);
    fig.CloseRequestFcn = @onClose;

    %% Callbacks
    function onBrowseSingle(~, ~)
        [fileName, folder] = uigetfile( ...
            {'*.jpg;*.jpeg;*.png;*.bmp', 'Image files'}, 'Select target image');
        if isequal(fileName, 0)
            statusLabel.Text = 'Browse cancelled.';
            return;
        end
        I = imread(fullfile(folder, fileName));
        runBoth(I, fileName);

        if ~state.screenshotSaved
            try
                exportapp(fig, fullfile(thisDir, 'ShootingTargetGUI_Unified_screenshot.png'));
                state.screenshotSaved = true;
            catch
            end
        end
    end

    function onBrowseAllSeenHC(~, ~)
        if isempty(seenList)
            statusLabel.Text = 'No SEEN images found.';
            return;
        end
        folderName = [timeStamp() '-HANDCRAFT'];
        outDir = fullfile(panelsRoot, folderName);
        if ~exist(outDir, 'dir'); mkdir(outDir); end
        panelDD.Title = 'Data-Driven  |  (idle this pass)';
        cla(axDD);
        N = numel(seenList);
        for i = 1:N
            entry = seenList{i};
            statusLabel.Text = sprintf('HC pass: case %d/%d - %s -> %s ...', ...
                i, N, entry.label, folderName);
            drawnow;
            try
                I = imread(entry.path);
                t = tic;
                result = score_shooting_target(I);
                showInAxes(axHC, result.annotatedImage);
                panelHC.Title = sprintf('Hand-Crafted  |  Score: %g', result.totalScore);
                statusLabel.Text = sprintf('HC case %d/%d - %s done (%.1fs, score=%g). Saving to %s/', ...
                    i, N, entry.label, toc(t), result.totalScore, folderName);
                imwrite(result.annotatedImage, fullfile(outDir, [entry.savename '.png']));
            catch ME
                showInAxes(axHC, errorImage(['HC error: ' ME.message]));
                panelHC.Title = 'Hand-Crafted  |  Score: ERROR';
                statusLabel.Text = sprintf('HC case %d/%d failed: %s', i, N, ME.message);
            end
            drawnow;
            if i < N, pause(1.5); end
        end
        statusLabel.Text = sprintf( ...
            'Done HC pass. All %d cases saved to unified_gui_panels/%s/', N, folderName);
    end

    function onBrowseAllSeenDD(~, ~)
        if isempty(seenList)
            statusLabel.Text = 'No SEEN images found.';
            return;
        end
        folderName = [timeStamp() '-DATADRIVEN'];
        outDir = fullfile(panelsRoot, folderName);
        if ~exist(outDir, 'dir'); mkdir(outDir); end
        panelHC.Title = 'Hand-Crafted  |  (idle this pass)';
        cla(axHC);
        N = numel(seenList);
        for i = 1:N
            entry = seenList{i};
            statusLabel.Text = sprintf('DD pass: case %d/%d - %s -> %s ...', ...
                i, N, entry.label, folderName);
            drawnow;
            try
                I = imread(entry.path);
                t = tic;
                [hits, score, annotated, ~] = detectAndScoreV8final(I);
                showInAxes(axDD, annotated);
                panelDD.Title = sprintf('Data-Driven  |  Score: %g (hits=%d)', score, hits);
                statusLabel.Text = sprintf('DD case %d/%d - %s done (%.1fs, score=%g, hits=%d). Saving to %s/', ...
                    i, N, entry.label, toc(t), score, hits, folderName);
                imwrite(annotated, fullfile(outDir, [entry.savename '.png']));
            catch ME
                showInAxes(axDD, errorImage(['DD error: ' ME.message]));
                panelDD.Title = 'Data-Driven  |  Score: ERROR';
                statusLabel.Text = sprintf('DD case %d/%d failed: %s', i, N, ME.message);
            end
            drawnow;
            if i < N, pause(1.5); end
        end
        statusLabel.Text = sprintf( ...
            'Done DD pass. All %d cases saved to unified_gui_panels/%s/', N, folderName);
    end

    function onAcquireCamera(~, ~)
        if state.cameraActive
            % --- second click: TAKE SHOT ---
            I = [];
            try
                I = snapshot(state.webcam);
            catch ME
                statusLabel.Text = ['Snapshot failed: ' ME.message];
            end
            stopCameraPreview();
            if ~isempty(I)
                runBoth(I, 'camera snapshot');
            end
            return;
        end

        % --- first click: start LIVE PREVIEW ---
        try
            state.webcam = webcam;
        catch ME
            % Webcam unavailable - fall back to stub on first SEEN image.
            statusLabel.Text = sprintf('Webcam unavailable (%s). Using stub image.', ME.message);
            if ~isempty(seenList)
                I = imread(seenList{1}.path);
                sourceTag = sprintf('camera stub: %s', seenList{1}.label);
            else
                I = uint8(255 * ones(416, 416, 3));
                sourceTag = 'camera stub: white image';
            end
            runBoth(I, sourceTag);
            return;
        end

        state.cameraActive = true;
        btnCamera.Text = 'TAKE SHOT (click to capture)';
        btnCamera.BackgroundColor = [1 0.85 0.85];
        btnSingle.Enable = 'off';
        btnAllHC.Enable = 'off';
        btnAllDD.Enable = 'off';
        panelHC.Title = 'LIVE PREVIEW - frame yourself, then click TAKE SHOT';
        panelDD.Title = 'Data-Driven  |  (waiting for shot)';
        cla(axDD);
        statusLabel.Text = 'Live camera preview running. Position the target, then click TAKE SHOT.';
        drawnow;

        state.cameraTimer = timer( ...
            'Period', 0.1, ...
            'ExecutionMode', 'fixedSpacing', ...
            'BusyMode', 'drop', ...
            'TimerFcn', @(~, ~) updatePreviewFrame());
        start(state.cameraTimer);
    end

    function updatePreviewFrame()
        if ~state.cameraActive || isempty(state.webcam)
            return;
        end
        try
            frame = snapshot(state.webcam);
            showInAxes(axHC, frame);
        catch
            % Suppress per-frame errors so the preview keeps trying.
        end
    end

    function stopCameraPreview()
        if ~isempty(state.cameraTimer) && isvalid(state.cameraTimer)
            stop(state.cameraTimer);
            delete(state.cameraTimer);
        end
        state.cameraTimer = [];
        if ~isempty(state.webcam)
            try
                delete(state.webcam);
            catch
            end
            state.webcam = [];
        end
        state.cameraActive = false;
        btnCamera.Text = '4. ACQUIRE from camera (HC + DD)';
        btnCamera.BackgroundColor = [0.96 0.96 0.96];
        btnSingle.Enable = 'on';
        btnAllHC.Enable = 'on';
        btnAllDD.Enable = 'on';
    end

    function onClose(~, ~)
        stopCameraPreview();
        delete(fig);
    end

    function runBoth(I, sourceTag)
        % HC
        statusLabel.Text = sprintf('Running Hand-Crafted on %s ...', sourceTag);
        panelHC.Title = 'Hand-Crafted  |  Score: ...';
        panelDD.Title = 'Data-Driven  |  Score: ...';
        cla(axHC); cla(axDD);
        drawnow;
        tHC = tic;
        hcScore = NaN;
        try
            res = score_shooting_target(I);
            hcScore = res.totalScore;
            showInAxes(axHC, res.annotatedImage);
            panelHC.Title = sprintf('Hand-Crafted  |  Score: %g', hcScore);
        catch ME
            showInAxes(axHC, errorImage(['HC error: ' ME.message]));
            panelHC.Title = 'Hand-Crafted  |  Score: ERROR';
        end
        hcElapsed = toc(tHC);
        statusLabel.Text = sprintf( ...
            'HC done (%.1fs, score=%g). Running Data-Driven (first call: model load + JIT, ~30-60s)...', ...
            hcElapsed, hcScore);
        drawnow;

        % DD
        tDD = tic;
        ddScore = NaN; ddHits = NaN;
        try
            [ddHits, ddScore, annotated, ~] = detectAndScoreV8final(I);
            showInAxes(axDD, annotated);
            panelDD.Title = sprintf('Data-Driven  |  Score: %g (hits=%d)', ddScore, ddHits);
        catch ME
            showInAxes(axDD, errorImage(['DD error: ' ME.message]));
            panelDD.Title = 'Data-Driven  |  Score: ERROR';
        end
        ddElapsed = toc(tDD);

        statusLabel.Text = sprintf( ...
            'Done %s. HC=%g (%.1fs)  |  DD=%g hits=%d (%.1fs).', ...
            sourceTag, hcScore, hcElapsed, ddScore, ddHits, ddElapsed);
        drawnow;
    end
end

%% --- helpers (local) ---

function ts = timeStamp()
% Returns a Windows-safe timestamp like "9-38am" or "2-15pm".
    d = datetime('now');
    h = hour(d);
    m = minute(d);
    if h == 0
        h12 = 12;  ampm = 'am';
    elseif h < 12
        h12 = h;   ampm = 'am';
    elseif h == 12
        h12 = 12;  ampm = 'pm';
    else
        h12 = h - 12; ampm = 'pm';
    end
    ts = sprintf('%d-%02d%s', h12, m, ampm);
end

function showInAxes(ax, img)
    cla(ax);
    if isempty(img), return; end
    imshow(img, 'Parent', ax);
    axis(ax, 'image');
    ax.XTick = []; ax.YTick = [];
end

function img = errorImage(message)
    img = uint8(255 * ones(360, 640, 3));
    img = insertText(img, [20 160], char(message), ...
        'FontSize', 18, 'BoxColor', 'red', 'BoxOpacity', 0.3);
end

function seenList = buildSeenList(seenRoot)
    rel = { ...
        'Case 1\1.1.jpg',           'Case 1\1.1',           'case1_1'; ...
        'Case 1\1.2.jpg',           'Case 1\1.2',           'case1_2'; ...
        'Case 2\2.1.jpg',           'Case 2\2.1',           'case2_1'; ...
        'Case 2\4.2.jpg',           'Case 2\4.2',           'case2_4_2'; ...
        'Case 3\3.1.jpg',           'Case 3\3.1',           'case3_1'; ...
        'Case 3\3.2.png',           'Case 3\3.2',           'case3_2'; ...
        'Case 4\4.1.jpg',           'Case 4\4.1',           'case4_1'; ...
        'Case 4\4.2.jpg',           'Case 4\4.2',           'case4_2'; ...
        'Bonus\Case 5\5.1.png',     'Bonus Case 5\5.1',     'bonus_case5_1'; ...
        'Bonus\Case 5\5.2.png',     'Bonus Case 5\5.2',     'bonus_case5_2'; ...
        'Bonus\Case 6\6.1.jpg',     'Bonus Case 6\6.1',     'bonus_case6_1'; ...
        'Bonus\Case 6\6.2.jpg',     'Bonus Case 6\6.2',     'bonus_case6_2'; ...
        'Bonus\Case 6\6.3.jpg',     'Bonus Case 6\6.3',     'bonus_case6_3'; ...
        'Bonus\Case 7\7.1.jpg',     'Bonus Case 7\7.1',     'bonus_case7_1'; ...
        'Bonus\Case 7\7.2.jpg',     'Bonus Case 7\7.2',     'bonus_case7_2'; ...
        'Bonus\Case 8\8.1.jpg',     'Bonus Case 8\8.1',     'bonus_case8_1'; ...
        'Bonus\Case 8\8.2.jpg',     'Bonus Case 8\8.2',     'bonus_case8_2'};
    seenList = {};
    for k = 1:size(rel, 1)
        relPath = strrep(rel{k, 1}, '\', filesep);
        fullPath = fullfile(seenRoot, relPath);
        if exist(fullPath, 'file') == 2
            seenList{end + 1} = struct( ...
                'label', rel{k, 2}, ...
                'path', fullPath, ...
                'savename', rel{k, 3}); %#ok<AGROW>
        end
    end
end
