## Config File

The source of truth for the config file parameters is the [SDRplay API Specification](https://www.sdrplay.com/docs/SDRplay_API_Specification_v3.pdf).

Here is a list of available config parameters:

- **agcSetPoint** in dBfs has a default value of -60 dBfs, and can be set between -72 dBfs and 0 dBfs.

- **bandwidthNumber** in Hz has a default value of 50 Hz, and can be 0, 5, 50 or 100 Hz.

- **gainReduction** in dB has a default value of 40 dB, and can be set between 20 and 60.

- **lnaState** has a default value of 4, must be between 1 and 9.

- **dabNotch** is a bool, true turns on the DAB band notch filter (default false).

- **rfNotch** is a bool, true turns on the AM/FM band notch filter (default false).
