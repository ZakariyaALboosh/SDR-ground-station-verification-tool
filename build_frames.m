function frames = build_frames(payload, cfg)
%BUILD_FRAMES Split the payload into simple CRC-protected frames.
%   frames = BUILD_FRAMES(payload, cfg) segments the uint8 payload into frames
%   of at most cfg.maxPayloadBytes and returns a struct array. Each frame:
%
%       sync marker (16) | seq number (16) | payload length (16) | payload | CRC-16
%
%   The CRC covers the sync marker, header and payload. The returned struct
%   carries both the byte layout and the information-bit vector (header + payload
%   + CRC) that the waveform generator will convolutionally encode. The known
%   preamble is added later, in generate_waveform.

payload = payload(:);
nBytes  = numel(payload);
nFrames = ceil(nBytes / cfg.maxPayloadBytes);

crcGen = comm.CRCGenerator('Polynomial', cfg.crcPolynomial);

frames = struct('seq', {}, 'payloadBytes', {}, 'payloadLen', {}, ...
                'infoBits', {}, 'crc', {});

for k = 1:nFrames
    a = (k-1) * cfg.maxPayloadBytes + 1;
    b = min(k * cfg.maxPayloadBytes, nBytes);
    chunk = payload(a:b);
    seq   = k - 1;                       % 0-based sequence number

    % Header + payload as a bit column (MSB first per field/byte).
    syncBits = local_u16_bits(double(cfg.syncWord));
    seqBits  = local_u16_bits(seq);
    lenBits  = local_u16_bits(numel(chunk));
    dataBits = local_bytes_bits(chunk);

    % Force double so comm.CRCGenerator accepts the input (de2bi may return
    % uint8, which would promote the whole concatenation to uint8).
    protectedBits = double([syncBits; seqBits; lenBits; dataBits]);

    % CRC-16 over the protected bits; comm.CRCGenerator appends the checksum.
    withCrc = crcGen(protectedBits);
    crcBits = withCrc(end-15:end);

    frames(k).seq          = seq;
    frames(k).payloadBytes = chunk;
    frames(k).payloadLen   = numel(chunk);
    frames(k).infoBits     = withCrc;    % protected bits followed by CRC-16
    frames(k).crc          = local_bits_u16(crcBits);
end

fprintf('Built %d frame(s) from %d payload bytes (<= %d bytes/frame).\n', ...
    nFrames, nBytes, cfg.maxPayloadBytes);
end

% ---------------------------------------------------------------------------
function bits = local_u16_bits(value)
% 16-bit unsigned value -> column of bits, MSB first.
bits = double(bitget(uint16(value), 16:-1:1)).';
end

% ---------------------------------------------------------------------------
function value = local_bits_u16(bits)
% 16 bits (MSB first) -> uint16 value.
value = uint16(0);
for i = 1:16
    value = bitor(bitshift(value, 1), uint16(bits(i)));
end
end

% ---------------------------------------------------------------------------
function bits = local_bytes_bits(bytes)
% uint8 column -> column of bits, MSB first within each byte.
bytes = uint8(bytes(:));
b = double(de2bi(bytes, 8, 'left-msb'));   % rows = bytes, cols = bits (as double)
bits = reshape(b.', [], 1);
end
