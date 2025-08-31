%% 
clc;
clear;
close all;

% ===============================================================================
% Passive Radar Software-In-The-Loop (SITL) Test Code                           |
% Objectives                                                                    |
%   (1) Read and Process Reference and Surveillance Channel Data from WAV file  |
%   (2) Inject Fake Moving Targets (optional)                                   |
%   (3) Remove Reference DPI from Surveillance Via (optional)                   |
%       (a) NLMS Adaptive Filter -OR-                                           |
%       (b) FFT Division -OR-                                                   |
%       (c) Wiener Filter                                                       |
%   (4) Compute Reference DPI Removal From Surveillance Algorithm Efficiency    |
%   (5) Matched Filtering & Range Doppler Processing                            |
%                                                                               |
% The entire passive radar digital signal processing (DSP) chain has been       |  
% implemented in MATLAB for offline SITL testing. Once the code has been batch  |
% tested, it will be implemented in the real time passive radar system via      |
% GNU radio.                                                                    |
%                                                                               |
%  ============================ User Defined Vars ============================  | 
% Set Post Processing Params                                                    |
% ------------------------                                                      |
% Set DPI_Removal_Selector to                                                   |
%   0: No Removal                                                               |
%   1: NLMS Adaptive Filter                                                     |
%   2: FFT Division                                                             |
%   3: Wiener Filter                                                            |
DPI_Removal_Selector = 1; %                                                     |
%                                                                               |
% Set Freq_Time_Selector to                                                     |
%   0: Frequency Analysis                                                       |
%   1: Time Analysis                                                            |
Freq_Time_Selector = 0; %                                                       |
%                                                                               |
% Set Inject_Targets_Selector to                                                |
%   0: Do Not Inject Fake Targets                                               |
%   1: Inject Fake Targets                                                      |                                      
Inject_Targets = 0; %                                                           |                      
%                                                                               |
% Set Fake Targets Params                                                       |
% Target 1                                                                      |
target_range_1 = 1500;    % meters                                              |
target_velocity_1 = 60;   % m/s (Moving away from radar)                        |
target_rcs_1 = 0.1;       %                                                     |
%                                                                               |
% Target 2                                                                      |
target_range_2 = 2500;     % meters                                             |
target_velocity_2 = -30;   % m/s (Moving towards radar)                         |
target_rcs_2 = 0.01;       %                                                    |
%                                                                               |
%  Target 3                                                                     |
target_range_3 = 800;      % meters                                             |
target_velocity_3 = 15;    % m/s                                                |
target_rcs_3 = 0.4;        %                                                    |
%                                                                               | 
% Real Time Signal Selector                                                     |
RT_Sig_Selector = 6; %                                                         |
% 1 to 11 plane capture signals available (except 2, signal was corrupted)      |
% ===============================================================================

disp('Passive Radar Processing...');

% Define Global Consts
c = 3e8; % Speed of light in m/s

%% Read and Process Reference and Surveillance Channel Data from WAV file
disp('Loading WAV file...');

%  === Select the WAV files ===

% Base directory [EDIT AS REQUIRED !!!]
basePath = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\Recordings\CBP\';

% Construct folder and file prefix for selected plane
folder = sprintf('plane%d\\', RT_Sig_Selector);
prefix = sprintf('plane%dcbp_2025_04_21_18_21_17', RT_Sig_Selector);

% Construct final file paths
refFile = fullfile(basePath, folder, ['ref_' prefix '.wav']);
surFile = fullfile(basePath, folder, ['sur_' prefix '.wav']);

% Read the WAV files
[iqData_ref, Fs_ref] = audioread(refFile);
[iqData_sur, Fs_sur] = audioread(surFile);

% Check for sample rate mismatch between referene and surveillance
if Fs_ref ~= Fs_sur
    error('Critical Error: Reference and Surveillance Sample Rate mismatch');
end
Fs = Fs_ref; % Set common sampling rate
disp(['Sampling Rate (Fs) = ', num2str(Fs/10e6), ' MSPS']);

