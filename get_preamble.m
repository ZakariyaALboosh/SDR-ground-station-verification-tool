function [bits, symbols] = get_preamble(cfg)
%GET_PREAMBLE Deterministic BPSK preamble shared by transmitter and receiver.
%   [bits, symbols] = GET_PREAMBLE(cfg) returns the known preamble as a bit
%   vector (0/1) and as BPSK symbols (+/-1). It is generated from a fixed seed
%   so both ends agree without transmitting it. The RNG state is saved and
%   restored so this call never perturbs channel-noise generation.

s = rng;                       % save global RNG state
cleanup = onCleanup(@() rng(s));
rng(cfg.preambleSeed, 'twister');

bits = randi([0 1], cfg.preambleLength, 1);
symbols = 1 - 2 * bits;        % 0 -> +1, 1 -> -1 (BPSK)
end
