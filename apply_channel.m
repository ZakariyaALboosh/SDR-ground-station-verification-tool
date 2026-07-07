function [rx, chan] = apply_channel(burst, dopplerHz, ebn0_dB, cfg)
%APPLY_CHANNEL Apply constant Doppler and Eb/N0-scaled AWGN to one frame burst.
%   [rx, chan] = APPLY_CHANNEL(burst, dopplerHz, ebn0_dB, cfg) shifts the burst
%   by a constant carrier offset (Doppler, treated as constant over one frame),
%   adds a small random timing offset, and adds complex AWGN scaled so that the
%   post-receiver Eb/N0 matches the link-budget value ebn0_dB.
%
%   Per-sample SNR relates to Eb/N0 by:
%       SNR_dB = Eb/N0 + 10log10(k) + 10log10(codeRate) - 10log10(sps)
%   with k = 1 bit/symbol for BPSK.

burst = burst(:);
guardSamps = cfg.guardSymbols * cfg.sps;

% Random whole-sample timing offset so the receiver must acquire the burst
% rather than rely on a fixed index.
jitter = randi([0, 2 * cfg.sps]);
x = [zeros(jitter, 1); burst];
N = numel(x);

% Constant Doppler over the frame.
t = (0:N-1).' / cfg.sampleRate;
x = x .* exp(1j * 2 * pi * dopplerHz * t);

% Signal power measured on the active (non-guard) region only.
active = burst(guardSamps+1 : end-guardSamps);
Ps = mean(abs(active).^2);

% Target per-sample SNR and matching complex-noise variance.
snr_dB = ebn0_dB + 10*log10(cfg.codeRate) - 10*log10(cfg.sps);
snr_lin = 10^(snr_dB / 10);
noiseVar = Ps / snr_lin;                       % total complex noise power

noise = sqrt(noiseVar/2) * (randn(N,1) + 1j*randn(N,1));
rx = x + noise;

chan = struct();
chan.dopplerHz  = dopplerHz;
chan.ebn0_dB    = ebn0_dB;
chan.snr_dB     = snr_dB;
chan.jitter     = jitter;
chan.noiseVar   = noiseVar;
end