% SDR Specfic Parameters
Fc = 538e6; % IO Center Freq (DVB-T2: 538MHz)
visibleBandwidth = 10e6; % (DVB-T2: 8MHz Bandwidth + 2MHz Buffer)

% Convert stereo channels to IQ
IQ_complex_ref = iqData_ref(:,1) + 1j * iqData_ref(:,2); % Reference Signal IQ
IQ_complex_sur = iqData_sur(:,1) + 1j * iqData_sur(:,2); % Surveillance Signal IQ

%% Align Ref and Sur IQ arrays

% Even though reference and surveillance signals were programmed to be
% recorded simultaneously, due to timing inconsistencies from Ubuntu and
% GNU Radio itself, the reference and surveillance recordings were offset
% 0.0167% (~50k samples offset out of a total of 300 million samples)
% Even this small offset buries the target peaks under noise.
% The below routine, aligns the reference and surveillance IQ arrays to
% address this issue.

disp('Auto-aligning Reference and Surveillance Using Best Segment and Offset...');

% === Possible starting offsets and segment lengths ===
% Offset is the starting point inside the IQ arrays.
% The first few IQ packets may be corrupted due to 
% roll off so these packets are to be excluded from 
% alignment processing.
offsets = 0:1e5:3e5; % sweep from 0 to 3mil in steps of 100k
seg_lengths = [1e5, 2.5e5, 5e5, 1e6]; % possible segment lengths

% Bound by min available samples
max_len = min(length(IQ_complex_ref), length(IQ_complex_sur));
% Remove segment lengths that are bigger than Reference and Surveillance IQ array lengths
seg_lengths = seg_lengths(seg_lengths < max_len);

% === Initialize alignment params ===
% XCorr peak value
best_peak_val = -Inf; % Highest peak value indicates best alignment
best_offset = 0;
best_seg_len = 0;
best_lag = 0;

% Iterative loop to find best segment + offset combination for most
% accurate reference and surveillance IQ array alignment
for offset_current = offsets
    for seg_length_current = seg_lengths
        if offset_current + seg_length_current - 1 > max_len
            continue;  % Skip to next segment length if max length has been exceeded
        end
        
        seg_ref = IQ_complex_ref(offset_current + 1 : offset_current + seg_length_current);
        seg_sur = IQ_complex_sur(offset_current + 1 : offset_current + seg_length_current);
        [xc, lags] = xcorr(seg_sur, seg_ref);
        [peak_val, idx] = max(abs(xc));
        
        if peak_val > best_peak_val
            best_peak_val = peak_val;
            best_lag = lags(idx);
            best_offset = offset_current;
            best_seg_len = seg_length_current;
        end
    end
end

disp(['Best Starting Offset = ', num2str(best_offset)]);
disp(['Best Segment Length = ', num2str(best_seg_len)]);
disp(['Estimated Sample Offset (Lag) = ', num2str(best_lag), ' samples']);

% Trim reference and surveillance IQ arrays to align based on the best lag value found above
if best_lag > 0
    IQ_complex_ref = IQ_complex_ref(1 + best_lag : end);
    IQ_complex_sur = IQ_complex_sur(1 : end - best_lag);
elseif best_lag < 0
    IQ_complex_ref = IQ_complex_ref(1 : end + best_lag);
    IQ_complex_sur = IQ_complex_sur(1 - best_lag : end);
end

% Ensure refrence and surveillance IQ arrays are equal in length
min_len = min(length(IQ_complex_ref), length(IQ_complex_sur));
IQ_complex_ref = IQ_complex_ref(1:min_len);
IQ_complex_sur = IQ_complex_sur(1:min_len);

%% Plot Pre-Processed Reference and Surveillance Signals
disp('Plotting Pre-Processed Reference and Surveillance...');

% FFT Parameters
% Num FFT: Define FFT size, must be a power of 2 for efficiency
NFFT = max(2^14, 2^nextpow2(min(length(IQ_complex_ref), length(IQ_complex_sur))));

