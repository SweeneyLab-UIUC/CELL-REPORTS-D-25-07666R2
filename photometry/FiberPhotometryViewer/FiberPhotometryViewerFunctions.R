library(reshape2)   # melt(); superseded by tidyr::pivot_longer but kept for compatibility
library(ggplot2)
library(shiny)
library(colourpicker)
library(dplyr)
library(tools)
library(signal)
library(minpack.lm)


# ─────────────────────────────────────────────────────────────────────────────
# Data Formatting / Uploading / Rearranging Functions
# ─────────────────────────────────────────────────────────────────────────────

subsample <- function(inputDF, analysisRange) {
  if (!is.null(analysisRange) && "timestamp" %in% colnames(inputDF)) {
    idx <- inputDF$timestamp >= min(analysisRange) & inputDF$timestamp <= max(analysisRange)
    inputDF <- inputDF[idx, ]
  }
  return(inputDF)
}

is.csv.like <- function(input_string) {
  length(strsplit(input_string, ",")[[1]]) > 1
}

drop.empty.columns <- function(df) {
  df[, !apply(df, 2, function(col) all(is.na(col) | col == "")), drop = FALSE]
}

monotonicity <- function(series, strict = TRUE, trivial = FALSE) {
  if (length(series) <= 1) return(trivial)
  if (strict) all(diff(series) > 0) else all(diff(series) >= 0)
}

find.time.column <- function(df) {
  normalized <- gsub("\\s+", "", tolower(colnames(df)))
  colnames(df)[normalized %in% c("timestamp", "time", "times", "timestamps")]
}

text.file.to.csv <- function(txt_file) {
  filt.txt <- readLines(txt_file)

  if (length(filt.txt) == 0) {
    return("UNREADABLE INPUT FILE:<br>File not interpretable as a .csv")
  }

  filt.txt <- paste(filt.txt, collapse = "\n")

  csv <- suppressWarnings(tryCatch(
    read.csv(text = filt.txt),
    error = function(e) paste0("UNREADABLE INPUT FILE:<br>", e$message)
  ))

  if (is.character(csv)) return(csv)

  csv <- drop.empty.columns(csv)

  time.col <- find.time.column(csv)
  if (length(time.col) == 1) {
    colnames(csv)[colnames(csv) == time.col] <- "timestamp"
  }

  return(csv)
}

find.465 <- function(datacols) {
  grep(".*465nm_F.*|RawF_465_F|CH1.470", datacols, value = TRUE)
}

find.410 <- function(datacols) {
  grep(".*410nm_F.*|RawF_410_F|CH1.410", datacols, value = TRUE)
}

