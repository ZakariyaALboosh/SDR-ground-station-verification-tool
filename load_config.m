function cfg = load_config()
%LOAD_CONFIG Central configuration for the SDR ground-station verification tool.
%   cfg = LOAD_CONFIG() returns a struct with every tunable parameter used by
%   the pipeline. Everything is kept in one place so the tool has a single,
%   readable point of control. Target environment: MATLAB R2022b,
%   Satellite Communications Toolbox 1.3, Communications Toolbox 7.8.

cfg = struct();

% ---------------------------------------------------------------------------
% Physical constants
% ---------------------------------------------------------------------------
cfg.c = 299792458;                 % speed of light [m/s]

% ---------------------------------------------------------------------------
% RF / carrier
% ---------------------------------------------------------------------------
cfg.carrierFreq = 437.5e6;         % downlink carrier [Hz] (UHF amateur-sat band)

% ---------------------------------------------------------------------------
% Waveform (BPSK + convolutional coding)
% ---------------------------------------------------------------------------
cfg.symbolRate   = 9600;           % channel symbol rate [sym/s]
cfg.sps          = 8;              % samples per symbol
cfg.sampleRate   = cfg.symbolRate * cfg.sps;   % complex baseband sample rate [Hz]
cfg.rrcBeta      = 0.35;           % root-raised-cosine roll-off
cfg.rrcSpan      = 10;             % RRC filter span [symbols]

% Rate-1/2, constraint length 7 convolutional code (industry standard).
cfg.constraintLength = 7;
cfg.codeGenerator    = [171 133];  % octal generator polynomials
cfg.codeRate         = 1/2;

% ---------------------------------------------------------------------------
% Framing (simple project-defined frame, NOT full CCSDS)
%   preamble | sync marker | seq(16) | length(16) | payload | CRC-16
% ---------------------------------------------------------------------------
cfg.preambleLength   = 64;         % known BPSK preamble symbols (sync + CFO aid)
cfg.preambleSeed     = 20240607;   % deterministic preamble generator seed
cfg.syncWord         = uint16(hex2dec('1ACF'));  % 16-bit sync marker
cfg.crcPolynomial    = 'z^16 + z^12 + z^5 + 1';  % CRC-16-CCITT
cfg.maxPayloadBytes  = 100;        % payload bytes per frame

% ---------------------------------------------------------------------------
% Receiver acquisition
% ---------------------------------------------------------------------------
cfg.coarseDopplerRange     = 12e3; % Hz, span the coarse Doppler stage can pre-correct
cfg.coarseDopplerStep      = 50;   % Hz, coarse pre-correction quantization grid
cfg.residualCFOSearchRange = 300;  % Hz, +/- residual carrier-offset search range
cfg.residualCFOSearchStep  = 5;    % Hz, residual search grid step
cfg.syncPeakThreshold      = 6;    % correlation peak / noise floor ratio for a valid sync

% ---------------------------------------------------------------------------
% Orbit / ground station
% ---------------------------------------------------------------------------
% Real ISS (ZARYA) two-line element set. The checksum digit (column 69) is
% recomputed when the file is written, so the orbital fields are what matter.
cfg.tleName  = 'ISS (ZARYA)';
cfg.tleLine1 = '1 25544U 98067A   24010.51782528  .00016717  00000-0  30074-3 0  9993';
cfg.tleLine2 = '2 25544  51.6416 247.4627 0006703 130.5360 325.0288 15.49309239 20631';

% Ground station: Muscat, Oman.
cfg.gsName        = 'Muscat GS';
cfg.gsLatitude    = 23.5880;       % deg
cfg.gsLongitude   = 58.3829;       % deg
cfg.gsAltitude    = 20;            % m
cfg.minElevation  = 10;            % deg, LOS/AOS threshold

% Scenario window: start at TLE epoch (2024-01-10 ~12:25 UTC) and search 12 h.
cfg.startTime    = datetime(2024,1,10,12,25,0,'TimeZone','UTC');
cfg.scenarioHours = 12;
cfg.sampleTime   = 1;              % s, orbit sampling step

% ---------------------------------------------------------------------------
% Link budget
% ---------------------------------------------------------------------------
lb = struct();
lb.satEIRP        = 14;    % dBm, spacecraft EIRP (e.g. ~1 W + modest antenna)
lb.rxAntennaGain  = 15;    % dBi, ground station antenna (e.g. UHF Yagi)
lb.pointingLoss   = 1.0;   % dB
lb.atmosLossZenith = 0.5;  % dB at zenith (scaled by 1/sin(el))
lb.polarizationLoss = 1.0; % dB

% RF chain after the antenna: Filter -> LNA -> Cable -> SDR.
% Each stage: gain in dB (loss is negative gain) and noise figure in dB.
lb.chain = struct( ...
    'name', {'Filter','LNA','Cable','SDR'}, ...
    'gain', {  -0.5,   25,   -3.0,   0  }, ...
    'nf',   {   0.5,  0.8,    3.0,   6.0});

lb.refTemp = 290;          % K, reference temperature for noise figure
cfg.link = lb;

% ---------------------------------------------------------------------------
% Outputs
% ---------------------------------------------------------------------------
cfg.payloadFile   = 'message.txt';
cfg.outputDir     = 'output';
cfg.exportIQ      = true;
cfg.iqFile        = 'received_iq.cf32';
cfg.iqMetaFile    = 'iq_metadata.json';
cfg.recoveredFile = 'recovered.txt';
cfg.resultsFile   = 'results.txt';
cfg.resultsJson   = 'results.json';

% Guard interval (silence) placed around each frame burst in the recording.
cfg.guardSymbols  = 16;

% Reproducible channel noise.
cfg.randomSeed    = 12345;
end
