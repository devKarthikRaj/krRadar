% Convert SDRplay WAV to CSV for Bok Choy's AI denoising

% Select the WAV files
wavFile = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\MATLAB krRadar DSP SITL Test Code\Recordings\538mhz_10s.wav';
mFile = 'C:\Users\kraj4\Documents\NTU Stuff\FYP\MATLAB krRadar DSP SITL Test Code\Recordings\538mhz_10s.mat';

% Read the WAV files
disp('Loading WAV files...');
[iqData,Fs] = audioread(wavFile);

% Convert stereo channels to I and Q
I = iqData(:, 1); % First column is In-phase (I)
Q = iqData(:, 2);  % Second column is Quadrature (Q)

% Combine I and Q into complex format
IQ_Complex = I + 1j * Q;

% Write IQ_Complex to .M file
disp('Generating .M File...');
fileID = fopen(mFile, 'w');
fprintf(fileID, '%% IQ Data from WAV file\n');
fprintf(fileID, 'Fs = %.2f;\n', Fs);
fprintf(fileID, 'IQ_Complex = [\n');

for k = 1:length(IQ_Complex)
    fprintf(fileID, '%.6f + %.6fi;\n', real(IQ_Complex(k)), imag(IQ_Complex(k)));
end

fprintf(fileID, '];\n');
fclose(fileID);

disp(['.M file saved: ', mFile]);