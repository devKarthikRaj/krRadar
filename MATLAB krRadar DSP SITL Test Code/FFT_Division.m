% Standalone FFT Division Test on DVB-T2 signal
% Goal: Remove Undesired DVB-T2 Reference Signal from Surveillance Signal
clear;
close all;
clc;

%% Read DVB-T2 data from WAV file to Complex IQ Buffer
disp('Loading WAV file...');

% Select the WAV files
file_ref = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\MATLAB krRadar DSP SITL Test Code\Recordings\538mhz_10s_ref.wav'; 
file_sur = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\MATLAB krRadar DSP SITL Test Code\Recordings\538mhz_10s_sur.wav'; 

% Read the WAV files
[iqData_ref, Fs_ref] = audioread(file_ref);
[iqData_sur, Fs_sur] = audioread(file_sur);

% Check for sample rate mismatch
if Fs_ref ~= Fs_sur
    error('Error: Reference and Surveillance Fs Mismatch');
end
Fs = Fs_ref; % Set common sampling rate
disp(['Sampling Rate (Fs) = ', num2str(Fs), ' Hz']);

% SDR Specfic Parameters
Fc = 538e6; % Center frequency of recording
visibleBandwidth = 10e6; % Frequency span = visible range = 10MHz around center freq 533 MHz to 543 MHz

% Convert stereo channels to I and Q
IQ_complex_ref = iqData_ref(:,1) + 1j * iqData_ref(:,2); % Reference Signal (IQ)
IQ_complex_sur = iqData_sur(:,1) + 1j * iqData_sur(:,2); % Surveillance Signal (IQ)

% FFT Parameters
NFFT = max(2^14, 2^nextpow2(min(length(IQ_complex_ref), length(IQ_complex_sur)))); % Ensure large NFFT

% Define frequency axis to match SDR software (533 MHz to 543 MHz)
freqAxis_ref_sur = linspace(Fc - visibleBandwidth/2, Fc + visibleBandwidth/2, NFFT) / 1e6; % Convert to MHz

% Compute FFT & Shift
spectrum_ref = fftshift(abs(fft(IQ_complex_ref, NFFT)));
spectrum_sur = fftshift(abs(fft(IQ_complex_sur, NFFT)));

% Normalize to avoid log(0) errors
spectrum_ref = spectrum_ref / max(spectrum_ref(spectrum_ref > 0));
spectrum_sur = spectrum_sur / max(spectrum_sur(spectrum_sur > 0));

% Plot Frequency Spectrum
figure;
subplot(3,1,1);
plot(freqAxis_ref_sur, 20*log10(spectrum_ref), 'b');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
title('Reference Spectrum');
grid on;
xlim([533, 543]); % Ensure correct range
xticks(533:1:543); % Correct tick marks for clarity
ylim([-100, 5]); % Normalize to dB scale

subplot(3,1,2);
plot(freqAxis_ref_sur, 20*log10(spectrum_sur), 'r');
xlabel('Frequency (MHz)');
ylabel('Magnitude (dB)');
title('Surveillance Spectrum');
grid on;
xlim([533, 543]); % Ensure correct range
xticks(533:1:543); % Correct tick marks for clarity
ylim([-100, 5]); % Normalize to dB scale

disp('WAV File Loaded');

%% Remove Reference DPI from Surveillance Using FFT Division
disp('Removing Reference DPI from Surveillance via FFT Division...');

epsilon = 1e-6; % Small value to prevent division by zero
X_ref = fft(IQ_complex_ref, NFFT);
X_sur = fft(IQ_complex_sur, NFFT);
X_clean = X_sur ./ (X_ref + epsilon); % Frequency-Domain Division

% Convert Back to Time Domain Using IFFT
IQ_clean = ifft(X_clean, NFFT);

% Compute & Plot Frequency Spectrum After FFT Division
spectrum_clean = fftshift(abs(fft(IQ_clean, NFFT)));

% Normalize to avoid log(0) errors
spectrum_clean = spectrum_clean / max(spectrum_clean(spectrum_clean > 0));

% Plot
subplot(3,1,3);
plot(freqAxis_ref_sur, 20*log10(spectrum_clean / max(spectrum_clean)), 'g');
xlabel('Frequency (MHz)'); ylabel('Magnitude (dB)');
title('Surveillance Signal Spectrum (After FFT Division)'); grid on;
xlim([min(freqAxis_ref_sur) max(freqAxis_ref_sur)]); ylim([-100, 5]);

disp('FFT Division-Based Interference Cancellation Complete');