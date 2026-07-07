function verdict = write_results(cfg, R)
%WRITE_RESULTS Evaluate the design checks, print the verdict, and save results.
%   verdict = WRITE_RESULTS(cfg, R) applies the fixed pass/revise checks to the
%   metrics collected by run_tool, prints which checks passed or failed with a
%   few plain observations, and writes results.txt and results.json.
%
%   This is deliberately not a recommendation engine: it just reports check
%   outcomes and a PASS/REVISE verdict.

thr = 0.90;

checks = struct('name', {}, 'pass', {}, 'detail', {});

% 1. Coarse Doppler correction covers the nominal Doppler seen in the pass.
c1 = R.maxAbsDopplerHz <= cfg.coarseDopplerRange;
checks(end+1) = local_chk('Coarse Doppler covers nominal', c1, ...
    sprintf('max |Doppler| %.0f Hz <= coarse range %.0f Hz', ...
        R.maxAbsDopplerHz, cfg.coarseDopplerRange));

% 2. Residual CFO search range is sufficient for the post-correction residual.
c2 = R.maxResidualHz <= cfg.residualCFOSearchRange;
checks(end+1) = local_chk('Residual CFO search sufficient', c2, ...
    sprintf('expected residual %.0f Hz <= search range +/-%.0f Hz', ...
        R.maxResidualHz, cfg.residualCFOSearchRange));

% 3. Sample rate is valid (integer sps and above the Nyquist requirement).
nyqNeed = 2 * (R.maxAbsDopplerHz + R.occupiedBW/2);
c3 = (cfg.sampleRate == cfg.symbolRate * cfg.sps) && (cfg.sampleRate >= nyqNeed);
checks(end+1) = local_chk('Sample rate valid', c3, ...
    sprintf('Fs %.0f Hz = %d sym/s x %d sps, need >= %.0f Hz', ...
        cfg.sampleRate, cfg.symbolRate, cfg.sps, nyqNeed));

% 4. Receiver synchronization success.
c4 = R.syncSuccess >= thr;
checks(end+1) = local_chk('Sync success >= 90%', c4, ...
    sprintf('%.1f%% (%d/%d frames)', 100*R.syncSuccess, R.nSync, R.nFrames));

% 5. CRC-valid frame recovery.
c5 = R.crcRecovery >= thr;
checks(end+1) = local_chk('CRC-valid recovery >= 90%', c5, ...
    sprintf('%.1f%% (%d/%d frames)', 100*R.crcRecovery, R.nCrcValid, R.nFrames));

% 6. Payload completeness.
c6 = R.completeness >= thr;
checks(end+1) = local_chk('Payload completeness >= 90%', c6, ...
    sprintf('%.1f%% (%d/%d bytes), exact match: %s', ...
        100*R.completeness, R.numRecovered, R.numTotalBytes, mat2str(R.exactMatch)));

allPass = all([checks.pass]);
verdict = 'REVISE';
if allPass
    verdict = 'PASS';
end

% -- Print report ----------------------------------------------------------
lines = {};
lines{end+1} = '============================================================';
lines{end+1} = ' SDR GROUND STATION -- PRE-DEPLOYMENT VERIFICATION RESULTS';
lines{end+1} = '============================================================';
lines{end+1} = sprintf('Carrier            : %.3f MHz', cfg.carrierFreq/1e6);
lines{end+1} = sprintf('Ground station     : %s (%.4f, %.4f)', cfg.gsName, cfg.gsLatitude, cfg.gsLongitude);
lines{end+1} = sprintf('Pass               : %s -> %s (%.0f s), peak el %.1f deg', ...
    R.passStart, R.passEnd, R.passDurationSec, R.peakEl);
lines{end+1} = sprintf('Frames transmitted : %d (%s)', R.nFrames, ...
    local_partial_str(R.partialRecovery));
lines{end+1} = sprintf('Eb/N0 over frames  : %.1f .. %.1f dB', R.minEbN0, R.maxEbN0);
lines{end+1} = '------------------------------------------------------------';
lines{end+1} = ' CHECKS';
lines{end+1} = '------------------------------------------------------------';
for k = 1:numel(checks)
    mark = 'FAIL';
    if checks(k).pass; mark = 'PASS'; end
    lines{end+1} = sprintf('  [%s] %-32s | %s', mark, checks(k).name, checks(k).detail); %#ok<AGROW>
end
lines{end+1} = '------------------------------------------------------------';
lines{end+1} = ' OBSERVATIONS';
lines{end+1} = '------------------------------------------------------------';
obs = local_observations(cfg, R, checks);
for k = 1:numel(obs)
    lines{end+1} = sprintf('  - %s', obs{k}); %#ok<AGROW>
end
lines{end+1} = '------------------------------------------------------------';
lines{end+1} = sprintf(' DESIGN VERDICT: %s', verdict);
lines{end+1} = '============================================================';

report = strjoin(lines, newline);
fprintf('%s\n', report);

% -- Save results ----------------------------------------------------------
if ~exist(cfg.outputDir, 'dir'); mkdir(cfg.outputDir); end
txtPath = fullfile(cfg.outputDir, cfg.resultsFile);
fid = fopen(txtPath, 'w');
fwrite(fid, report);
fclose(fid);

jsonStruct = struct();
jsonStruct.verdict = verdict;
for k = 1:numel(checks)
    key = matlab.lang.makeValidName(checks(k).name);
    jsonStruct.checks.(key) = struct('pass', checks(k).pass, 'detail', checks(k).detail);
end
jsonStruct.metrics = R;
jsonPath = fullfile(cfg.outputDir, cfg.resultsJson);
fid = fopen(jsonPath, 'w');
fwrite(fid, jsonencode(jsonStruct, 'PrettyPrint', true));
fclose(fid);

fprintf('Wrote %s and %s.\n', txtPath, jsonPath);
end

% ---------------------------------------------------------------------------
function c = local_chk(name, pass, detail)
c = struct('name', name, 'pass', logical(pass), 'detail', detail);
end

% ---------------------------------------------------------------------------
function s = local_partial_str(isPartial)
if isPartial
    s = 'partial: file did not fit the contact';
else
    s = 'full file fit the contact';
end
end

% ---------------------------------------------------------------------------
function obs = local_observations(cfg, R, checks)
obs = {};
if R.exactMatch
    obs{end+1} = 'Recovered file is byte-for-byte identical to the transmitted file.';
else
    obs{end+1} = 'Recovered file differs from the transmitted file (see completeness).';
end
obs{end+1} = sprintf(['Coarse Doppler quantized to %.0f Hz leaves up to %.0f Hz ', ...
    'residual, handled by the +/-%.0f Hz CFO search.'], ...
    cfg.coarseDopplerStep, R.maxResidualHz, cfg.residualCFOSearchRange);
if R.minEbN0 < 6
    obs{end+1} = 'Some frames fell below ~6 dB Eb/N0; low-elevation link margin is thin.';
else
    obs{end+1} = 'Eb/N0 stayed comfortably above the BPSK+FEC threshold for all frames.';
end
if all([checks.pass])
    obs{end+1} = 'All checks passed: the proposed configuration is verified for deployment.';
else
    failed = {checks(~[checks.pass]).name};
    obs{end+1} = ['Revise the design; failing checks: ', strjoin(failed, ', '), '.'];
end
end
