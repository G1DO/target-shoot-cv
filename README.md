# Shooting Target Score

SCO421 Computer Vision project — automatic scoring of shooting targets from images.
Two parallel implementations:
- Hand-crafted: traditional image processing (Hough circles, morphology, region props).
- Data-driven: YOLOv2 + ResNet-18 fine-tune (transfer learning).
Plus a unified GUI that exposes both approaches.

## Requirements

- MATLAB R2023b or newer (developed against R2026a).
- Image Processing Toolbox.
- Computer Vision Toolbox (for `yolov2ObjectDetector` and `imfindcircles`).
- Deep Learning Toolbox (to load the trained network).
- Image Acquisition Toolbox (optional, for the ACQUIRE Camera button — the GUI has a stub fallback if missing).

## Quick start

1. Clone this repo:
   `git clone https://github.com/G1DO/target-shoot-cv.git`
2. Open MATLAB and `cd` into the cloned folder.
3. Run `addpath(genpath(pwd))` once to put all subfolders on the path.
4. Launch the GUI: type `ShootingTargetGUI_Unified` in the Command Window and press Enter.

(If `ShootingTargetGUI_Unified.m` is not in the repo yet, run the older GUI `TargetScorerGUI` from `team_handcrafted/` for the hand-crafted demo, or `shootingTargetGUI` from `data_driven/phase6/` for the data-driven demo.)

## What the GUI does (4 buttons per the project spec)

1. **BROWSE single image** — pick any image; the GUI runs BOTH hand-crafted and data-driven on it and displays both annotated outputs side by side along with both scores.
2. **BROWSE ALL SEEN — hand-crafted** — iterates through the 17 official test cases under `2 Shooting Target Score/SEEN TESTS/` using the hand-crafted pipeline and shows intermediate segmentation + final scored output per case.
3. **BROWSE ALL SEEN — data-driven** — same loop but using the trained YOLOv2 detector.
4. **ACQUIRE Camera** — captures one frame from the connected webcam (or uses the built-in stub fallback) and runs both approaches on the captured frame.

Every output panel shows the intermediate segmentation result beside the final annotated output, as required by the project spec.

## Demo checklist for the TA

- Open MATLAB, run `ShootingTargetGUI_Unified`.
- Click each of the 4 buttons in order. Buttons 2 and 3 cycle through 17 cases — wait for the loop to finish.
- Open the documentation file `Shooting_Target_Score_Handcrafted_Documentation.docx` to walk through methodology and results.
- The spec is in `2 Shooting Target Score/Shooting Target Score.pdf` if needed for reference.

## Project layout (relevant runtime files only)

- `ShootingTargetGUI_Unified.m` — main GUI (4 required buttons).
- `team_handcrafted/` — hand-crafted MATLAB pipeline (7 .m files).
- `data_driven/phase6/` — data-driven inference wrapper and original GUI.
- `data_driven/phase3/` — score arithmetic and tuned thresholds.
- `data_driven/phase8/` — final detector wrapper (V8final) used by the unified GUI.
- `data_driven/phase2a/` — detector input preprocessing.
- `models/yolov2_pretrained.mat` — trained YOLOv2 + ResNet-18 detector.
- `models/channel_stats.mat` — per-channel mean and standard deviation used at inference time.
- `2 Shooting Target Score/SEEN TESTS/` — 17 official test images.

## Troubleshooting

- **Webcam button errors**: Image Acquisition Toolbox not installed. The GUI falls back to a stub image — this is acceptable per the project spec.
- **`yolov2ObjectDetector not found`**: Computer Vision Toolbox missing.
- **Detector file not loading**: ensure `models/yolov2_pretrained.mat` and `models/channel_stats.mat` are present at the path. If a model file was excluded from git for size reasons, see the model download note below (if applicable).
