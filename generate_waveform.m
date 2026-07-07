function [burst, info] = generate_waveform(infoBits, cfg)
%GENERATE_WAVEFORM Build one baseband frame burst (BPSK + convolutional code).
%   [burst, info] = GENERATE_WAVEFORM(infoBits, cfg) convolutionally encodes the
%   frame information bits, maps them to BPSK, prepends the known preamble,
%   applies root-raised-cosine pulse shaping and pads the burst with guard
%   silence. The result is a complex baseband column vector at cfg.sampleRate.
%
%   info returns the piece counts used by the receiver-side reference.

persistent trellis rrc
if isempty(trellis)
    trellis = poly2trellis(cfg.constraintLength, cfg.codeGenerator);
    rrc = rcosdesign(cfg.rrcBeta, cfg.rrcSpan, cfg.sps, 'sqrt');
end

infoBits = infoBits(:);

% Terminate the convolutional code with (K-1) flush bits so the trellis
% returns to the zero state at the end of the frame.
flush = zeros(cfg.constraintLength - 1, 1);
coded = convenc([infoBits; flush], trellis);

% BPSK mapping: 0 -> +1, 1 -> -1.
codedSymbols = 1 - 2 * coded;

% Known preamble in front for timing acquisition and residual CFO estimation.
[~, preSymbols] = get_preamble(cfg);

txSymbols = [preSymbols; codedSymbols];

% Pulse shaping.
up   = upsample(txSymbols, cfg.sps);
wave = conv(up, rrc, 'full');

% Guard silence around the burst (models the gap between frame bursts).
guardSamps = cfg.guardSymbols * cfg.sps;
burst = [zeros(guardSamps, 1); wave; zeros(guardSamps, 1)];

info = struct();
info.numPreambleSymbols = numel(preSymbols);
info.numCodedSymbols    = numel(codedSymbols);
info.numFrameSymbols    = numel(txSymbols);
info.guardSamples       = guardSamps;
info.filterDelay        = (numel(rrc) - 1) / 2;   % samples, one-sided RRC delay
end