% Define frequency axis to match SDR software (533 MHz to 543 MHz)
% *Note: Signal has been downconverted to baseband by SDR in actual fact
freqAxis_ref_sur = linspace(Fc - visibleBandwidth/2, Fc + visibleBandwidth/2, NFFT) / 1e6; % Convert to MHz

% Compute FFT & shift center to 0Hz
spectrum_ref = fftshift(abs(fft(IQ_complex_ref, NFFT)));
spectrum_sur = fftshift(abs(fft(IQ_complex_sur, NFFT)));

% Normalize to avoid log(0) errors
spectrum_ref = spectrum_ref / max(spectrum_ref(spectrum_ref > 0));
spectrum_sur = spectrum_sur / max(spectrum_sur(spectrum_sur > 0));
% Normalized reference and surveillance spectrum range from 0 to 1

if Freq_Time_Selector == 0
    % Plot Frequency Domain
    figure(1);
    subplot(3,1,1);
    plot(freqAxis_ref_sur, 20*log10(spectrum_ref), 'b');
    xlabel('Frequency (MHz)');
    ylabel('Magnitude (dB)');
    title('Raw Reference Spectrum (Frequency Domain');
    grid on;
    xlim([533, 543]);  % Ensure correct range
    xticks(533:1:543); % Correct tick marks for clarity
    ylim([-100, 5]);   % Normalize to dB scale
    
    subplot(3,1,2);
    plot(freqAxis_ref_sur, 20*log10(spectrum_sur), 'r');
    xlabel('Frequency (MHz)');
    ylabel('Magnitude (dB)');
    title('Raw Surveillance Spectrum (Frequency Domain)');
    grid on;
    xlim([533, 543]);  % Ensure correct range
    xticks(533:1:543); % Correct tick marks for clarity
    ylim([-100, 5]);   % Normalize to dB scale

elseif Freq_Time_Selector == 1
    % Plot Time Domain
    t_ref = (0:length(IQ_complex_ref)-1) / Fs; % Time axis in seconds
    t_sur = (0:length(IQ_complex_sur)-1) / Fs; % Time axis in seconds
    t_plot_ref = t_ref(1:5000); % Limit to first 5000 samples for clarity
    t_plot_sur = t_sur(1:5000); % Limit to first 5000 samples for clarity

    figure(1);
    subplot(3,1,1);
    plot(t_plot_ref * 1e3, real(IQ_complex_ref(1:5000)), 'b'); 
    xlabel('Time (ms)');
    ylabel('Amplitude');
    title('Raw Reference Signal (Time Domain)');
    grid on;
    
    subplot(3,1,2);
    plot(t_plot_sur * 1e3, real(IQ_complex_sur(1:5000)), 'r'); 
    xlabel('Time (ms)');
    ylabel('Amplitude');
    title('Raw Surveillance Signal (Time Domain)');
    grid on;
end


%% Inject Fake Moving Targets

% This feature is for simulation purposes only
% Disable this feature field tests
if Inject_Targets == 1
    disp('Injecting Fake Targets...');
    
    % Fake target params defined above
    
    % Time Vector
    t = (0:length(IQ_complex_sur)-1)' / Fs;
    
    % Target 1 Injection
    delay_samples_1 = round((target_range_1 / c) * Fs);
    doppler_1 = (2 * target_velocity_1 * Fc) / c;
    echo_1 = [zeros(delay_samples_1, 1); IQ_complex_sur(1:end - delay_samples_1)] .* exp(1j * 2 * pi * doppler_1 * t);
    
    % Target 2 Injection
    delay_samples_2 = round((target_range_2 / c) * Fs);
    doppler_2 = (2 * target_velocity_2 * Fc) / c;
    echo_2 = [zeros(delay_samples_2, 1); IQ_complex_sur(1:end - delay_samples_2)] .* exp(1j * 2 * pi * doppler_2 * t);
    
    % Target 3 Injection
    delay_samples_3 = round((target_range_3 / c) * Fs);
    doppler_3 = (2 * target_velocity_3 * Fc) / c;
    echo_3 = [zeros(delay_samples_3, 1); IQ_complex_sur(1:end - delay_samples_3)] .* exp(1j * 2 * pi * doppler_3 * t);
    
    % Add All Targets to Surveillance Signal
    IQ_complex_sur = IQ_complex_sur + target_rcs_1 * echo_1 + target_rcs_2 * echo_2 + target_rcs_3 * echo_3;
