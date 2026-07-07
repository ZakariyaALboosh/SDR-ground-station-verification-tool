function pass = build_pass_profile(cfg)
%BUILD_PASS_PROFILE Propagate the TLE and extract one LEO pass geometry.
%   pass = BUILD_PASS_PROFILE(cfg) builds a satelliteScenario from the TLE in
%   cfg, finds visibility passes over the ground station, selects the pass with
%   the highest peak elevation, and returns per-second az/el/range plus the
%   derived range-rate and Doppler profile.
%
%   Doppler is computed with the R2022b-compatible method (NOT dopplershift):
%       [az, el, range, time] = aer(gs, sat);
%       rangeRate = gradient(range, sampleTime);
%       dopplerHz = -(rangeRate / c) * carrierFrequency;

stopTime = cfg.startTime + hours(cfg.scenarioHours);

sc  = satelliteScenario(cfg.startTime, stopTime, cfg.sampleTime);

% Write the TLE to a temporary file (with a corrected checksum) for tleread.
tleFile = local_write_tle(cfg);
cleanup = onCleanup(@() local_safe_delete(tleFile));
sat = satellite(sc, tleFile);

gs = groundStation(sc, ...
    'Name', cfg.gsName, ...
    'Latitude', cfg.gsLatitude, ...
    'Longitude', cfg.gsLongitude, ...
    'Altitude', cfg.gsAltitude, ...
    'MinElevationAngle', cfg.minElevation);

% Full-scenario look angles (spec's working method).
[az, el, rng, t] = aer(gs, sat);
az  = az(:);  el = el(:);  rng = rng(:);  t = t(:);

% Find visibility passes (contiguous samples with elevation >= min elevation).
visible = el >= cfg.minElevation;
[passStartIdx, passEndIdx] = local_find_runs(visible);

if isempty(passStartIdx)
    error('build_pass_profile:noPass', ...
        ['No pass above %.1f deg elevation found in a %d h window. ', ...
         'Adjust the ground station or scenario window in load_config.'], ...
        cfg.minElevation, cfg.scenarioHours);
end

% Select the pass with the highest peak elevation (best demonstration pass).
peakEl = zeros(numel(passStartIdx), 1);
for k = 1:numel(passStartIdx)
    peakEl(k) = max(el(passStartIdx(k):passEndIdx(k)));
end
[~, best] = max(peakEl);
i0 = passStartIdx(best);
i1 = passEndIdx(best);

idx = (i0:i1).';

% Range rate and Doppler over the selected pass.
% gradient() over the full range vector keeps the derivative well-conditioned
% at the pass edges, then we slice out the pass window.
rangeRateFull = gradient(rng, cfg.sampleTime);            % m/s
dopplerFull   = -(rangeRateFull / cfg.c) * cfg.carrierFreq; % Hz
dopRateFull   = gradient(dopplerFull, cfg.sampleTime);     % Hz/s

pass = struct();
pass.time        = t(idx);
pass.az          = az(idx);
pass.el          = el(idx);
pass.range       = rng(idx);
pass.rangeRate   = rangeRateFull(idx);
pass.dopplerHz   = dopplerFull(idx);
pass.dopplerRate = dopRateFull(idx);
pass.sampleTime  = cfg.sampleTime;
pass.startTime   = t(i0);
pass.endTime     = t(i1);
pass.durationSec = seconds(t(i1) - t(i0));
pass.peakEl      = max(pass.el);

fprintf(['Selected pass: %s -> %s (%.0f s), peak elevation %.1f deg, ', ...
         'max |Doppler| %.0f Hz.\n'], ...
    datestr(pass.startTime, 'HH:MM:SS'), datestr(pass.endTime, 'HH:MM:SS'), ...
    pass.durationSec, pass.peakEl, max(abs(pass.dopplerHz)));
end

% ---------------------------------------------------------------------------
function tleFile = local_write_tle(cfg)
% Write a two-line TLE file, recomputing the column-69 checksum so tleread
% always accepts it regardless of the literal supplied in load_config.
l1 = local_fix_checksum(cfg.tleLine1);
l2 = local_fix_checksum(cfg.tleLine2);

tleFile = [tempname, '.tle'];
fid = fopen(tleFile, 'w');
if fid < 0
    error('build_pass_profile:tleWrite', 'Could not create temporary TLE file.');
end
fprintf(fid, '%s\n%s\n%s\n', cfg.tleName, l1, l2);
fclose(fid);
end

% ---------------------------------------------------------------------------
function line = local_fix_checksum(line)
% Recompute the standard TLE modulo-10 checksum for the first 68 columns and
% overwrite column 69. Digits add their value, '-' adds 1, everything else 0.
line = char(line);
if numel(line) < 68
    error('build_pass_profile:badTLE', 'TLE line shorter than 68 columns.');
end
body = line(1:68);
s = 0;
for k = 1:numel(body)
    ch = body(k);
    if ch >= '0' && ch <= '9'
        s = s + (ch - '0');
    elseif ch == '-'
        s = s + 1;
    end
end
line = [body, char('0' + mod(s, 10))];
end

% ---------------------------------------------------------------------------
function local_safe_delete(f)
if exist(f, 'file')
    delete(f);
end
end

% ---------------------------------------------------------------------------
function [starts, ends] = local_find_runs(mask)
% Return start/end indices of each contiguous run of true values in mask.
mask = mask(:).';
d = diff([false, mask, false]);
starts = find(d == 1);
ends   = find(d == -1) - 1;
end
