# Photometry Software:
Software for processing raw photometry signals from individual or multiple mice are available as a self contained package in this github.

Briefly, FiberPhotometryViewer (FPV) and MultiMouseViewer (MMV) are two RShiny applications designed to flexibly inspect raw photometry signals encoded in csv files. They were used to produce photometry signal plots seen in figures 5 and 6, and extended figures 11, 12, and 13.

### FiberPhotometryViewer (FPV):
FPV is designed primarily for inspecting raw and normalized traces of individual 465nm/405nm signals, and computing $\Delta$ f/f or z-scores using global statistics (i.e. $\mu$ and $\sigma$ calculated across the entire range) or using pre-event statistics. FPV has some options for more advanced signal processing using various filters, though these were not used in this publication.

### MultiMouseViewer (MMV):
MMV is designed for averaging several separate photometry traces across animals and trials, and displaying average responses of cohorts to stimuli. Events may be manually specified, or inferred from timestamps from uploaded event files. As these figures are slightly more time intensive to produce, an option is available for saving data to a custom format for viewing later.

### Running these Apps:
```
# FPV and MMV can be ran locally using by calling:
shiny::runGitHub("SweeneyLab-UIUC/CELL-REPORTS-D-25-07666R2", subdir = "photometry/FiberPhotometryViewer")
shiny::runGitHub("SweeneyLab-UIUC/CELL-REPORTS-D-25-07666R2", subdir = "photometry/MultiMouseViewer")

# alternatively, they can be cloned via git and accessed by:
setwd(~clone_location)
shiny::runApp()

# FPV and MMV can also be accessed remotely through Posit Connect Cloud (formally shinyapps.io) at:
<TO DO>
```

## Additional MATLAB Photometry Software:
RampingAnalysis.m and TimePointPuller.m were used to subset photometry signal data in support of extended figures 11 and 13. In brief: 
  - RampingAnalysis.m captures feeding bouts (specified by event timestamps) and extracts the fiber photometry signals twenty seconds prior to feeding. Thus enabling the analysis of pre-eating episode dopaminergic signalling - see extended figure 11c.
  - BetweenBoutAnalysis.m captures periods either between feeding bouts or at the cessation of feeding, which were used to compute the average Z-score in the 30 seconds following the end of the bout. Signal data where feeding bouts occured again before a 30 second period had elapsed were ignored - see extended figures 11 (B, D) and 13 (B, D and F) 
