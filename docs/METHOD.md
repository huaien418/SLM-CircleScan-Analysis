# Method and data contracts

## Inputs and review

The workflow uses image sequences, matched dark references, camera/scanning parameters, and a dataset manifest. The real detector estimates image activity and repeated timing. It marks low-confidence results for review rather than treating every capture as accepted.

A candidate Global ROI is built from suitable intervals and must be explicitly reviewed before real-image analysis continues. Preserve the actual approval record for that study; the synthetic test's fixed ROI is a software fixture, not a human approval of experimental images.

## Brightness features

Images are read as double precision while retaining their DN scale. The feature extractor subtracts the corresponding mean dark ROI and clips negative corrected values to zero:

```text
corrected_pixel = max(raw_pixel - mean_dark_pixel, 0)
```

For `N` finite corrected ROI pixels sorted from brightest to darkest, `Top1MeanDN` is the mean of exactly `ceil(0.01*N)` pixels. It is not the P99 percentile threshold, nor the mean of all tied pixels at or above P99. P99, ROI mean, Top5/Top10 and other features provide declared comparisons or exploratory summaries.

Exposure/saturation checks use raw, pre-correction DN values. Dark correction does not recover information lost to saturation. The extractor retains its original saturation convention; use the QC report and record actual acquisition conditions.

## Aggregation and experimental units

1. Calculate each frame's feature within the fixed approved ROI.
2. Average frame features within each selected cycle.
3. Average cycle means with equal cycle weight to obtain a capture result.
4. Compare technical captures within a bed/state separately from variation across independently justified experimental units.

`T01`–`T03` names do not create independent powder beds. Likewise, `Rxx` labels alone do not prove independence: describe the actual re-preparation or sequence-restart procedure. A paired 40-then-80 continuous spreading sequence has a different interpretation from independent randomized thickness preparations.

The `plot_stage3_sequence_review_v2` entry point is specifically intended for saved paired 40/80 sequence data, up to five sequences and three captures per state. It reads existing CSVs and writes new figures; it does not recompute the image features.

## Repeatability and screening

The code uses sample SD divided by mean for CV (%), and endpoint separation:

```text
S = abs(mean_low - mean_high) / sqrt(sd_low^2 + sd_high^2)
```

State the units from which those means/SDs are calculated. CV and S thresholds are configurable pilot screening gates, not general significance tests or demonstrated field detection specifications. Nominal platform thickness is not independently measured local thickness truth.

## Motion logs

Map scanner logs to datasets explicitly. Without a supplied mapping, motion checks report missing evidence. Image periodicity is not XY geometry; command geometry is not a proof of physical response accuracy or image/log synchronization. Response evidence is retained separately from command-path checks.
