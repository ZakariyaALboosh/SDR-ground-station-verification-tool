# SDR Ground Station Verification Tool

A pre-deployment verification tool for a proposed physical SDR-based LEO ground
station (BSc project). It simulates a full downlink over a real TLE-derived
satellite pass and reports whether the proposed receiver configuration can
recover a data file reliably — **before** any hardware is built.

The tool deliberately reuses simple, proven MATLAB / Communications Toolbox
building blocks. It is not an RF circuit simulator, not a full CCSDS stack, and
not an AI recommendation engine.

## Target environment

- MATLAB **R2022b**
- Satellite Communications Toolbox 1.3
- Communications Toolbox 7.8

## Run it

From this folder in MATLAB:

```matlab
results = run_tool;
```

Outputs are written to `output/`:

| File | Description |
|------|-------------|
| `recovered.txt`      | Payload rebuilt from CRC-valid frames |
| `received_iq.cf32`   | Interleaved float32 I/Q recording (`I0 Q0 I1 Q1 …`) |
| `iq_metadata.json`   | Recording metadata (sample rate, modulation, notes) |
| `results.txt`        | Human-readable checks + verdict |
| `results.json`       | Machine-readable metrics + verdict |

The `received_iq.cf32` recording is intended for later reuse as a repeatable
GNU Radio receiver test input. For v1 it is the **concatenation of the received
frame bursts**, not a continuous full-pass recording — this is stated in the
metadata.

## Pipeline

```
load_config      -> all tunable parameters (single point of control)
load_payload     -> read the file to transmit (bytes)
build_pass_profile   -> TLE + satelliteScenario + aer -> az/el/range + Doppler
calculate_link_profile -> FSPL, Friis noise figure, SNR, Eb/N0 per pass point
build_frames     -> sync | seq(16) | len(16) | payload | CRC-16
                    (frames mapped onto the pass; Tx stops at LOS)
generate_waveform-> BPSK + rate-1/2 K=7 convolutional code + RRC shaping
apply_channel    -> constant per-frame Doppler + Eb/N0-scaled AWGN
run_receiver     -> coarse Doppler correction -> matched filter -> preamble
                    sync -> residual CFO search -> Viterbi decode -> CRC check
reassemble_payload   -> rebuild file from valid frames, byte-exact compare
export_iq_cf32   -> write I/Q recording + metadata
write_results    -> evaluate checks, print PASS/REVISE verdict
```

## Doppler method (R2022b compatible)

`dopplershift` is **not** used. Doppler is derived from range rate:

```matlab
[az, el, range, time] = aer(gs, sat);
rangeRate = gradient(range, sampleTime);
dopplerHz = -(rangeRate / c) * carrierFrequency;
```

## Frame format

A simple project-defined frame (not full CCSDS):

```
[ known preamble ][ 16-bit sync marker ][ 16-bit seq ][ 16-bit length ][ payload ][ CRC-16 ]
```

The information field (sync + seq + length + payload + CRC) is convolutionally
encoded; the preamble is sent uncoded for timing acquisition and residual CFO
estimation.

## Design verdict

The tool prints **PASS** or **REVISE** based on six checks:

1. Coarse Doppler correction covers the nominal Doppler
2. Residual CFO search range is sufficient
3. Sample rate is valid
4. Receiver synchronization success ≥ 90%
5. CRC-valid frame recovery ≥ 90%
6. Payload completeness ≥ 90%

## Configuration

Everything is tuned in `load_config.m`: carrier frequency, symbol rate, samples
per symbol, FEC, framing, ground station location, TLE, scenario window, and the
link-budget parameters (satellite EIRP, antenna gain, and the
Filter → LNA → Cable → SDR RF chain).
