function targetExplorerUI()
    % === Predefined File Paths ===
    refFile = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\Recordings\CBP\plane6\ref_plan6cbp_2025_04_21_18_21_17.wav';
    surFile = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\Recordings\CBP\plane6\sur_plan6cbp_2025_04_21_18_21_17.wav';

    % === Load WAV files ===
    [iq_ref, Fs1] = audioread(refFile);
    [iq_sur, Fs2] = audioread(surFile);
    if Fs1 ~= Fs2
        error('Sampling rates do not match.');
    end
    Fs = Fs1;

    % Convert stereo to complex
    ref = iq_ref(:,1) + 1j * iq_ref(:,2);
    sur = iq_sur(:,1) + 1j * iq_sur(:,2);

    % === Create UI ===
    fig = uifigure('Name', 'Target Explorer UI', 'Position', [100, 100, 700, 500]);

    segmentLength = 5000;
    offsetStart = 1e5;

    ax = uiaxes(fig, 'Position', [50 100 600 300]);

    % Offset slider
    sld_offset = uislider(fig, ...
        'Position', [100, 70, 500, 3], ...
        'Limits', [1, length(sur) - segmentLength], ...
        'Value', offsetStart, ...
        'ValueChangedFcn', @(sld, event) update());

    lbl_offset = uilabel(fig, ...
        'Position', [100, 80, 400, 22], ...
        'Text', ['Offset Start = ', num2str(offsetStart)]);

    % Play/Pause button
    btn = uibutton(fig, 'Text', '▶ Auto Scan', ...
        'Position', [300, 20, 100, 30], ...
        'ButtonPushedFcn', @(btn, event) toggleTimer());

    % Timer config
    t = timer( ...
        'ExecutionMode', 'fixedRate', ...
        'Period', 0.3, ...
        'TimerFcn', @(~, ~) autoStep(), ...
        'BusyMode', 'drop');

    direction = 1;  % 1 = forward, -1 = backward

    update();  % Initial plot

    function update()
        offsetStart = round(sld_offset.Value);
        lbl_offset.Text = ['Offset Start = ', num2str(offsetStart)];

        % Get segments
        seg_ref = ref(1:segmentLength);
        seg_sur = sur(offsetStart : offsetStart + segmentLength - 1);

        [xc, lags] = xcorr(seg_sur, seg_ref);
        [peakVal, idx] = max(abs(xc));
        peakLag = lags(idx);

        % Plot
        plot(ax, lags, abs(xc), 'LineWidth', 1.2);
        title(ax, ['Peak @ lag = ', num2str(peakLag), ' samples, Amplitude = ', num2str(peakVal)]);
        xlabel(ax, 'Lag (samples)');
        ylabel(ax, '|Cross-Correlation|');
        grid(ax, 'on');
    end

    function autoStep()
        % Step forward/backward
        stepSize = 500;  % Samples per step
        current = sld_offset.Value;
        minVal = sld_offset.Limits(1);
        maxVal = sld_offset.Limits(2);

        newVal = current + direction * stepSize;

        % Reverse direction at edges
        if newVal >= maxVal
            newVal = maxVal;
            direction = -1;
        elseif newVal <= minVal
            newVal = minVal;
            direction = 1;
        end

        % Update slider value
        sld_offset.Value = newVal;
        
        % Manually trigger the update (slider callback isn't called automatically)
        update();
    end

    function toggleTimer()
        if strcmp(t.Running, 'off')
            start(t);
            btn.Text = '⏸ Pause';
        else
            stop(t);
            btn.Text = '▶ Auto Scan';
        end
    end

    % Clean up timer when figure is closed
    fig.CloseRequestFcn = @(src, event) cleanup();

    function cleanup()
        if isvalid(t)
            stop(t);
            delete(t);
        end
        delete(fig);
    end
end
