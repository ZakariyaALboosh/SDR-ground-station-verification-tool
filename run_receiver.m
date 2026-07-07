function result = run_receiver(rx, coarseDopplerHz, cfg)
%RUN_RECEIVER Acquire, correct, demodulate and decode one received frame burst.
%   result = RUN_RECEIVER(rx, coarseDopplerHz, cfg) implements the pre-hardware
%   receiver chain:
%       1. coarse Doppler correction using the predicted (quantized) Doppler
%       2. root-raised-cosine matched filter
%       3. preamble correlation for timing/frame synchronization
%       4. residual carrier frequency offset (CFO) search over the preamble
%       5. phase de-rotation (resolves the BPSK sign ambiguity)
%       6. BPSK demodulation + Viterbi decoding of the rate-1/2 conv code
%       7. header parse and CRC-16 check
%
%   result is a struct describing what the receiver recovered from this burst.

persistent trellis rrc crcDet
if isempty(trellis)
    trellis = poly2trellis(cfg.constraintLength, cfg.codeGenerator);
    rrc = rcosdesign(cfg.rrcBeta, cfg.rrcSpan, cfg.sps, 'sqrt');
    crcDet = comm.CRCDetector('Polynomial', cfg.crcPolynomial);
end

rx = rx(:);
sps = cfg.sps;
Ts  = 1 / cfg.symbolRate;           % symbol period
[~, preSymbols] = get_preamble(cfg);
P = numel(preSymbols);

result = local_empty_result();
result.coarseDopplerHz = coarseDopplerHz;

% -- 1. Coarse Doppler correction -----------------------------------------
N = numel(rx);
t = (0:N-1).' / cfg.sampleRate;
rxc = rx .* exp(-1j * 2 * pi * coarseDopplerHz * t);

% -- 2. Matched filter -----------------------------------------------------
mf = conv(rxc, rrc, 'full');

% -- 3. Preamble correlation (timing / sync) -------------------------------
sMax = numel(mf) - (P - 1) * sps;
if sMax < 1
    return;   % burst too short to contain a preamble
end
corrMag = zeros(sMax, 1);
n = (0:P-1).';
for s = 1:sMax
    seg = mf(s + n * sps);
    corrMag(s) = abs(sum(seg .* preSymbols));   % preSymbols are real +/-1
end
[peak, sBest] = max(corrMag);
floorLevel = median(corrMag) + eps;
peakRatio = peak / floorLevel;

result.syncMetric = peakRatio;
result.syncFound  = peakRatio >= cfg.syncPeakThreshold;
if ~result.syncFound
    return;
end

% -- 4. Residual CFO search over the preamble ------------------------------
preRx = mf(sBest + n * sps);
freqs = -cfg.residualCFOSearchRange : cfg.residualCFOSearchStep : cfg.residualCFOSearchRange;
cfoMetric = zeros(numel(freqs), 1);
for i = 1:numel(freqs)
    rot = exp(-1j * 2 * pi * freqs(i) * n * Ts);
    cfoMetric(i) = abs(sum(preRx .* rot .* preSymbols));
end
[~, iBest] = max(cfoMetric);
estCFO = freqs(iBest);
result.estCFO = estCFO;

% -- 5. Phase de-rotation from the (CFO-corrected) preamble ----------------
preRxc = preRx .* exp(-1j * 2 * pi * estCFO * n * Ts);
phase = angle(sum(preRxc .* preSymbols));

% -- 6. Extract & correct all data symbols, demodulate, decode -------------
dataIdx = (P:1:floor((numel(mf) - sBest) / sps)).';   % global symbol indices
if numel(dataIdx) < 2
    return;
end
dataSyms = mf(sBest + dataIdx * sps);
dataSyms = dataSyms .* exp(-1j * (2 * pi * estCFO * dataIdx * Ts + phase));

% BPSK hard decisions: +1 -> 0, -1 -> 1.
codedBits = double(real(dataSyms) < 0);

% Rate-1/2 code needs an even number of coded bits.
codedBits = codedBits(1:2*floor(numel(codedBits)/2));

tblen = 5 * (cfg.constraintLength - 1);
decoded = vitdec(codedBits, trellis, tblen, 'trunc', 'hard');

% -- 7. Header parse + CRC check ------------------------------------------
[ok, frame] = local_parse_frame(decoded, cfg, crcDet);
if ~ok
    return;
end

result.headerValid  = frame.headerValid;
result.seq          = frame.seq;
result.payloadLen   = frame.payloadLen;
result.payloadBytes = frame.payloadBytes;
result.crcValid     = frame.crcValid;
end

% ---------------------------------------------------------------------------
function r = local_empty_result()
r = struct('syncFound', false, 'syncMetric', 0, 'estCFO', NaN, ...
    'coarseDopplerHz', NaN, 'headerValid', false, 'crcValid', false, ...
    'seq', NaN, 'payloadLen', 0, 'payloadBytes', uint8([]));
end

% ---------------------------------------------------------------------------
function [ok, frame] = local_parse_frame(bits, cfg, crcDet)
% Parse: sync(16) | seq(16) | len(16) | payload | CRC-16 and verify the CRC.
ok = false;
frame = struct('headerValid', false, 'seq', NaN, 'payloadLen', 0, ...
    'payloadBytes', uint8([]), 'crcValid', false);

bits = bits(:);
if numel(bits) < 48 + 16
    return;
end

sync = local_bits_u16(bits(1:16));
seq  = local_bits_u16(bits(17:32));
len  = double(local_bits_u16(bits(33:48)));

frame.seq = double(seq);
frame.headerValid = (sync == cfg.syncWord) && (len >= 1) && (len <= cfg.maxPayloadBytes);
if ~frame.headerValid
    ok = true;   % we produced a result; it simply fails validation
    return;
end

need = 48 + 8*len + 16;
if numel(bits) < need
    ok = true;
    return;
end

payloadBits   = bits(49 : 48 + 8*len);
crcBits       = bits(48 + 8*len + 1 : need);
protectedBits = bits(1 : 48 + 8*len);

% CRC-16 check over [sync|seq|len|payload] against the received CRC.
[~, err] = crcDet(double([protectedBits; crcBits]));
frame.crcValid = (err == 0);

frame.payloadLen = len;
if frame.crcValid
    frame.payloadBytes = local_bits_bytes(payloadBits);
end

ok = true;
end

% ---------------------------------------------------------------------------
function value = local_bits_u16(bits)
value = uint16(0);
for i = 1:16
    value = bitor(bitshift(value, 1), uint16(bits(i)));
end
end

% ---------------------------------------------------------------------------
function bytes = local_bits_bytes(bits)
bits = bits(:);
nBytes = floor(numel(bits) / 8);
b = reshape(bits(1:8*nBytes), 8, nBytes).';   % rows = bytes, MSB first
bytes = uint8(bi2de(b, 'left-msb'));
end
