% MATLAB Script: krRadar Digital Signal Processing (DSP) Chain Software In The Loop (SITL) Testing
clear;
close all;
clc;
figure;

% -------------------------------
% Stage 1                       |
% Wav to IQ                     |
% Processing                    |
%--------------------------------

% Select the WAV files
refWavFile = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\MATLAB krRadar DSP SITL Test Code\Recordings\538mhz_10s.wav';
surWavFile = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\MATLAB krRadar DSP SITL Test Code\Recordings\538mhz_10s.wav';

% Read the WAV files
disp('Loading WAV files...');
[iqDataRef, FsRef] = audioread(refWavFile);
[iqDataSur, FsSur] = audioread(surWavFile);

% Convert stereo channels to I and Q
Iref = iqDataRef(:, 1);  % First column is In-phase (I)
Qref = iqDataRef(:, 2);  % Second column is Quadrature (Q)
Isur = iqDataSur(:, 1);  % First column is In-phase (I)
Qsur = iqDataSur(:, 2);  % Second column is Quadrature (Q)

% Combine I and Q into complex format
IQ_Complex_Ref = Iref + 1j * Qref;
IQ_Complex_Sur = Isur + 1j * Qsur;

% Display sample rates
disp(['INFO: Reference Sample Rate = ', num2str(FsRef), ' Hz']);
disp(['INFO: Surveillance Sample Rate = ', num2str(FsSur), ' Hz']);

% FFT Parameters
NFFT = 4096; % Set FFT Resolution
freqAxis = linspace(-FsRef/2, FsRef/2, NFFT) / 1e6; % Frequency in MHz

% -------------------------------
% Stage 2                       |
% Wav to IQ                     |
% Visualization                 |
%--------------------------------

% Compute FFT & Shift
SpectrumRef = fftshift(abs(fft(IQ_Complex_Ref, NFFT)));
SpectrumSur = fftshift(abs(fft(IQ_Complex_Sur, NFFT)));

% Normalize Spectra to Avoid log(0) Issues - Squeeze the entire range to inbetween -1 and 1 
SpectrumRef = SpectrumRef / max(SpectrumRef(SpectrumRef > 0));
SpectrumSur = SpectrumSur / max(SpectrumSur(SpectrumSur > 0));

subplot(5,1,1);
hPlot1 = plot(freqAxis, 20*log10(SpectrumRef), 'b');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
title('Reference Signal Spectrum');
grid on;
xlim([min(freqAxis) max(freqAxis)]);
ylim([-100, 5]);

subplot(5,1,2);
hPlot2 = plot(freqAxis, 20*log10(SpectrumSur), 'r');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
title('Surveillance Signal Spectrum');
grid on;
xlim([min(freqAxis) max(freqAxis)]);
ylim([-100, 5]);

% -------------------------------------
% Stage 2                             |
% Reference and Surveillance Cleaning |
% Processing                          |
%--------------------------------------

% Low Pass Filter Design
fc = 1e6/2; % Desired cutoff frequency (Hz)
[b, a] = butter(4, fc/(FsRef/2)); % 4th order Butterworth low-pass filter

% Apply Low Pass Filter
Iref_LPF = filtfilt(b, a, Iref); % Filter I component
Qref_LPF = filtfilt(b, a, Qref); % Filter Q component
Isur_LPF = filtfilt(b, a, Isur); % Filter I component
Qsur_LPF = filtfilt(b, a, Qsur); % Filter Q component

% Combine filtered I and Q into complex format
IQ_Complex_Ref_LPF = Iref_LPF + 1j * Qref_LPF;
IQ_Complex_Sur_LPF = Isur_LPF  + 1j * Qsur_LPF;

% -------------------------------------
% Stage 2                             |
% Reference and Surveillance Cleaning |
% Visualization                       |
%--------------------------------------

% Compute FFT & Shift
SpectrumRef_LPF = fftshift(abs(fft(IQ_Complex_Ref_LPF, NFFT)));
SpectrumSur_LPF = fftshift(abs(fft(IQ_Complex_Sur_LPF, NFFT)));

% Normalize Spectra to Avoid log(0) Issues
SpectrumRef_LPF = SpectrumRef_LPF / max(SpectrumRef_LPF(SpectrumRef_LPF > 0));
SpectrumSur_LPF = SpectrumSur_LPF / max(SpectrumSur_LPF(SpectrumSur_LPF > 0));

subplot(5,1,3);
hPlot3 = plot(freqAxis, 20*log10(SpectrumRef_LPF), 'b');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
title('Reference Signal Spectrum LPF');
grid on;
xlim([min(freqAxis) max(freqAxis)]);
ylim([-100, 5]);

subplot(5,1,4);
hPlot4 = plot(freqAxis, 20*log10(SpectrumSur_LPF), 'r');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
title('Surveillance Signal Spectrum LPF');
grid on;
xlim([min(freqAxis) max(freqAxis)]);
ylim([-100, 5]);

% ---------------------------------
% Stage 3                         |
% Surveillance Adaptive Filtering |
% Processing                      |
%----------------------------------

% Make Ref and Sur LPF signal array the same size to prevent dimension mismatches
minLen = min(length(IQ_Complex_Ref_LPF), length(IQ_Complex_Sur_LPF));
IQ_Complex_Ref_LPF = IQ_Complex_Ref_LPF(1:minLen);
IQ_Complex_Sur_LPF = IQ_Complex_Sur_LPF(1:minLen);

% Parameters
mu = 0.0001; % Step size
filterOrder = 128; % Filter length

% Adaptive Filter Design (To remove DPI from Surveillance Signal)
lms = dsp.LMSFilter(filterOrder, 'StepSize', mu);

% Apply Adaptive LMS Filter (Surveillance = Input, Reference = Unwanted DPI Signal to Be Removed From Surveillance)
[~, IQ_Complex_Sur_Adp] = lms(IQ_Complex_Ref_LPF, IQ_Complex_Sur_LPF);

% ---------------------------------
% Stage 3                         |
% Surveillance Adaptive Filtering |
% Visualization                   |
%----------------------------------

% Compute FFT & Shift
SpectrumSur_Adp = fftshift(abs(fft(IQ_Complex_Sur_Adp, NFFT)));

% Normalize Spectra to Avoid log(0) Issues
SpectrumSur_Adp = SpectrumSur_Adp / max(SpectrumSur_Adp(SpectrumSur_Adp > 0));

subplot(5,1,5);
hPlot5 = plot(freqAxis, 20*log10(SpectrumSur_Adp), 'r');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
title('Surveillance Signal Adaptive Filter');
grid on;
xlim([min(freqAxis) max(freqAxis)]);
ylim([-100, 5]);

% ---------------------------------
% Stage 4                         |
% Matched Filtering               |
% Processing                      |
%----------------------------------

% Take the conjugate of the LPF'ed reference signal
% IQ_Complex_Ref_Conj = conj(IQ_Complex_Ref_LPF);

% Multiply conjugated LPF'ed reference signal with adaptive filtered surveillance signal
% IQ_Complex_Matched_Out = IQ_Complex_Ref_Conj .* IQ_Complex_Sur_Adp;