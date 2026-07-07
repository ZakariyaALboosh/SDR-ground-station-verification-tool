function payload = load_payload(cfg)
%LOAD_PAYLOAD Read the input file to transmit as a raw byte vector.
%   payload = LOAD_PAYLOAD(cfg) reads cfg.payloadFile and returns its contents
%   as a uint8 column vector. This is the exact data the receiver must recover.

fid = fopen(cfg.payloadFile, 'rb');
if fid < 0
    error('load_payload:fileNotFound', ...
        'Could not open payload file "%s".', cfg.payloadFile);
end
cleanup = onCleanup(@() fclose(fid));

payload = fread(fid, Inf, 'uint8=>uint8');
payload = payload(:);

if isempty(payload)
    error('load_payload:emptyFile', ...
        'Payload file "%s" is empty.', cfg.payloadFile);
end

fprintf('Loaded payload "%s": %d bytes.\n', cfg.payloadFile, numel(payload));
end
