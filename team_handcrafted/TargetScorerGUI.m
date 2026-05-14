function TargetScorerGUI
    % Create the main window (Widened to 880 to fit 5 buttons)
    fig = uifigure('Name', 'Shooting Target Analyzer', 'Position', [100 100 880 200]);
    
    % --- Button 1: Handcrafted ALL ---
    uibutton(fig, 'push', ...
        'Text', 'Handcrafted ALL (1,3)', ...
        'Position', [20, 100, 150, 40], ...
        'ButtonPushedFcn', @(btn, event) run_gui_logic_all());
    
    % --- Button 2: Handcrafted Single ---
    uibutton(fig, 'push', ...
        'Text', 'Handcrafted Single', ...
        'Position', [190, 100, 150, 40], ...
        'ButtonPushedFcn', @(btn, event) run_gui_logic_single());

    % --- Button 3: CASE 2 ---
    uibutton(fig, 'push', ...
        'Text', 'CASE 2', ...
        'Position', [360, 100, 150, 40], ...
        'ButtonPushedFcn', @(btn, event) run_gui_logic_case2());
    
    % --- NEW BUTTON: CASE 4 ---
    uibutton(fig, 'push', ...
        'Text', 'CASE 4', ...
        'Position', [530, 100, 150, 40], ...
        'ButtonPushedFcn', @(btn, event) run_gui_logic_case4());
    
    % --- Button 5: Exit ---
    uibutton(fig, 'push', ...
        'Text', 'Exit', ...
        'Position', [700, 100, 150, 40], ...
        'ButtonPushedFcn', @(btn, event) delete(fig));

    % Label for status
    lblStatus = uilabel(fig, 'Text', 'Select a mode to begin.', 'Position', [20, 50, 840, 20]);

    % --- Logic for CASE 4 (Splatter Targets) ---
    function run_gui_logic_case4()
        [file, path] = uigetfile({'*.jpg;*.png;*.bmp', 'Image Files'}, ...
            'Select Splatter Target Image', 'MultiSelect', 'off');
        
        if isequal(file, 0), return; end
        fullImagePath = fullfile(path, file);
        
        lblStatus.Text = 'Processing Case 4 (Splatter)...';
        pause(0.1);
        
        try
            % Calls your function for splatter targets
            score_case4_splatter_targets(fullImagePath); 
            lblStatus.Text = 'Case 4 Analysis complete.';
        catch ME
            lblStatus.Text = 'Error during Case 4 processing.';
            fprintf('Error: %s\n', ME.message);
        end
    end

    % --- Logic for CASE 2 ---
    function run_gui_logic_case2()
        [file, path] = uigetfile({'*.jpg;*.png;*.bmp', 'Image Files'}, ...
            'Select Case 2 Target Image', 'MultiSelect', 'off');
        if isequal(file, 0), return; end
        try
            paper_target_score_two_cases(fullfile(path, file)); 
            lblStatus.Text = 'Case 2 Analysis complete.';
        catch ME
            lblStatus.Text = 'Error during Case 2 processing.';
        end
    end

    % --- Logic for Batch Processing (ALL) ---
    function run_gui_logic_all()
        [files, path] = uigetfile({'*.jpg;*.png;*.bmp', 'Image Files'}, ...
            'Select Multiple Target Images', 'MultiSelect', 'on');
        if isequal(files, 0), return; end
        if ischar(files), files = {files}; end
        lblStatus.Text = sprintf('Processing %d images...', numel(files));
        pause(0.1);
        for i = 1:numel(files)
            try
                score_shooting_target(fullfile(path, files{i}));
            catch
            end
        end
        lblStatus.Text = 'Batch processing complete.';
    end

    % --- Logic for Single Image ---
    function run_gui_logic_single()
        [file, path] = uigetfile({'*.jpg;*.png;*.bmp', 'Image Files'}, ...
            'Select Target Image', 'MultiSelect', 'off');
        if isequal(file, 0), return; end
        try
            score_and_show_single(fullfile(path, file)); 
            lblStatus.Text = 'Analysis complete.';
        catch
            lblStatus.Text = 'Error during processing.';
        end
    end
end