csv_dataframe_to_fpDF <- function(inputDF, isMultiFiber = FALSE, columnList,
                                   fittingOptions, filterValues) {
  if (is.null(fittingOptions)) fittingOptions <- 0

  if (!isMultiFiber) {
    ind      <- which(colnames(inputDF) == "timestamp")
    datacols <- colnames(inputDF)[(ind + 1):ncol(inputDF)]

    col_465 <- find.465(datacols)
    col_410 <- find.410(datacols)

    if (any(length(col_465) == 0, length(col_410) == 0,
            length(col_410) > 1, length(col_465) > 1)) {
      return("Data Error:<br>Unable to populate columns automatically - try manual input.")
    }

    full_rows  <- complete.cases(inputDF[, c(col_465, col_410)])
    signal     <- inputDF[full_rows, col_465]
    control    <- inputDF[full_rows, col_410]
    timestamps <- inputDF[full_rows, "timestamp"]

    if (filterValues$filter.bool) {
      signal  <- apply.zero_phase_low_pass(signal,  filterValues$cutOff.freq,
                                           filterValues$sampling.freq, filterValues$order)
      control <- apply.zero_phase_low_pass(control, filterValues$cutOff.freq,
                                           filterValues$sampling.freq, filterValues$order)
    }
    if (is.character(signal))  return(signal)
    if (is.character(control)) return(control)

    if (fittingOptions == 1) {
      control <- apply.linear_fit(signal, control)
    } else if (fittingOptions == 2) {
      control <- control - apply.biexponential_fit(control, timestamps)
      signal  <- signal  - apply.biexponential_fit(signal,  timestamps)
    }
    if (is.character(signal))  return(signal)
    if (is.character(control)) return(control)

    df         <- data.frame(timestamp = timestamps, signal = signal, control = control)
    df$delff   <- 100 * (df$signal - df$control) / df$control
    df$zScore  <- (df$delff - mean(df$delff, na.rm = TRUE)) / sd(df$delff, na.rm = TRUE)
    return(df)
  }

  # Multi-fiber path — columnList is a flat list of triplets: [ts, signal, control, ts, signal, control, ...]
  # BUG FIX: was checking > 1 (catches partial triplets); minimum valid columnList is length 3
  if (length(columnList) < 3) return(data.frame())

  df         <- data.frame(timestamp = no_na(inputDF[, columnList[[1]]]))
  max_length <- nrow(df)

  for (i in seq(1, length(columnList), by = 3)) {
    signalName  <- as.character(columnList[[i + 1]])
    controlName <- as.character(columnList[[i + 2]])
    delffName   <- paste0(signalName, "_delff")
    zScoreName  <- paste0(signalName, "_zScore")

    full_rows <- complete.cases(inputDF[, c(signalName, controlName)])
    signal    <- inputDF[full_rows, signalName]
    control   <- inputDF[full_rows, controlName]

    if (filterValues$filter.bool) {
      signal  <- apply.zero_phase_low_pass(signal,  filterValues$cutOff.freq,
                                           filterValues$sampling.freq, filterValues$order)
      control <- apply.zero_phase_low_pass(control, filterValues$cutOff.freq,
                                           filterValues$sampling.freq, filterValues$order)
    }
    if (is.character(signal))  return(signal)
    if (is.character(control)) return(control)

    if (fittingOptions == 1) {
      control <- apply.linear_fit(signal, control)
    } else if (fittingOptions == 2) {
      ts      <- inputDF[full_rows, "timestamp"]
      control <- control - apply.biexponential_fit(control, ts)
      signal  <- signal  - apply.biexponential_fit(signal,  ts)
    }
    if (is.character(signal))  return(signal)
    if (is.character(control)) return(control)

    # Pad shorter vectors to the master timestamp length
    signal  <- c(signal,  rep(NA, max_length - length(signal)))
    control <- c(control, rep(NA, max_length - length(control)))

    df <- cbind(df, signal, control)
    df[[delffName]]  <- 100 * (signal - control) / control
    df[[zScoreName]] <- (df[[delffName]] - mean(df[[delffName]], na.rm = TRUE)) /
                         sd(df[[delffName]], na.rm = TRUE)
  }

  return(df)
}

update_fpDF <- function(inputDF, zeroPreEventSelection, zScoreMethod,
                        zeroRange, normRange, analysisRange) {
  if (!is.null(zeroPreEventSelection)) {
    inputDF <- zero_pre_event(inputDF, zeroPreEventSelection, zeroRange, analysisRange)
  }
  if (zScoreMethod == "zScoreBaseline") {
    inputDF <- zScore_pre_event_baseline(inputDF, normRange)
  }
  return(inputDF)
}

zero_pre_event <- function(inputDF, zeroPreEventSelection, preEventRange, analysisRange) {
  colNames   <- colnames(inputDF)
  delffCols  <- colNames[endsWith(colNames, "delff")]
  zScoreCols <- colNames[endsWith(colNames, "zScore")]

  if (length(delffCols) == 0 && length(zScoreCols) == 0) return(inputDF)

  idx <- inputDF$timestamp >= min(preEventRange) & inputDF$timestamp <= max(preEventRange)

  # Force baseline window to center on zero.
  zero_col <- function(df, col) {
    df[[col]] <- df[[col]] - mean(df[[col]][idx], na.rm = TRUE)
    df
  }

  if ("delff"   %in% zeroPreEventSelection) for (col in delffCols)  inputDF <- zero_col(inputDF, col)
  if ("zScore"  %in% zeroPreEventSelection) for (col in zScoreCols) inputDF <- zero_col(inputDF, col)

  return(inputDF)
}

fpDF_to_ggplotDF <- function(inputDF, id = "timestamp", downsamplingRate) {
  idx <- seq(1, nrow(inputDF), by = downsamplingRate)
  # BUG FIX: id.vars was passed positionally; melt's second positional arg is measure.vars
  melt(inputDF[idx, ], id.vars = id)
}

downsample_for_download <- function(inputDF, downsamplingRate) {
  inputDF[seq(1, nrow(inputDF), by = downsamplingRate), ]
}

