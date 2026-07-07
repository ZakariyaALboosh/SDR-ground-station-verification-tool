function rec = reassemble_payload(rxResults, originalPayload, cfg)
%REASSEMBLE_PAYLOAD Rebuild the payload from CRC-valid received frames.
%   rec = REASSEMBLE_PAYLOAD(rxResults, originalPayload, cfg) orders the CRC-valid
%   frames by sequence number, concatenates their payloads, writes the recovered
%   file, and reports completeness against the original payload.

originalPayload = originalPayload(:);
nTotal = numel(originalPayload);

% Collect CRC-valid frames keyed by sequence number (first valid copy wins).
maxSeq = -1;
for k = 1:numel(rxResults)
    r = rxResults(k);
    if r.crcValid && ~isnan(r.seq)
        maxSeq = max(maxSeq, r.seq);
    end
end

recovered = uint8([]);
seqSeen = false(maxSeq + 1, 1);
if maxSeq >= 0
    parts = cell(maxSeq + 1, 1);
    for k = 1:numel(rxResults)
        r = rxResults(k);
        if r.crcValid && ~isnan(r.seq)
            idx = r.seq + 1;
            if ~seqSeen(idx)
                parts{idx} = r.payloadBytes(:);
                seqSeen(idx) = true;
            end
        end
    end
    % Concatenate contiguously from seq 0 up to the first gap (a missing frame
    % breaks byte-exact continuity of the file).
    for idx = 1:(maxSeq + 1)
        if ~seqSeen(idx)
            break;
        end
        recovered = [recovered; parts{idx}]; %#ok<AGROW>
    end
end

% Write the recovered file.
if ~exist(cfg.outputDir, 'dir'); mkdir(cfg.outputDir); end
outPath = fullfile(cfg.outputDir, cfg.recoveredFile);
fid = fopen(outPath, 'wb');
if fid < 0
    error('reassemble_payload:writeFail', 'Could not write "%s".', outPath);
end
fwrite(fid, recovered, 'uint8');
fclose(fid);

% Byte-exact comparison against the original.
nRec = numel(recovered);
compareLen = min(nRec, nTotal);
exactMatch = (nRec == nTotal) && isequal(recovered, originalPayload);
matchingBytes = sum(recovered(1:compareLen) == originalPayload(1:compareLen));

rec = struct();
rec.recovered      = recovered;
rec.outPath        = outPath;
rec.numTotalBytes  = nTotal;
rec.numRecovered   = nRec;
rec.completeness   = nRec / nTotal;        % fraction of bytes recovered
rec.byteAccuracy   = matchingBytes / max(compareLen, 1);
rec.exactMatch     = exactMatch;

fprintf('Recovered %d/%d bytes (%.1f%%), exact file match: %s.\n', ...
    nRec, nTotal, 100 * rec.completeness, mat2str(exactMatch));
end
