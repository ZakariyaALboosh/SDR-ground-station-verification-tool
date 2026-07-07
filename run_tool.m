function results = run_tool()
%RUN_TOOL Pre-deployment verification pipeline for the SDR ground station.
%   results = RUN_TOOL() runs the full pipeline end to end:
%       config -> payload -> TLE pass -> link budget -> frames ->
%       map frames onto the pass -> waveform -> channel -> receiver ->
%       reassemble payload -> I/Q export -> verdict.
%
%   It reuses simple, proven MATLAB / Communications Toolbox building blocks and
%   is written for MATLAB R2022b. Run it from this folder:  results = run_tool;

fprintf('\n=== SDR Ground Station Verification Tool ===\n\n');

cfg = load_config();
rng(cfg.randomSeed, 'twister');           % reproducible channel noise

% -- Inputs ----------------------------------------------------------------
payload = load_payload(cfg);
pass    = build_pass_profile(cfg);
link    = calculate_link_profile(cfg, pass);
frames  = build_frames(payload, cfg);

% -- Map frames onto the pass ---------------------------------------------
% Frames are transmitted sequentially from AOS. For each frame we find its
% midpoint time and use the nearest pass-profile point for Doppler and Eb/N0
% (constant over one frame -- acceptable for v1). Transmission stops at LOS.
passRelSec = seconds(pass.time - pass.startTime);
flush = cfg.constraintLength - 1;
guardSym = cfg.guardSymbols;

mapped = struct('frameIdx', {}, 'dopplerHz', {}, 'dopplerRate', {}, ...
                'ebn0_dB', {}, 'frameDurSec', {}, 'midSec', {});
tCursor = 0;
partial = false;
for k = 1:numel(frames)
    infoLen = numel(frames(k).infoBits);
    numFrameSym = cfg.preambleLength + (infoLen + flush) * 2;   % preamble + coded
    burstSym    = numFrameSym + 2 * guardSym;
    frameDur    = burstSym / cfg.symbolRate;

    if tCursor + frameDur > pass.durationSec
        partial = true;                    % file does not fit the remaining contact
        break;
    end

    midSec = tCursor + frameDur / 2;
    [~, idx] = min(abs(passRelSec - midSec));

    mapped(end+1) = struct( ...
        'frameIdx',    k, ...
        'dopplerHz',   pass.dopplerHz(idx), ...
        'dopplerRate', pass.dopplerRate(idx), ...
        'ebn0_dB',     link.ebn0_dB(idx), ...
        'frameDurSec', frameDur, ...
        'midSec',      midSec); %#ok<AGROW>

    tCursor = tCursor + frameDur;
end

nMapped = numel(mapped);
if nMapped == 0
    error('run_tool:noFramesFit', 'No frame fits inside the selected pass.');
end
fprintf('Mapped %d/%d frame(s) onto the pass%s.\n', nMapped, numel(frames), ...
    local_ternary(partial, ' (partial contact)', ''));

% -- Transmit, channel, receive -------------------------------------------
rxResults = struct('syncFound', {}, 'syncMetric', {}, 'estCFO', {}, ...
    'coarseDopplerHz', {}, 'headerValid', {}, 'crcValid', {}, ...
    'seq', {}, 'payloadLen', {}, 'payloadBytes', {});
iqAll = [];
maxResidual = 0;
for m = 1:nMapped
    k    = mapped(m).frameIdx;
    dopp = mapped(m).dopplerHz;
    ebn0 = mapped(m).ebn0_dB;

    burst = generate_waveform(frames(k).infoBits, cfg);

    % Coarse Doppler prediction, quantized to the coarse correction grid.
    coarseDopp = round(dopp / cfg.coarseDopplerStep) * cfg.coarseDopplerStep;

    [rx, ~] = apply_channel(burst, dopp, ebn0, cfg);
    res = run_receiver(rx, coarseDopp, cfg);

    rxResults(m) = res;
    iqAll = [iqAll; rx]; %#ok<AGROW>

    % Physical residual the CFO search must absorb: coarse quantization error
    % plus Doppler drift across half a frame.
    residual = abs(dopp - coarseDopp) + abs(mapped(m).dopplerRate) * mapped(m).frameDurSec / 2;
    maxResidual = max(maxResidual, residual);
end

nSync     = sum([rxResults.syncFound]);
nCrcValid = sum([rxResults.crcValid]);

% -- Reassemble payload ----------------------------------------------------
rec = reassemble_payload(rxResults, payload, cfg);

% -- Export I/Q recording --------------------------------------------------
if cfg.exportIQ
    extra = struct('num_frames', nMapped, ...
        'partial_contact', partial, ...
        'doppler_min_hz', min([mapped.dopplerHz]), ...
        'doppler_max_hz', max([mapped.dopplerHz]), ...
        'ebn0_min_db', min([mapped.ebn0_dB]), ...
        'ebn0_max_db', max([mapped.ebn0_dB]));
    export_iq_cf32(iqAll, cfg, extra);
end

% -- Collect metrics and evaluate the verdict ------------------------------
R = struct();
R.nFrames         = nMapped;
R.nSync           = nSync;
R.nCrcValid       = nCrcValid;
R.syncSuccess     = nSync / nMapped;
R.crcRecovery     = nCrcValid / nMapped;
R.completeness    = rec.completeness;
R.byteAccuracy    = rec.byteAccuracy;
R.exactMatch      = rec.exactMatch;
R.numTotalBytes   = rec.numTotalBytes;
R.numRecovered    = rec.numRecovered;
R.partialRecovery = partial;
R.maxAbsDopplerHz = max(abs([mapped.dopplerHz]));
R.maxResidualHz   = maxResidual;
R.occupiedBW      = link.occupiedBW;
R.minEbN0         = min([mapped.ebn0_dB]);
R.maxEbN0         = max([mapped.ebn0_dB]);
R.passStart       = datestr(pass.startTime, 'yyyy-mm-dd HH:MM:SS');
R.passEnd         = datestr(pass.endTime, 'HH:MM:SS');
R.passDurationSec = pass.durationSec;
R.peakEl          = pass.peakEl;

verdict = write_results(cfg, R);

results = struct('cfg', cfg, 'pass', pass, 'link', link, 'frames', frames, ...
    'mapped', mapped, 'rxResults', rxResults, 'recovered', rec, ...
    'metrics', R, 'verdict', verdict);

fprintf('\nDone. Verdict: %s\n\n', verdict);
end

% ---------------------------------------------------------------------------
function s = local_ternary(cond, a, b)
if cond; s = a; else; s = b; end
end