no_na <- function(vec) {
  for (i in seq_along(vec)) {
    if (is.na(vec[i]) && i > 1) vec[i] <- vec[i - 1]
  }
  vec
}

# Appends a frequency suffix (_2, _3, ...) to deduplicate repeated event names
append_frequency <- function(strings) {
  out <- strings
  for (i in seq_along(strings)) {
    count <- sum(strings[seq_len(i)] == strings[i])
    if (count > 1) out[i] <- paste(strings[i], count, sep = "_")
  }
  out
}


# ─────────────────────────────────────────────────────────────────────────────
# Signal Processing Functions
# ─────────────────────────────────────────────────────────────────────────────

# Linear regression of control onto signal; returns fitted control values
apply.linear_fit <- function(signalData, controlData) {
  model       <- lm(signalData ~ controlData)
  control_fit <- model$fitted.values

  if (length(control_fit) != length(controlData)) {
    pad         <- length(controlData) - length(control_fit)
    control_fit <- c(rep(NA, floor(pad / 2)), control_fit, rep(NA, ceiling(pad / 2)))
  }

  return(control_fit)
}

apply.biexponential_fit <- function(data, timestamps) {
  if (is.null(data)) return("Invalid data")

  if (any(data <= 0)) {
    return("Biexponential Model failure:<br>Non-positive data passed to biexponential fit")
  }

  # Piecewise log-linear regression provides stable initial estimates for A and k
  log_data <- log(data)
  t        <- as.numeric(timestamps)
  half     <- floor(length(log_data) / 2)

  lm1 <- lm(log_data[seq_len(half)]           ~ t[seq_len(half)])
  lm2 <- lm(log_data[(half + 1):length(log_data)] ~ t[(half + 1):length(t)])

  k1 <- unname(coef(lm1)[2])
  k2 <- unname(coef(lm2)[2])

  # Prevent degenerate starting point where both exponential components are identical
  if (abs(k1 - k2) < .Machine$double.eps * 100) k2 <- k1 * 0.5

  A1 <- data[1] / 2
  A2 <- A1

  fit <- suppressWarnings(tryCatch(
    nlsLM(y ~ A1 * exp(k1 * t) + A2 * exp(k2 * t),
          start   = list(A1 = A1, A2 = A2, k1 = k1, k2 = k2),
          data    = data.frame(t = t, y = data),
          control = nls.lm.control(maxiter = 200)),
    error = function(e) e$message
  ))

  if (is.character(fit)) return(paste0("Biexponential Model failure:<br>", fit))

  fitted <- predict(fit)

  if (length(fitted) != length(data)) {
    pad    <- length(data) - length(fitted)
    fitted <- c(rep(NA, floor(pad / 2)), fitted, rep(NA, ceiling(pad / 2)))
  }

  return(fitted)
}

apply.zero_phase_low_pass <- function(noisy.data, cutoff.freq = 5, sampling.freq = 30, order = 3) {
  w.freq <- cutoff.freq / (sampling.freq / 2)  # normalise to Nyquist

  if (w.freq >= 1 || w.freq <= 0) {
    return("Filtering failure:<br>Cut-off frequency must be between 0 and the Nyquist frequency")
  }

  # filtfilt requires at least 3x the filter order in samples
  min_len <- 3 * order
  if (length(noisy.data) < min_len) {
    return(paste0("Filtering failure:<br>Signal too short for filter order ", order,
                  " (minimum ", min_len, " samples required)"))
  }

  butter_filt <- signal::butter(order, W = w.freq, type = "low")
  signal::filtfilt(butter_filt, noisy.data)
}

derive.signal_to_noise <- function(signal.465, noise.410) {
  noise.power  <- sum(noise.410^2,  na.rm = TRUE) / sum(!is.na(noise.410))
  signal.power <- sum(signal.465^2, na.rm = TRUE) / sum(!is.na(signal.465))
  return(list(
    "Noise Power"    = noise.power,
    "Combined Power" = signal.power,
    "Signal Power"   = signal.power - noise.power
  ))
}

