%% Passive Radar Cross-Correlation Alignment UI
clc;
clear;
close all;

disp('Loading WAV files...');

% === [1] DEFINE FILE PATHS HERE ===
refFile = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\Recordings\CBP\plane11\ref_plane11cbp_2025_04_21_18_21_17.wav'; 
surFile = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\Recordings\CBP\plane11\sur_plane11cbp_2025_04_21_18_21_17.wav';

% === [2] LOAD FILES ===
[iqData_ref, Fs_ref] = audioread(refFile);
[iqData_sur, Fs_sur] = audioread(surFile);

if Fs_ref ~= Fs_sur
    error('Error: Reference and Surveillance Fs Mismatch');
end

Fs = Fs_ref;

% Convert stereo WAV to complex IQ
IQ_complex_ref = iqData_ref(:,1) + 1j * iqData_ref(:,2);
IQ_complex_sur = iqData_sur(:,1) + 1j * iqData_sur(:,2);

% Trim to equal length
minLength = min(length(IQ_complex_ref), length(IQ_complex_sur));
IQ_complex_ref = IQ_complex_ref(1:minLength);
IQ_complex_sur = IQ_complex_sur(1:minLength);

% Launch UI
runAlignmentUI(IQ_complex_ref, IQ_complex_sur);

%% Alignment UI Function
function runAlignmentUI(IQ_complex_ref, IQ_complex_sur)

    disp('Launching Alignment UI...');

    fig = uifigure('Name', 'Alignment Tuner', 'Position', [100 100 650 400]);

    segmentLength = 1e6;
    offset_start = 1e5;
    polarity = -1;

    sld_seg = uislider(fig, ...
        'Position', [100, 310, 400, 3], ...
        'Limits', [1e4, 1e6], ...
        'MajorTicks', [1e4, 2e5, 4e5, 6e5, 8e5, 1e6], ...
        'Value', segmentLength, ...
        'ValueChangedFcn', @(sld,event) update());

    lbl_seg = uilabel(fig, 'Position', [100, 325, 300, 22], ...
        'Text', ['Segment Length = ', num2str(segmentLength)]);

    sld_off = uislider(fig, ...
        'Position', [100, 240, 400, 3], ...
        'Limits', [1, length(IQ_complex_ref)-1e5], ...
        'MajorTicks', [0, 2e6, 4e6, 6e6, 8e6, 1e7], ...
        'Value', offset_start, ...
        'ValueChangedFcn', @(sld,event) update());

    lbl_off = uilabel(fig, 'Position', [100, 255, 300, 22], ...
        'Text', ['Offset Start = ', num2str(offset_start)]);

    btn = uibutton(fig, 'state', ...
        'Position', [100, 190, 220, 30], ...
        'Text', 'Polarity: -sample_offset', ...
        'ValueChangedFcn', @(btn,event) update());

    ax = uiaxes(fig, 'Position', [50 20 550 140]);

    function update()
        segmentLength = round(sld_seg.Value);
        offset_start = round(sld_off.Value);

        if offset_start + segmentLength - 1 > length(IQ_complex_ref)
            offset_start = length(IQ_complex_ref) - segmentLength + 1;
        end

        lbl_seg.Text = ['Segment Length = ', num2str(segmentLength)];
        lbl_off.Text = ['Offset Start = ', num2str(offset_start)];

        if btn.Value
            polarity = +1;
            btn.Text = 'Polarity: +sample_offset';
        else
            polarity = -1;
            btn.Text = 'Polarity: -sample_offset';
        end

        segment_ref = IQ_complex_ref(offset_start:offset_start+segmentLength-1);
        segment_sur = IQ_complex_sur(offset_start:offset_start+segmentLength-1);

        [xcorr_vals, lags] = xcorr(segment_sur, segment_ref);
        [~, maxIdx] = max(abs(xcorr_vals));
        sample_offset = lags(maxIdx);
        disp(['Estimated Sample Offset = ', num2str(sample_offset), ' samples']);

        IQ_complex_sur_aligned = circshift(IQ_complex_sur, polarity * sample_offset);

        plot(ax, lags, abs(xcorr_vals));
        xlabel(ax, 'Lag (samples)');
        ylabel(ax, '|Cross-Correlation|');
        title(ax, ['Estimated Offset = ', num2str(polarity * sample_offset), ' samples']);
        grid(ax, 'on');
    end

    update();  % Initial run
end