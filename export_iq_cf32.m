function meta = export_iq_cf32(iq, cfg, extra)
%EXPORT_IQ_CF32 Write the received I/Q recording and its metadata sidecar.
%   meta = EXPORT_IQ_CF32(iq, cfg, extra) writes iq to received_iq.cf32 as
%   interleaved float32 (I0 Q0 I1 Q1 ...) and a JSON metadata file. The recording
%   is intended for later reuse as a repeatable GNU Radio receiver test input.
%
%   For v1 the recording is the concatenation of the received frame bursts, not
%   a continuous full-pass recording; this is stated explicitly in the metadata.

if ~exist(cfg.outputDir, 'dir'); mkdir(cfg.outputDir); end
iq = iq(:);

% Interleave I and Q as float32.
interleaved = zeros(2 * numel(iq), 1, 'single');
interleaved(1:2:end) = single(real(iq));
interleaved(2:2:end) = single(imag(iq));

iqPath = fullfile(cfg.outputDir, cfg.iqFile);
fid = fopen(iqPath, 'wb');
if fid < 0
    error('export_iq_cf32:writeFail', 'Could not write "%s".', iqPath);
end
fwrite(fid, interleaved, 'float32');
fclose(fid);

meta = struct();
meta.format          = 'complex float32 interleaved (I0 Q0 I1 Q1 ...)';
meta.sample_rate_hz  = cfg.sampleRate;
meta.center_freq_hz  = cfg.carrierFreq;
meta.num_samples     = numel(iq);
meta.duration_s      = numel(iq) / cfg.sampleRate;
meta.modulation      = 'BPSK';
meta.symbol_rate_hz  = cfg.symbolRate;
meta.samples_per_symbol = cfg.sps;
meta.fec             = sprintf('convolutional rate 1/2, K=%d, gen=[%s]', ...
                          cfg.constraintLength, num2str(cfg.codeGenerator));
meta.rrc_beta        = cfg.rrcBeta;
meta.recording_note  = ['v1: concatenation of received frame bursts, NOT a ', ...
                        'continuous full-pass recording. Bursts carry per-frame ', ...
                        'Doppler and Eb/N0 from the pass profile.'];
if nargin >= 3 && ~isempty(extra)
    fn = fieldnames(extra);
    for i = 1:numel(fn)
        meta.(fn{i}) = extra.(fn{i});
    end
end

metaPath = fullfile(cfg.outputDir, cfg.iqMetaFile);
fid = fopen(metaPath, 'w');
if fid < 0
    error('export_iq_cf32:metaFail', 'Could not write "%s".', metaPath);
end
fwrite(fid, jsonencode(meta, 'PrettyPrint', true));
fclose(fid);

fprintf('Wrote I/Q recording: %s (%d samples, %.1f s) + %s.\n', ...
    iqPath, numel(iq), meta.duration_s, cfg.iqMetaFile);
end
