# Limitations and validation boundaries

- This first public release contains analysis code and synthetic software evidence. Real research images, numerical experiment results, logs and approvals remain outside the repository.
- Synthetic inputs intentionally encode a separable signal. Passing their screening gates is a test of computation and contracts, not a physical finding.
- The smoke test mocks interval detection and supplies fixed cycle windows, synthetic ROI approval and some QC/status tables. It is not an end-to-end test of the real detector or interactive review flow.
- The real activity detector and interactive Global ROI approval have not been runtime-validated by this publication test. Camera timing, scanner hardware, re-powdering variability and physical thickness inference require independent evidence.
- Not every production function is exercised by the demo. Static dependency/code analysis covers the 27 production files; the sequence-review plotting function, for example, was not executed in this synthetic run.
- Minimum MATLAB version and Linux/macOS runtime behavior have not been established. This release was checked on Windows with R2025b.
- Keep acquisition exposure, bit depth, dark frames and ROI definitions comparable within the intended study. Do not reuse historical paths, frame indices or approvals across unrelated experiments.
- A repeatable brightness measurement is not automatically an accurate thickness estimate. Validate unseen beds/runs/dates with independent labels and predeclared evaluation rules before making detection claims.
- Calibration, spatial mapping, SIFT defect recognition and laser power compensation are separate research stages. None is claimed complete by these MATLAB files.
