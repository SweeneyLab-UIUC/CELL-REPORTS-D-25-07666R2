library(dplyr)     # trimws, make.names used here are base R; dplyr needed for pipeline-style callers
library(reshape2)  # melt

# ── Utilities ─────────────────────────────────────────────────────────────────

blank_df_builder <- function(col_ls = NULL) {
  if (is.null(col_ls)) return(data.frame())
  df <- data.frame(matrix(nrow = 0, ncol = length(col_ls)))
  colnames(df) <- col_ls
  df
}

add_row <- function(df, row_data) {
  cn <- colnames(df)
  df <- rbind(df, row_data)
  colnames(df) <- cn
  df
}

del_row <- function(df) df[-nrow(df), ]

# Appends a numeric suffix to repeated strings: c("A","A","B") → c("A","A_2","B")
append_frequency <- function(strings) {
  result <- strings
  for (i in seq_along(strings)) {
    count <- sum(strings[seq_len(i)] == strings[i])
    if (count > 1) result[i] <- paste0(strings[i], "_", count)
  }
  result
}

# Last-observation carried forward: fills consecutive NAs with the nearest prior non-NA value.
# Previous version used dplyr::lag which only fixed isolated (single) NAs.
no_na <- function(vec) {
  for (i in seq_along(vec)) {
    if (is.na(vec[i]) && i > 1L) vec[i] <- vec[i - 1L]
  }
  vec
}

# Returns column indices interleaved as signal/control pairs.
# paired_list(4) → c(1,3,2,4): signal1, control1, signal2, control2.
paired_list <- function(number) {
  if (number %% 2L != 0L)
    stop("Channel list must have an even number of entries (one control channel per signal channel).")
  unlist(lapply(seq_len(number / 2L), function(i) c(i, number / 2L + i)))
}

# ── Table Builders ────────────────────────────────────────────────────────────

inputtable_builder <- function(summaryTable, extractRange, downsampleData) {
  # Reads raw CSV files, aligns each event to a shared relative time axis, and
  # returns a wide table: timestamp | (id-event-channel)* for every signal/control pair.
  #
  # extractRange: c(secondsBefore, secondsAfter) — must be as wide as the largest
  #   downstream window (zeroing or baseline range may exceed the final plot window).

  inputtable <- data.frame()

  for (i in seq_len(nrow(summaryTable))) {
    if (is.na(summaryTable$EventFile[i])) next

    channelsIncluded <- strsplit(as.character(summaryTable$ChannelsIncluded[i]), ",")[[1]]
    eventsIncluded   <- strsplit(as.character(summaryTable$EventsIncluded[i]),   ",")[[1]]
    id               <- summaryTable$Identifier[i]

    signal_df <- read.csv(summaryTable$DataPath[i], header = TRUE, sep = ",",
                          fill = TRUE, colClasses = "numeric")
    # Keep row 1; then subsample from row 10 onward to skip sensor initialisation artefacts.
    signal_df <- signal_df[c(1L, seq(10L, nrow(signal_df), by = downsampleData)), ]

    events_df       <- read.csv(summaryTable$EventPath[i], header = TRUE, sep = ",", check.names = FALSE)
    events_df$Event <- append_frequency(events_df$Event)

    channelPattern <- channelsIncluded[paired_list(length(channelsIncluded))]
    fullframe      <- signal_df[c("timestamp", channelPattern)]

    # Relative time axis: 0 = event onset, negative = pre-event
    inWindow <- fullframe$timestamp >= 0 & fullframe$timestamp <= sum(extractRange)
    adj_ts   <- round(fullframe$timestamp[inWindow] - extractRange[1], digits = 5)
    addframe <- data.frame(timestamp = adj_ts)

    for (j in seq_along(eventsIncluded)) {
      event  <- eventsIncluded[j]
      tag    <- paste(id, event, sep = "-")
      tStart <- events_df$`Start Time (s)`[events_df$Event == event]
      tEnd   <- round(tStart + extractRange[2], 0)
      tStart <- round(tStart - extractRange[1], 0)

      idx      <- which(fullframe$timestamp >= tStart & fullframe$timestamp <= tEnd)
      res      <- fullframe[idx, c("timestamp", channelPattern), drop = FALSE]
      res      <- res[seq_len(nrow(addframe)), ]
      dataCols <- paste(tag, channelPattern, sep = "-")
      colnames(res)[2:ncol(res)] <- dataCols

      addframe <- cbind(addframe, res[, -1L, drop = FALSE])
      # Forward-fill NAs introduced when the recording doesn't fully cover the extract window.
      addframe[dataCols] <- lapply(addframe[dataCols], no_na)
    }

    if (nrow(inputtable) > 0L) {
      inputtable <- cbind(inputtable, addframe[seq_len(nrow(inputtable)), -1L, drop = FALSE])
    } else {
      inputtable <- addframe
    }
  }

  inputtable
}

datatable_builder <- function(inputTable, summaryTable, zeroRange, baselineRange, outputRange,
                              linearFit = FALSE) {
  # Computes dF/F and Z-score for each signal/control pair in inputTable.
  # Returns: timestamp | id-event-channel-delff | id-event-channel-zScore | ...
  # linearFit: if TRUE, the control channel is first fitted to the signal via OLS before dF/F,
  #            correcting for gain differences between channels.

  numDataCols <- ncol(inputTable) - 1L
  dataTable   <- data.frame(timestamp = inputTable$timestamp)

  for (i in seq(2L, numDataCols, by = 2L)) {
    colId   <- colnames(inputTable)[i]
    signal  <- inputTable[[i]]
    control <- if (linearFit) linear_fit_control(signal, inputTable[[i + 1L]]) else inputTable[[i + 1L]]

    delff <- zero_by_range(
      data      = delff_calc(signal, control),
      timeRange = dataTable$timestamp,
      zeroRange = zeroRange
    )
    dataTable[[paste0(colId, "-delff")]]  <- delff
    dataTable[[paste0(colId, "-zScore")]] <- zscore_calc(delff, dataTable$timestamp, baselineRange)
  }

  dataTable[dataTable$timestamp >= -outputRange[1] & dataTable$timestamp <= outputRange[2], ]
}

