function link = calculate_link_profile(cfg, pass)
%CALCULATE_LINK_PROFILE Simple per-point link budget over the pass.
%   link = CALCULATE_LINK_PROFILE(cfg, pass) computes FSPL, received power,
%   the cascaded receiver noise figure (Friis), noise power, SNR and Eb/N0 at
%   every point of the pass profile. These are plain link-budget equations,
%   not an RF circuit simulator.
%
%   RF chain (noise figure cascade, after the antenna): Filter -> LNA -> Cable -> SDR.

lb = cfg.link;

% Cascaded noise figure (Friis) for the post-antenna chain.
[nfTotal_dB, gainTotal_dB] = local_friis(lb.chain);

% Occupied bandwidth and information bit rate.
occupiedBW = cfg.symbolRate * (1 + cfg.rrcBeta);   % Hz
infoBitRate = cfg.symbolRate * cfg.codeRate;        % info bits/s

% Free-space path loss at each range point.
% FSPL(dB) = 20*log10(4*pi*d*f/c)
fspl_dB = 20 * log10(4 * pi * pass.range * cfg.carrierFreq / cfg.c);

% Elevation-scaled atmospheric loss (thicker slant path near the horizon).
elClamped = max(pass.el, 1);                        % avoid divide-by-zero
atmos_dB = lb.atmosLossZenith ./ sind(elClamped);

% Received power (dBm). EIRP is already Ptx + Gtx of the spacecraft.
prx_dBm = lb.satEIRP + lb.rxAntennaGain ...
        - fspl_dB - atmos_dB - lb.pointingLoss - lb.polarizationLoss;

% Noise power at the receiver (dBm) referred to the occupied bandwidth.
% N(dBm) = -174 dBm/Hz + NF(dB) + 10*log10(B)
noise_dBm = -174 + nfTotal_dB + 10 * log10(occupiedBW);

snr_dB  = prx_dBm - noise_dBm;                      % SNR in the occupied bandwidth
ebn0_dB = snr_dB + 10 * log10(occupiedBW / infoBitRate);

link = struct();
link.fspl_dB       = fspl_dB;
link.atmos_dB      = atmos_dB;
link.prx_dBm       = prx_dBm;
link.noise_dBm     = noise_dBm;
link.snr_dB        = snr_dB;
link.ebn0_dB       = ebn0_dB;
link.nfTotal_dB    = nfTotal_dB;
link.gainTotal_dB  = gainTotal_dB;
link.occupiedBW    = occupiedBW;
link.infoBitRate   = infoBitRate;

fprintf(['Link budget: Rx NF %.2f dB, occupied BW %.1f kHz, ', ...
         'Eb/N0 range %.1f..%.1f dB (median %.1f dB).\n'], ...
    nfTotal_dB, occupiedBW/1e3, min(ebn0_dB), max(ebn0_dB), median(ebn0_dB));
end

% ---------------------------------------------------------------------------
function [nf_dB, gain_dB] = local_friis(chain)
% Cascaded noise figure via Friis: F = F1 + (F2-1)/G1 + (F3-1)/(G1 G2) + ...
% Passive losses are represented as gains < 1 (F = 1/G for a matched attenuator).
f = 10.^([chain.nf] / 10);        % linear noise factors
g = 10.^([chain.gain] / 10);      % linear gains

fTotal = f(1);
gCascade = 1;
for k = 2:numel(f)
    gCascade = gCascade * g(k-1);
    fTotal = fTotal + (f(k) - 1) / gCascade;
end

nf_dB   = 10 * log10(fTotal);
gain_dB = 10 * log10(prod(g));
end