end

%% Apply NLMS Adaptive Filtering to Remove Reference DPI from Surveillance

if DPI_Removal_Selector == 1
    disp('Applying NLMS Adaptive Filter...');

    tic; % Start NLMS processing timer
    
    filterOrder = 256; % Keep the same order
    mu = 0.005; % Adaptation step
    
    nlms = dsp.LMSFilter(filterOrder, 'StepSizeSource', 'Input port', 'Method', 'Normalized LMS');
    
    % Apply NLMS Adaptive Filter
    [~, IQ_clean_sur] = nlms(IQ_complex_ref, IQ_complex_sur, mu);
    
    % Compute FFT & Shift
    spectrum_sur_adp = fftshift(abs(fft(IQ_clean_sur, NFFT)));
    
    % Normalize Spectra to Avoid log(0) Issues
    spectrum_sur_adp = spectrum_sur_adp / max(spectrum_sur_adp(spectrum_sur_adp > 0));
    
    if Freq_Time_Selector == 0
        subplot(3,1,3);
        plot(freqAxis_ref_sur, 20*log10(spectrum_sur_adp), 'g');
        xlabel('Frequency (MHz)');
        ylabel('Magnitude (dB)');
        title('Surveillance Spectrum After NLMS Adaptive Filtering (Frequency Domain)');
        grid on;
        ylim([-100, 5]);
    elseif Freq_Time_Selector == 1
        t_clean = (0:length(IQ_clean_sur)-1) / Fs; % Time axis in seconds
        t_plot_clean = t_clean(1:5000); % Limit to first 5000 samples for clarity

        subplot(3,1,3);
        plot(t_plot_clean * 1e3, real(IQ_clean_sur(1:5000)), 'g'); 
        xlabel('Time (ms)');
        ylabel('Amplitude');
        title('Surveillance After NLMS Adaptive Filtering (Time Domain)');
        grid on;
    end
    
    procTimeNLMS = toc; % End NLMS processing timer
end

%% Apply FFT Division to Remove Reference DPI from Surveillance

if DPI_Removal_Selector == 2
    disp('Applying FFT Division...');

    tic; % Start FFT division processing timer
    
    epsilon = 1e-2; % Small const to prevent division by zero
    X_ref = fft(IQ_complex_ref, NFFT);
    X_sur = fft(IQ_complex_sur, NFFT);
    X_clean = X_sur ./ (X_ref + epsilon); % Frequency domain division
    
    % Convert back to time domain using IFFT
    IQ_clean_sur = ifft(X_clean, NFFT);
    
    % Compute & plot frequency spectrum after FFT division
    spectrum_clean_sur = fftshift(abs(fft(IQ_clean_sur, NFFT)));
    
    % Normalize to avoid log(0) errors
    spectrum_clean_sur = spectrum_clean_sur / max(spectrum_clean_sur(spectrum_clean_sur > 0));
    
    % Plot
    if Freq_Time_Selector == 0
        subplot(3,1,3);
        plot(freqAxis_ref_sur, 20*log10(spectrum_clean_sur / max(spectrum_clean_sur)), 'g');
        xlabel('Frequency (MHz)'); ylabel('Magnitude (dB)');
        title('Surveillance Spectrum After FFT Division (Frequency Domain)'); grid on;
        xlim([min(freqAxis_ref_sur) max(freqAxis_ref_sur)]); ylim([-100, 5]);
    elseif Freq_Time_Selector == 1
        t_clean = (0:length(IQ_clean_sur)-1) / Fs; % Time axis in seconds
        t_plot_clean = t_clean(1:5000); % Limit to first 5000 samples for clarity

        subplot(3,1,3);
        plot(t_plot_clean * 1e3, real(IQ_clean_sur(1:5000)), 'g'); 
        xlabel('Time (ms)');
        ylabel('Amplitude');
        title('Surveillance After FFT Division (Time Domain)');
        grid on;
    end
    
    procTimeFFTDiv = toc; % End FFT division processing timer