outputtable_builder <- function(summaryTable, dataTable, plotGroupTable) {
  # Builds group-level mean ± SEM columns for each group in plotGroupTable.
  # plotGroupTable: GroupID | Type | IncludedChannels
  #   "eventname" — IncludedChannels = comma-sep event names
  #   "inputfile" — IncludedChannels = comma-sep Identifier values
  #   "manual"    — IncludedChannels = comma-sep id-event-channel strings

  outputTable <- data.frame(timestamp = dataTable$timestamp)

  # Sanitize column names for safe regex matching; restored after the loop.
  nameStore          <- colnames(dataTable)
  colnames(dataTable) <- make.names(colnames(dataTable))

  for (i in seq_len(nrow(plotGroupTable))) {
    type     <- plotGroupTable$Type[i]
    included <- make.names(trimws(strsplit(plotGroupTable$IncludedChannels[i], ",")[[1]]))
    gid      <- plotGroupTable$GroupID[i]

    matchPattern <- if (type == "eventname") {
      # Matches event name anywhere in the column string, with optional trailing counter suffix.
      paste0("(", paste0(included, "(.|_|$)", collapse = "|"), ")")
    } else {
      # "inputfile" and "manual" both anchor to the start of the column name.
      paste0("^(", paste(included, collapse = "|"), ")")
    }

    hits       <- grep(matchPattern, colnames(dataTable), value = TRUE)
    delffHits  <- hits[endsWith(hits, "delff")]
    zScoreHits <- hits[endsWith(hits, "zScore")]

    for (metric in list(list(delffHits, "delff"), list(zScoreHits, "zScore"))) {
      cols   <- metric[[1]]
      suffix <- metric[[2]]
      mn     <- mean_calc(dataTable[cols])
      sem    <- mean_SEM_calc(dataTable[cols])
      outputTable[[paste0(gid, "-mean-",    suffix)]] <- mn
      outputTable[[paste0(gid, "-SEMPLUS-", suffix)]] <- mn + sem
      outputTable[[paste0(gid, "-SEMNEG-",  suffix)]] <- mn - sem
    }
  }

  # Restore original names. Previously this was inside the loop, which caused grep
  # to fail against unsanitized names on all iterations after the first.
  colnames(dataTable) <- nameStore

  outputTable
}

# ── Signal Math ───────────────────────────────────────────────────────────────

delff_calc <- function(signal, control) (signal - control) / control

zscore_calc <- function(delff, timeRange, zScoreRange) {
  ind <- if (is.null(zScoreRange)) {
    seq_along(delff)
  } else {
    which(timeRange >= zScoreRange[1] & timeRange <= zScoreRange[2])
  }
  mu  <- mean(delff[ind], na.rm = TRUE)
  sig <- sd(delff[ind],   na.rm = TRUE)
  (delff - mu) / sig
}

mean_calc     <- function(data_cols) rowMeans(data_cols, na.rm = TRUE)

mean_SEM_calc <- function(data_cols) apply(data_cols, 1L, sd, na.rm = TRUE) / sqrt(ncol(data_cols))

zero_by_range <- function(data, timeRange, zeroRange) {
  if (is.null(zeroRange)) return(data)
  ind <- timeRange >= zeroRange[1] & timeRange <= zeroRange[2]
  data - mean(data[ind], na.rm = TRUE)
}

# Fits control to signal via OLS (signal ≈ a·control + b) and returns the fitted values.
# Using the fitted control in dF/F corrects for gain differences between channels and
# removes bleaching trends that are shared between signal and control.
linear_fit_control <- function(signal, control) {
  valid <- !is.na(signal) & !is.na(control)
  if (sum(valid) < 2L) return(control)  # not enough points to fit; fall back to raw control
  cf <- lm(signal[valid] ~ control[valid])$coefficients
  cf[[1]] + cf[[2]] * control  # apply coefficients to all indices, including NAs
}

# ── Plot Data Preparation ─────────────────────────────────────────────────────

ggtable_builder <- function(outputTable, id = "timestamp", downsampleRate, measures, factors = NULL) {
  # Melts outputTable into long format for ggplot.
  # `measures` is a list of character vectors; each becomes a value column.
  # Measures after the first are cbind'd (used to carry SEM band columns alongside the mean).

  downsampleRate <- max(1L, as.integer(downsampleRate))
  outputTable    <- outputTable[seq(1L, nrow(outputTable), by = downsampleRate), ]  # was computed but never applied

  melttable <- melt(outputTable, id.vars = id, measure.vars = measures[[1]], variable.name = "Group")
  for (measure in measures[-1]) {
    extra     <- melt(outputTable, id.vars = id, measure.vars = measure, variable.name = "Group")
    melttable <- cbind(melttable, extra["value"])
  }

  if (!is.null(factors)) {
    levels(melttable$Group) <- unlist(
      lapply(factors, function(x) c(paste0(x, "-delff"), paste0(x, "-zScore")))
    )
  }

  melttable
}
