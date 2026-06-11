# CELL-REPORTS-D-25-07666R2
Companion resource for CELL-REPORTS-D-25-07666R2: Lactation increases food seeking and palatable feeding through mesolimbic dopamine signaling in mice &lt;/LINK TO PAPER/>

```
CELL-REPORTS-D-25-07666R2/
├── photometry/
│    ├── README.md
│    ├── FiberPhotometryViewer/
│    │    ├── app.R
│    │    ├── FiberPhotometryViewerFunctions.R
│    │    └── manifest.json
│    ├── MultiMouseViewer/
│    │     ├── app.R
│    │     ├── MultiMouseFunctions.R
│    │     └── mainfest.json
│    └── MATLAB Scripts/
│          ├── RampingAnalysis.m
│          └── BetweenBoutAnalysis.m
└── locomotion/
     ├── README.md
     ├── SLEAP model/
     │    ├── 640x480_gray.ckpt
     │    └── initial_config.yaml
     └── Keypoints.py
```

## Locomotion Analysis Methods & Example Videos:
Comparisons of gross locomotor behavior were performed with SLEAP (https://github.com/talmolab/sleap) using a 5 part single animal model on a U-NET backend. The model was trained on grayscale videos of homecage locomotion, at approximately 640x480 pixel resolution. The pretrained model is available as a .ckpt file, and a training config.yaml is available with user directories left blank.

Tracked points were analyzed using custom python module - Keypoints.py. The centroid of the mouse's head was calculated using the arithmetic mean of the polygon drawn between nose-tip and ears, and total distance travelled and instananeous speed are determined from this reference point. As recordings vary in duration, all totals and averages are reported from the first 12 minutes of motion. Distances measured in pixels were converted to inches using known reference objects in the image frame.