end

%% Apply Wiener Filtering to Remove Reference DPI from Surveillance

if DPI_Removal_Selector == 3
    disp('Applying Wiener Filter...');

    tic; % Start Wiener processing timer
    
    % Compute Wiener filter coefficients
    H_wiener = (abs(fft(IQ_complex_ref, NFFT)).^2) ./ ...
               (abs(fft(IQ_complex_ref, NFFT)).^2 + abs(fft(IQ_complex_sur, NFFT)).^2);
    
    % Apply Wiener filtering in frequency domain
    X_clean = fft(IQ_complex_sur, NFFT) .* (1 - H_wiener);
    
    % Convert back to time domain using IFFT
    IQ_clean_sur = ifft(X_clean, NFFT);
    
    % Compute & plot frequency spectrum after Wiener filtering
    spectrum_clean_sur = fftshift(abs(fft(IQ_clean_sur, NFFT)));
    
    % Normalize to avoid log(0) errors
    spectrum_clean_sur = spectrum_clean_sur / max(spectrum_clean_sur(spectrum_clean_sur > 0));
    
    if Freq_Time_Selector == 0
        % Plot
        subplot(3,1,3);
        plot(freqAxis_ref_sur, 20*log10(spectrum_clean_sur), 'g');
        xlabel('Frequency (MHz)'); ylabel('Magnitude (dB)');
        title('Surveillance Spectrum After Wiener Filtering (Frequency Domain)'); grid on;
        xlim([min(freqAxis_ref_sur) max(freqAxis_ref_sur)]); ylim([-100, 5]);
    elseif Freq_Time_Selector == 1
        t_clean = (0:length(IQ_clean_sur)-1) / Fs; % Time axis in seconds
        t_plot_clean = t_clean(1:5000); % Limit to first 5000 samples for clarity

        subplot(3,1,3);
        plot(t_plot_clean * 1e3, real(IQ_clean_sur(1:5000)), 'g'); 
        xlabel('Time (ms)');
        ylabel('Amplitude');
        title('Surveillance After Wiener Filtering (Time Domain)');
        grid on;
    end
    
    procTimeWiener = toc; % End Wiener processing timer
end

%% Compute Reference DPI Removal Algorithm Efficiency

disp('Computing Algorithm Efficiency...');

if DPI_Removal_Selector ~= 0
    snrVal = snr(IQ_complex_sur(1:min(end, length(IQ_clean_sur))), IQ_clean_sur(1:min(end, length(IQ_complex_sur))));

    figure(2); 
    clf;

    yyaxis left;
    if DPI_Removal_Selector == 1
    bar(1, procTimeNLMS, 0.4, 'FaceColor', [0.2 0.6 0.8]);
    ylim([0, 120]);
    elseif DPI_Removal_Selector == 2
    bar(1, procTimeFFTDiv, 0.4, 'FaceColor', [0.2 0.6 0.8]);
    ylim([0, 120]);
    elseif DPI_Removal_Selector == 3
    bar(1, procTimeWiener, 0.4, 'FaceColor', [0.2 0.6 0.8]);
    ylim([0, 120]);
    end
    ylabel('Processing Time (s)');

    yyaxis right;
    bar(1.5, snrVal, 0.4, 'FaceColor', [0.8 0.4 0.4]);
    ylabel('SNR (dB)');
    ylim([0, 20]);
end

%% Matched Filtering & Range Doppler Processing

disp('Matched Filtering and Range Doppler Processing...')

% Define range doppler params
ts = 1 / Fs; % Sample period
Nt = min(length(IQ_complex_ref)); % Number of slow time samples
Nf = 1024; % Number of fast time samples
rdNFFT = 1024; % Size of range doppler 2d sqaure array (rdNFFT x rdNFFT)
Nstep = rdNFFT/2; % Sliding window size (50% overlap)
ND = floor((Nt-rdNFFT)/Nstep); % Number of frames in range doppler map
% Create empty arrays to hold reference and surveillance data
sig_ref = zeros(Nf,rdNFFT);
sig_sur = zeros(Nf,rdNFFT);