zScore_pre_event_baseline <- function(inputDF, preEventRange) {
  colNames  <- colnames(inputDF)
  delffCols <- colNames[endsWith(colNames, "delff")]

  if (length(delffCols) == 0) return(inputDF)

  # If the range is degenerate (both endpoints equal, e.g. at init), use the full series
  idx <- if (preEventRange[1] == preEventRange[2]) {
    seq_len(nrow(inputDF))  # seq_len avoids 1:0 when nrow is 0
  } else {
    inputDF$timestamp >= min(preEventRange) & inputDF$timestamp <= max(preEventRange)
  }

  for (delffName in delffCols) {
    mu    <- mean(inputDF[[delffName]][idx], na.rm = TRUE)
    sigma <- sd(inputDF[[delffName]][idx],   na.rm = TRUE)
    # Replace "delff" suffix with "zScoreBaseline", preserving any channel prefix
    baselineName <- sub("delff$", "zScoreBaseline", delffName)
    inputDF[[baselineName]] <- (inputDF[[delffName]] - mu) / sigma
  }

  return(inputDF)
}


# ─────────────────────────────────────────────────────────────────────────────
# Event Table Functions
# ─────────────────────────────────────────────────────────────────────────────

EVENT_TABLE_COLS <- c(
  "Signal Name", "Event Name", "Start Point / s", "End Point / s",
  "Mean value: delta F/F", "Max value: delta F/F", "Min Value: delta F/F",
  "Mean value: Z-Score",   "Max value: Z-Score",   "Min value: Z-Score"
)

eventDF_setup <- function() {
  df           <- data.frame(matrix(nrow = 0, ncol = length(EVENT_TABLE_COLS)))
  colnames(df) <- EVENT_TABLE_COLS
  df
}

update_event_table_add <- function(inputDF, dataDF, zScoreType, eventName, startPoint, endPoint) {
  idx        <- dataDF$timestamp >= startPoint & dataDF$timestamp <= endPoint
  colNames   <- colnames(dataDF)
  delffCols  <- colNames[endsWith(colNames, "delff")]
  zScoreCols <- colNames[endsWith(colNames, zScoreType)]

  for (i in seq_along(zScoreCols)) {
    delffName  <- delffCols[i]
    zScoreName <- zScoreCols[i]

    meanVal_delff  <- mean(dataDF[[delffName]][idx],  na.rm = TRUE)
    maxVal_delff   <- max( dataDF[[delffName]][idx],  na.rm = TRUE)
    minVal_delff   <- min( dataDF[[delffName]][idx],  na.rm = TRUE)
    meanVal_zScore <- mean(dataDF[[zScoreName]][idx], na.rm = TRUE)
    maxVal_zScore  <- max( dataDF[[zScoreName]][idx], na.rm = TRUE)
    minVal_zScore  <- min( dataDF[[zScoreName]][idx], na.rm = TRUE)

    # Strip _delff / delff suffix to recover a human-readable signal name
    signalName <- sub("_?delff$", "", delffName)
    if (nchar(signalName) == 0) signalName <- "Signal"
    if (zScoreType == "zScoreBaseline") signalName <- paste(signalName, "Baseline")

    inputDF <- rbind(inputDF, c(signalName, eventName, startPoint, endPoint,
                                meanVal_delff, maxVal_delff, minVal_delff,
                                meanVal_zScore, maxVal_zScore, minVal_zScore))
  }

  return(inputDF)
}

update_event_table_del <- function(inputDF, rowToDel = NULL) {
  idx <- if (is.null(rowToDel)) nrow(inputDF) else which(inputDF$"Event Name" == rowToDel)
  inputDF[-idx, ]
}

filterValues_setup <- function() {
  list(filter.bool = FALSE, cutOff.freq = 5, sampling.freq = 30, order = 3)
}


# ─────────────────────────────────────────────────────────────────────────────
# Plot Helpers
# ─────────────────────────────────────────────────────────────────────────────

ggplot_object <- function(ggDF, y, x = "timestamp") {
  ggplot(subset(ggDF, variable %in% y), aes(x = !!sym(x), y = value, color = variable))
}

build_rect_object <- function(fill, xmin, xmax) {
  # Enforce a minimum visible width of 1 s
  if ((xmax - xmin) < 1) {
    mid  <- (xmin + xmax) / 2
    xmin <- mid - 0.5
    xmax <- mid + 0.5
  }
  annotate("rect", fill = fill, alpha = 0.3, xmin = xmin, xmax = xmax, ymin = -Inf, ymax = Inf)
}

# Fallback for renderPlot tryCatch blocks — shows the error instead of crashing the app
plot_error_message <- function(msg) {
  ggplot() +
    annotate("text", x = 0.5, y = 0.5, label = msg, size = 4.5, color = "firebrick") +
    theme_void() +
    xlim(0, 1) + ylim(0, 1)
}