disp('Performing 1D IQ to 2D IQ conversion...')

% Pre-allocate empty 2D RD array to hold the results for efficiency
IQ_rd_ref = complex(zeros(Nf, rdNFFT));
IQ_rd_sur = complex(zeros(Nf, rdNFFT));  

% Seperate signal to 2D of fast time and slow time domain 
for m = 1 : rdNFFT
    % IQ Row Array > IQ 2D Array
    IQ_rd_ref(:, m) = IQ_complex_ref((m-1)*Nf+1 : m*Nf);  % Take Nf samples at a time

    if DPI_Removal_Selector == 0
        IQ_rd_sur(:, m) = IQ_complex_sur((m-1)*Nf+1 : m*Nf);  % (Non-filtered) Take Nf samples at a time
    elseif DPI_Removal_Selector == 1 | 2 | 3
        IQ_rd_sur(:, m) = IQ_clean_sur((m-1)*Nf+1 : m*Nf); % (Filtered) Take Nf samples at a time
    end
end

disp('Matched Filtering...');

% Go into frequency domain
% Using a zero-padding FFT
% That is, the resolution is 2*Nf = 2048
% Instead of Nf = 1024 for a 1024 x 1024 RD square array
spectrum_rd_ref = fft(IQ_rd_ref,2*Nf);
spectrum_rd_sur = fft(IQ_rd_sur,2*Nf);
% The above operation will result in an RD array of dimensions 2048 x 1024
% More range bins of frequency x-axis due to the resolution being 2*Nf
% Amplitude y-axis remains the same (1024)

% Range compression (fast-time FFT) via matched filtering > Go back to time domain 
% Matched filter output is useful only in time domain
spectrum_rd_pc = ifft(spectrum_rd_sur .* conj(spectrum_rd_ref));

disp('Range Doppler Processing...')

%  === Layout Definitions ===
% This layout will contain the RD map & target peak visualization
% Create combined figure for RD map and target peak visualization
fig = figure(3);
tile = tiledlayout(1, 6, 'TileSpacing', 'compact', 'Padding', 'compact'); 
axRD = nexttile(tile, [1 4]);  % RD map spans 4 out of 6 columns
axPK = nexttile(tile, [1 2]);  % Target peak uses last 2 columns

% Button params
% Buttons to be overlaid on top of figure
btnY = 0.10; % 10% above bottom of figure window
btnW = 0.03; % Button width
btnH = 0.04; % Button height

% UI controls (centered near bottom)
prevButton = uicontrol('Style','pushbutton','String','⏮', ...
    'Units','normalized','Position',[0.18 btnY btnW btnH],'FontSize',12);

frameInput = uicontrol('Style','edit','String','1', ...
    'Units','normalized','Position',[0.28 btnY 0.05 0.04],'FontSize',12);

goButton = uicontrol('Style','pushbutton','String','Go', ...
    'Units','normalized','Position',[0.38 btnY btnW btnH],'FontSize',12);

nextButton = uicontrol('Style','pushbutton','String','⏭', ...
    'Units','normalized','Position',[0.48 btnY btnW btnH],'FontSize',12);

% Button callback definitions
goButton.Callback = @(~,~) updateFrame( ...
    str2double(get(frameInput, 'String')), ...
    axRD, axPK, spectrum_rd_pc, ...
    Nf, rdNFFT, c, Fs, Fc, ND, ...
    Nstep, IQ_complex_ref, IQ_clean_sur, ...
    frameInput, goButton, prevButton, nextButton);

prevButton.Callback = @(~,~) stepFrame(-1, ...
    axRD, axPK, spectrum_rd_pc, ...
    Nf, rdNFFT, c, Fs, Fc, ND, ...
    Nstep, IQ_complex_ref, IQ_clean_sur, ...
    frameInput, goButton, prevButton, nextButton);

nextButton.Callback = @(~,~) stepFrame(+1, ...
    axRD, axPK, spectrum_rd_pc, ...
    Nf, rdNFFT, c, Fs, Fc, ND, ...
    Nstep, IQ_complex_ref, IQ_clean_sur, ...
    frameInput, goButton, prevButton, nextButton);

% Initialize current frame index
currentFrame = 1;
% Show first frame by default
updateFrame(currentFrame, axRD, axPK, spectrum_rd_pc, Nf, rdNFFT, c, Fs, Fc, ND, ...
            Nstep, IQ_complex_ref, IQ_clean_sur, ...
            frameInput, goButton, prevButton, nextButton);

%% Extract Strongest Target Peak Frame
% Define tuning params
lag_thresh = 10;      % Ignore peaks within ±10 samples (likely direct path)
amp_thresh = 0.7;     % Minimum cross-corr peak amplitude for detection

findNonZeroLagPeaks(IQ_complex_ref, IQ_clean_sur, Nf, Nstep, ND, lag_thresh, amp_thresh);

%% End
disp('End of Passive Radar Processing')

%% Function Definitions

% Doppler processing (slow-time FFT)
function updateFrame(n, axRD, axPK, spectrum_rd_pc, ...
                     Nf, rdNFFT, c, Fs, Fc, ND, ...
                     Nstep, IQ_complex_ref, IQ_clean_sur, ...
                     frameInput, goButton, prevButton, nextButton)
    
    % Disable controls while processing
    set([frameInput, goButton, prevButton, nextButton], 'Enable', 'off');

    n = max(1, min(ND, round(n)));  % Bound check

    % === Range Doppler Filtering ===
    
    % Apply FFT along columns with default FFT size then center the zero doppler 
    % around ref IO center freq (538MHz)
    RD = fftshift(fft(spectrum_rd_pc(), [], 2), 2);
    
    % Dynamic RD map color tuning for target visibility
    rd_db = 20*log10(abs(RD) + 1e-6);
    low_clip = prctile(rd_db(:), 98) - 30;
    high_clip = prctile(rd_db(:), 99.9);
    
    % Range axis
    range_axis = (0:2*Nf-1) * c / Fs;
    
    % Doppler axis
    doppler_freqs = fftshift(linspace(-Fs/2, Fs/2, rdNFFT));
    doppler_axis = - doppler_freqs * (c / (2 * Fc)) * 3.6;
    
    % Plot RD map
    imagesc(axRD, doppler_axis, range_axis / 1e3, rd_db);
    clim(axRD, [low_clip, high_clip]);
    set(axRD, 'YDir', 'normal');
    title(axRD, sprintf('Range-Doppler Map (Frame %d / %d)', n, ND));
    xlabel(axRD, 'Doppler (km/h)');
    ylabel(axRD, 'Bistatic Range (km)');
    ylim(axRD, [0 5]);
    xlim(axRD, [-500 500]);
    colormap(axRD, 'turbo');
    colorbar(axRD);
    grid(axRD, 'on');
    
    % === Target peak visualization processing (matched filtering) ===
    
    % Check if sliding window exceeds length of IQ arrays
    offset_start_peak = (n - 1) * Nstep + 1;
    if offset_start_peak + Nf - 1 > length(IQ_complex_ref)
        disp('Sliding Window exceeded limits.');
        return;
    end
    
    % Pluck out the reference and surveillance current frame IQ data for matched filtering
    seg_ref = IQ_complex_ref(offset_start_peak : offset_start_peak + Nf - 1);
    seg_sur = IQ_clean_sur(offset_start_peak : offset_start_peak + Nf - 1);
    [xc, lags] = xcorr(seg_sur, seg_ref);
    [peakVal, idx] = max(abs(xc));
    peakLag = lags(idx);

    % Compute bistatic range from lag
    bistatic_range_m = abs(peakLag) * (3e8 / Fs);
    bistatic_range_km = bistatic_range_m / 1000;
    
    % Display in MATLAB console
    fprintf('Frame %d: lag = %d ⇒ Bistatic Range = %.2f km\n', n, peakLag, bistatic_range_km);

    
    % Plot target peaks in current frame
    plot(axPK, lags, abs(xc), 'LineWidth', 1.2);
    title(axPK, sprintf('Target Peak: lag = %d, amplitude = %.3f', peakLag, peakVal));
    xlabel(axPK, 'Lag (samples)');
    ylabel(axPK, '|Cross-Correlation|');
    grid(axPK, 'on');
    xlim(axPK, [-Nf, Nf]);

    % Enable controls after processing
    set([frameInput, goButton, prevButton, nextButton], 'Enable', 'on');
end

function stepFrame(direction, ...
                   axRD, axPK, spectrum_rd_pc, ...
                   Nf, rdNFFT, c, Fs, Fc, ND, ...
                   Nstep, IQ_complex_ref, IQ_clean_sur, ... 
                   frameInput, goButton, prevButton, nextButton)

    % Parse current frame from the textbox
    n = str2double(get(frameInput, 'String'));
    n = n + direction;
    n = max(1, min(ND, round(n)));
    
    % Update text and plot
    set(frameInput, 'String', num2str(n));
    updateFrame(n, axRD, axPK, spectrum_rd_pc, ...
                   Nf, rdNFFT, c, Fs, Fc, ND, ...
                   Nstep, IQ_complex_ref, IQ_clean_sur, ...
                   frameInput, goButton, prevButton, nextButton);
end

function findNonZeroLagPeaks(IQ_complex_ref, IQ_clean_sur, Nf, Nstep, ND, lag_thresh, amp_thresh)
    % Scan all RD frames for significant non-zero lag peaks
    % and show only sustained peaks (≥ 10 frames)
    fprintf('Scanning all frames for strong, non-zero-lag target peaks...\n');
    
    peak_flags = false(1, ND);  % Flags to mark valid peak frames

    for n = 1:ND
        offset = (n - 1) * Nstep + 1;

        if offset + Nf - 1 > min(length(IQ_complex_ref), length(IQ_clean_sur))
            break;
        end
        
        % Extract frame segments
        seg_ref = IQ_complex_ref(offset : offset + Nf - 1);
        seg_sur = IQ_clean_sur(offset : offset + Nf - 1);

        % Cross-correlate
        [xc, lags] = xcorr(seg_sur, seg_ref);
        [peakVal, idx] = max(abs(xc));
        peakLag = lags(idx);

        % Mark frame if it satisfies both lag and amplitude threshold
        if abs(peakLag) > lag_thresh && peakVal >= amp_thresh
            peak_flags(n) = true;
        end
    end

    % Extract frame indices where conditions are met
    peak_frames = find(peak_flags);

    if isempty(peak_frames)
        disp('No strong non-zero lag peaks found.');
    else
        disp('Suggested interesting frame ranges to inspect (≥10 frames continuous):');
        showFrameRanges(peak_frames, 10);
    end
end

function showFrameRanges(frames, min_peak_len)
    frames = sort(frames(:));
    if isempty(frames)
        return;
    end

    ranges = {};
    start_idx = frames(1);
    count = 1;
    
    % From the array of frame numbers with cross correlation 
    % peaks > amp_thresh, find min_peak_len (or more) consecutive 
    % frames
    for i = 2:length(frames)
        if frames(i) == frames(i-1) + 1
            count = count + 1;
        else
            if count >= min_peak_len
                ranges{end+1} = sprintf('%d-%d', start_idx, frames(i-1));
            end
            start_idx = frames(i);
            count = 1;
        end
    end

    % Ensure consecutive frame length more than min_peak_len
    % Print frame ranges
    if count >= min_peak_len
        ranges{end+1} = sprintf('%d-%d', start_idx, frames(end));
    end

    if isempty(ranges)
        fprintf('No frame ranges ≥%d were found.\n', min_peak_len);
    else
        disp(strjoin(ranges, ', '));
    end
end