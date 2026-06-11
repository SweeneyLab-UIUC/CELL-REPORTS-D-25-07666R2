source("FiberPhotometryViewerFunctions.R")

ui <- fluidPage(

  headerPanel("Fiber Photometry"),

  tabsetPanel(

    # ── Data Upload ──────────────────────────────────────────────────────────
    tabPanel("Data Upload",
      sidebarLayout(
        sidebarPanel(width = 3,
          fileInput(inputId = "fpFile", "Choose your FPdata file",
                    accept = c(".csv", ".zip", ".txt")),
          hr(),
          checkboxInput(inputId = "uploadManual_DataUpload", label = "Manual upload", value = FALSE),

          conditionalPanel(condition = "input.uploadManual_DataUpload == true",
            fluidRow(
              column(4, selectInput("timestampSelection_DataUpload", "Timestamp:", choices = NULL)),
              column(4, selectInput("signalSelection_DataUpload",    "Signal:",    choices = NULL)),
              column(4, selectInput("controlSelection_DataUpload",   "Control:",   choices = NULL))
            ),
            hr(),
            actionButton("addDataToAnalysis_DataUpload", "Add to Analysis"),
            actionButton("delDataToAnalysis_DataUpload", "Remove from Analysis")
          )
        ),

        mainPanel(width = 9,
          h3("Uploaded Photometry Data"),
          tableOutput("uploadedDataTable_DataUpload"),
          conditionalPanel(condition = "input.uploadManual_DataUpload == true",
            h3("Data to Analyze"),
            tableOutput("manualDataTable_DataUpload")
          )
        )
      )
    ),

    # ── Pre-Analysis Options ─────────────────────────────────────────────────
    tabPanel("Pre-Analysis Options",
      sidebarLayout(
        sidebarPanel(width = 3,
          fluidRow(
            column(4,
              radioButtons("fittingOptions_PreAnalysisOptions", "Fitting Options",
                           choices = list("None" = 0, "Linear Fit" = 1, "Biexponential Fit" = 2),
                           selected = 0)
            )
          ),
          hr(),
          fluidRow(
            column(10,
              checkboxInput("lowPassFiltering_PreAnalysisOptions", "Low Pass Filtering"),
              conditionalPanel(condition = "input.lowPassFiltering_PreAnalysisOptions == true",
                sliderInput("lowPassCutOffFreq_PreAnalysisOptions", "Cut Off Frequency / hz",
                            min = 1, max = 15, value = 5),
                sliderInput("samplingFreq_PreAnalysisOptions", "Sampling Frequency / hz",
                            min = 15, max = 50, value = 30),
                numericInput("butterworthOrder_PreAnalysisOptions", "Filter order",
                             min = 1, max = 15, value = 3, step = 1)
              )
            )
          ),
          hr(),
          fluidRow(
            column(4, actionButton("subsetData_PreAnalysisOptions",       "Subset Data")),
            column(4, actionButton("subsetDataCancel_PreAnalysisOptions",  "Cancel Subset"))
          ),
          hr(),
          fluidRow(
            column(4, numericInput("graphDownsamplingRate_PreAnalysisOptions",
                                   "Figure Downsampling", value = 5, min = 1)),
            column(4, numericInput("dataDownsamplingRate_PreAnalysisOptions",
                                   "Data Downsampling", value = 1, min = 1))
          )
        ),

        mainPanel(width = 9,
          h3("Control & Signal"),
          plotOutput("rawDataPlot",
                     brush = brushOpts(id = "rawDataPlotBrush_PreAnalysisOptions", direction = "x"))
        )
      )
    ),

    # ── Normalization and Z-Scores ───────────────────────────────────────────
    tabPanel("Normalization and Z-Scores",
      sidebarLayout(
        sidebarPanel(width = 3,
          checkboxGroupInput("zeroPreEventSelection", "Zero Pre-event Plots and Data",
                             choices = c("Delta F over F" = "delff", "Z-Score" = "zScore"),
                             inline = TRUE),
          sliderInput("zeroRange", "Pre-event values to zero-out data by:",
                      min = 0, max = 100, value = c(0, 0)),
          hr(),
          radioButtons("zScoreMethod", "Which Z-Score method to apply?:",
                       choices = c("Full range" = "zScore", "Base-line" = "zScoreBaseline")),
          sliderInput("normalizeRange", "Pre-event values to normalize data by:",
                      min = 0, max = 100, value = c(0, 0))
        ),

        mainPanel(
          mainPanel(width = 9,
            h3("Delta F / F Plot"),
            plotOutput("delffDataPlot"),
            h3("Z Score Plot"),
            plotOutput("zScoreDataPlot"),
            downloadButton("dataExport_SingleRunViewer", "Export Formatted Data")
          )
        )
      )
    ),

    # ── Manual Event Exporter ────────────────────────────────────────────────
    tabPanel("Manual Event Exporter",
      sidebarLayout(
        sidebarPanel(width = 3,
          fluidRow(column(10,
            radioButtons("plotType_ManualEventExporter", "Plot type",
                         choices = c("Delta F / F" = "delff", "Z-Score" = "zScore"))
          )),
          fluidRow(column(10,
            textInput("brushName_ManualEventExporter", "", value = "Enter selection name...")
          )),
          fluidRow(column(10,
            colourInput("brushColor_ManualEventExporter", "Selection Color",
                        value = "red", showColour = "background")
          )),
          fluidRow(column(10,
            radioButtons("selectiontype_ManualEventExporter", "Event Selection Type",
                         choices = c("Click and Drag", "Time Range Entry", "By Event File"),
                         inline = TRUE)
          )),

          conditionalPanel(condition = "input.selectiontype_ManualEventExporter == 'Click and Drag'",
            fluidRow(column(8, checkboxInput("rendercursorposition_ManualEventExporter",
                                             "Render Cursor Position?"))),
            fluidRow(
              column(4, actionButton("saveBrush_ManualEventExporter",   "Save Selection")),
              column(4, actionButton("deleteBrush_ManualEventExporter", "Delete selection"))
            )
          ),

          conditionalPanel(condition = "input.selectiontype_ManualEventExporter == 'Time Range Entry'",
            fluidRow(
              column(4, numericInput("startnumericrange_ManualEventExporter", "Start point - Event", value = 0)),
              column(4, numericInput("endnumericrange_ManualEventExporter",   "End point - Event",   value = 0))
            ),
            fluidRow(
              column(4, actionButton("savenumericrange_ManualEventExporter",   "Save Selection")),
              column(4, actionButton("deletenumericrange_ManualEventExporter", "Delete selection"))
            )
          ),

          conditionalPanel(condition = "input.selectiontype_ManualEventExporter == 'By Event File'",
            fluidRow(column(8, fileInput("eventfile_ManualEventExporter", "Upload Event File"))),
            fluidRow(column(8, selectInput("eventname_ManualEventExporter", "Events to add to plot",
                                           choices = NULL, multiple = TRUE))),
            fluidRow(
              column(4, actionButton("saveeventname_ManualEventExporter",   "Save Selection")),
              column(4, actionButton("deleteeventname_ManualEventExporter", "Delete selection"))
            )
          )
        ),

        mainPanel(width = 9,
          plotOutput("eventPlot_ManualEventExporter", width = "90%",
                     brush = brushOpts(id = "eventPlotBrush_ManualEventExporter", direction = "x"),
                     hover = hoverOpts(id = "eventPlotHover_ManualEventExporter",
                                       delay = 50, delayType = "throttle")),
          conditionalPanel(condition = "input.rendercursorposition_ManualEventExporter == true",
                           textOutput("cursorpositiontext_ManualEventExporter")),
          tableOutput("eventTable_ManualEventExporter"),
          downloadButton("eventStatsExport_ManualEventExporter", "Export Event Summary Data")
        )
      )
    ),

    # ── Methods ──────────────────────────────────────────────────────────────
    tabPanel("Methods",
      verticalLayout(
        column(4,  h3("Downsampling")),
        column(4, offset = 0.5,
          p("Downsampling reduces the number of individual data points used in rendering graphs
             and/or in exported data. Downsampling is set as a \"rate\" which will set the number
             of dropped data points", em("i.e."), "a rate of 5 will mean that in every 5 data
             points, only one will be used. Downsampling rates can be chosen for exported data and
             graphs separately, and by default the graph downsampling rate is set at 5 to reduce
             computational burden when graphs are re-rendered repeatedly.")),
        br(), hr(), br(),
        column(4,  h3("Zero Pre-event Plots and Data")),
        column(4, offset = 0.5,
          p("Subtracts the mean of a user-defined pre-event window from the trace, so the
             baseline period centres on zero. This can be applied to the delta F over F and
             Z-score plots independently."),
          br(),
          p("This applies a constant offset to the data. Comparisons of absolute values between
             animals are therefore not valid after zeroing, but percentage or absolute changes
             relative to baseline remain valid.")),
        br(), hr(), br(),
        column(4,  h3("Z-Score Methods")),
        column(4, offset = 0.5,
          p("There are two available Z-Score methods, \"Full Range\" and \"Base-line\". The
             \"Full Range\" method finds the mean and standard deviation of all data points from
             a fiber, whereas \"Base-line\" uses a user-set range of data points to determine
             the mean and standard deviation. Means and standard deviations are determined using R.")),
        br(), hr(), br(),
        column(4,  h3("Data Export")),
        column(4, offset = 0.5,
          p("Data can be downloaded in several pages of this app. In general, the downloaded data
             will match whatever is being displayed on the graph. Therefore, if a \"Zero Pre-Event\"
             or \"Base-line Z-Score\" setting is selected, the .csv created will reflect this."))
      )
    )
  )
)


server <- function(input, output) {

  options(shiny.maxRequestSize = 1000 * 1024^2)

  # ── Core reactive data pipeline ───────────────────────────────────────────
  #
  # fpText  — raw parsed CSV (no subsetting, no processing)
  # fpData  — fpText subsetted to the user's time window
  # fpDF    — fpData with signal processing, normalization, and z-scores applied
  # ggfpDF  — fpDF melted into long form and downsampled for plotting

  fpText <- reactive({
    req(input$fpFile$datapath)
    fp.csv <- text.file.to.csv(input$fpFile$datapath)
    if (is.character(fp.csv)) {
      showModal(modalDialog(title = "Error", HTML(fp.csv), easyClose = TRUE))
      return(NULL)
    }
    fp.csv
  })

  fpData <- reactive({
    req(fpText())
    subsample(fpText(), reactiveHolder$subsetDataRange_PreAnalysisOptions)
  })

  fpDF <- reactive({
    req(fpData())

    input.Error <- case_when(
      !any(colnames(fpData()) == "timestamp") ~ "Can't find a \"timestamp\" column in the signal file!",
      !ncol(fpData()) > 1                     ~ "Can't find sufficient data to proceed - check signal file!",
      TRUE                                    ~ ""
    )
    if (input.Error != "") {
      #showModal(modalDialog(title = "Signal File Error", input.Error, easyClose = TRUE))
      return(NULL)
    }

    inputDF <- csv_dataframe_to_fpDF(
      inputDF        = req(fpData()),
      isMultiFiber   = input$uploadManual_DataUpload,
      columnList     = reactiveHolder$uploadManualColumnList_DataUpload,
      fittingOptions = input$fittingOptions_PreAnalysisOptions,
      filterValues   = reactiveHolder$filterValues
    )
    if (is.character(inputDF)) {
      #showModal(modalDialog(title = "Error", HTML(inputDF), easyClose = TRUE)) # Error messages are annoying.
      return(NULL)
    }

    update_fpDF(
      inputDF            = inputDF,
      zeroPreEvent       = input$zeroPreEventSelection,
      zScoreMethod       = input$zScoreMethod,
      zeroRange          = input$zeroRange,
      normRange          = input$normalizeRange,
      analysisRange      = reactiveHolder$subsetDataRange_PreAnalysisOptions
    )
  })

  ggfpDF <- reactive(fpDF_to_ggplotDF(req(fpDF()), downsamplingRate = input$graphDownsamplingRate_PreAnalysisOptions))

  eventFile <- reactive({
    evF <- read.csv(req(input$eventfile_ManualEventExporter$datapath),
                    header = TRUE, sep = ",", check.names = FALSE)
    inputError <- case_when(
      !(nrow(evF) > 2)                             ~ "Can't find sufficient data to proceed - check signal file!",
      !any(colnames(evF) == "Event")               ~ "Can't find an \"Event\" column in the event file!",
      !any(colnames(evF) == "Start Time (s)")      ~ "Can't find a \"Start Time (s)\" in the event file!",
      !any(colnames(evF) == "End Time (s)")        ~ "Can't find a \"End Time (s)\" in the event file!",
      !(ncol(evF) > 1)                             ~ "Can't find sufficient data to proceed - check signal file!",
      TRUE                                         ~ ""
    )
    if (inputError != "") {
      showModal(modalDialog(title = "Event File Error", inputError, easyClose = TRUE))
      return(NULL)
    }
    evF$"Event" <- append_frequency(evF$"Event")
    return(evF)
  })

  # ── Shared reactive state ─────────────────────────────────────────────────

  reactiveHolder <- reactiveValues()
  reactiveHolder$eventDF_ManualEventExporter    <- eventDF_setup()
  reactiveHolder$filterValues                   <- filterValues_setup()

  # Reset all per-file state whenever a new file is uploaded
  observeEvent(input$fpFile, {
    reactiveHolder$subsetDataRange_PreAnalysisOptions    <- NULL
    reactiveHolder$uploadManualColumnList_DataUpload     <- list()
    reactiveHolder$eventDF_ManualEventExporter           <- eventDF_setup()
    reactiveHolder$brushAnnotationsList_ManualEventExporter <- list()
  })

  # Consolidate four separate filter observeEvents into one reactive block
  observe({
    reactiveHolder$filterValues <- list(
      filter.bool   = input$lowPassFiltering_PreAnalysisOptions,
      cutOff.freq   = input$lowPassCutOffFreq_PreAnalysisOptions,
      sampling.freq = input$samplingFreq_PreAnalysisOptions,
      order         = input$butterworthOrder_PreAnalysisOptions
    )
  })

  # ── Data Upload tab ───────────────────────────────────────────────────────

  observe({
    req(fpData())
    if (!any(colnames(fpData()) == "timestamp") || ncol(fpData()) <= 1) return()
    datacols <- colnames(fpData())
    updateSelectInput(inputId = "timestampSelection_DataUpload", choices = datacols)
    updateSelectInput(inputId = "signalSelection_DataUpload",    choices = datacols)
    updateSelectInput(inputId = "controlSelection_DataUpload",   choices = datacols)
  })

  observeEvent(input$addDataToAnalysis_DataUpload, {
    reactiveHolder$uploadManualColumnList_DataUpload <- append(
      reactiveHolder$uploadManualColumnList_DataUpload,
      c(as.character(input$timestampSelection_DataUpload),
        as.character(input$signalSelection_DataUpload),
        as.character(input$controlSelection_DataUpload))
    )
  })

  observeEvent(input$delDataToAnalysis_DataUpload, {
    lst <- reactiveHolder$uploadManualColumnList_DataUpload
    if (length(lst) >= 3) {
      reactiveHolder$uploadManualColumnList_DataUpload <- lst[seq_len(length(lst) - 3)]
    }
  })

  output$uploadedDataTable_DataUpload <- renderTable({
    req(fpText())
    head(fpText())
  })

  output$manualDataTable_DataUpload <- renderTable({
    req(fpDF())
    head(fpDF())
  })

  # ── Pre-Analysis Options tab ──────────────────────────────────────────────

  output$rawDataPlot <- renderPlot({
    req(ggfpDF())
    req(any(colnames(ggfpDF()) == "variable"))
    tryCatch({
      # Plot only raw signal/control columns (exclude derived columns)
      colPlot  <- grep("timestamp$|delff$|zScore$|zScoreBaseline$",
                       colnames(fpDF()), value = TRUE, invert = TRUE)
      linePlot <- ggplot_object(ggDF = ggfpDF(), y = colPlot)
      linePlot + geom_line() + labs(x = "Time / s", y = "Signal")
    }, error = function(e) plot_error_message(paste("Plot error:", e$message)))
  })

  observeEvent(input$subsetData_PreAnalysisOptions, {
    reactiveHolder$subsetDataRange_PreAnalysisOptions <-
      c(input$rawDataPlotBrush_PreAnalysisOptions$xmin,
        input$rawDataPlotBrush_PreAnalysisOptions$xmax)
  })

  observeEvent(input$subsetDataCancel_PreAnalysisOptions, {
    reactiveHolder$subsetDataRange_PreAnalysisOptions <- NULL
  })

  # ── Normalization and Z-Scores tab ────────────────────────────────────────

  observe({
    updateSliderInput(inputId = "normalizeRange",
                      min = floor(min(fpDF()[["timestamp"]], na.rm = TRUE)),
                      max = floor(max(fpDF()[["timestamp"]], na.rm = TRUE)))
    updateSliderInput(inputId = "zeroRange",
                      min = floor(min(fpDF()[["timestamp"]], na.rm = TRUE)),
                      max = floor(max(fpDF()[["timestamp"]], na.rm = TRUE)))
  })

  output$delffDataPlot <- renderPlot({
    req(ggfpDF())
    req(any(colnames(ggfpDF()) == "variable"))
    tryCatch({
      delffData <- colnames(fpDF())[endsWith(colnames(fpDF()), "delff")]
      linePlot  <- ggplot_object(ggDF = ggfpDF(), y = delffData)
      linePlot + geom_line() + labs(x = "Time / s", y = "Delta F / F")
    }, error = function(e) plot_error_message(paste("Plot error:", e$message)))
  })

  output$zScoreDataPlot <- renderPlot({
    req(ggfpDF())
    req(any(colnames(ggfpDF()) == "variable"))
    tryCatch({
      zScoreData <- colnames(fpDF())[endsWith(colnames(fpDF()), input$zScoreMethod)]
      linePlot   <- ggplot_object(ggDF = ggfpDF(), y = zScoreData)
      linePlot + geom_line() + labs(x = "Time / s", y = "Z-Score")
    }, error = function(e) plot_error_message(paste("Plot error:", e$message)))
  })

  output$dataExport_SingleRunViewer <- downloadHandler(
    filename = function() paste0(file_path_sans_ext(input$fpFile$name), "_formatted.csv"),
    content  = function(file) {
      fileDF <- downsample_for_download(fpDF(), input$dataDownsamplingRate_PreAnalysisOptions)
      fileDF$"Pre-Event-Range/s" <- c(input$normalizeRange[1], input$normalizeRange[2],
                                      rep(NA, nrow(fileDF) - 2))
      if (input$dataDownsamplingRate_PreAnalysisOptions != 1) {
        fileDF$"Downsampling Ratio" <- c(input$dataDownsamplingRate_PreAnalysisOptions,
                                         rep(NA, nrow(fileDF) - 1))
      }
      write.csv(x = fileDF, file, row.names = FALSE, na = "")
    }
  )

  # ── Manual Event Exporter tab ─────────────────────────────────────────────

  output$eventPlot_ManualEventExporter <- renderPlot({
    req(any(colnames(ggfpDF()) == "variable"))
    tryCatch({
      ggDF <- ggfpDF()
      ggDF <- ggDF[!is.na(ggDF$value), ]

      if (input$plotType_ManualEventExporter == "zScore") {
        y     <- colnames(fpDF())[endsWith(colnames(fpDF()), input$zScoreMethod)]
        yaxis <- "Z Score"
      } else {
        y     <- colnames(fpDF())[endsWith(colnames(fpDF()), "delff")]
        yaxis <- "Delta F / F"
      }

      linePlot <- ggplot_object(ggDF = ggDF, y = y)
      linePlot <- linePlot + geom_line() + labs(x = "Time / s", y = yaxis)

      for (ann in reactiveHolder$brushAnnotationsList_ManualEventExporter) {
        linePlot <- linePlot + ann
      }
      linePlot
    }, error = function(e) plot_error_message(paste("Plot error:", e$message)))
  })

  observe({
    updateNumericInput(inputId = "startnumericrange_ManualEventExporter",
                       min   = floor(min(fpDF()[["timestamp"]])),
                       max   = floor(max(fpDF()[["timestamp"]])),
                       value = floor(min(fpDF()[["timestamp"]])))
    updateNumericInput(inputId = "endnumericrange_ManualEventExporter",
                       min   = floor(min(fpDF()[["timestamp"]])),
                       max   = floor(max(fpDF()[["timestamp"]])),
                       value = floor(min(fpDF()[["timestamp"]])))
  })

  observe({
    req(is.data.frame(eventFile()))
    updateSelectInput(inputId = "eventname_ManualEventExporter",
                      choices = append_frequency(eventFile()[["Event"]]))
  })

  # Helper: add a row to the event table and a rect annotation to the plot
  add_event <- function(eventName, startPoint, endPoint) {
    req(fpDF())
    reactiveHolder$eventDF_ManualEventExporter <-
      update_event_table_add(
        inputDF    = reactiveHolder$eventDF_ManualEventExporter,
        dataDF     = fpDF(),
        zScoreType = input$zScoreMethod,
        eventName  = eventName,
        startPoint = startPoint,
        endPoint   = endPoint
      )
    reactiveHolder$brushAnnotationsList_ManualEventExporter <-
      append(reactiveHolder$brushAnnotationsList_ManualEventExporter,
             build_rect_object(fill = input$brushColor_ManualEventExporter,
                               xmin = startPoint, xmax = endPoint))
  }

  # Helper: remove the last event table row and its annotation
  delete_last_event <- function() {
    if (nrow(reactiveHolder$eventDF_ManualEventExporter) > 0) {
      reactiveHolder$eventDF_ManualEventExporter <-
        update_event_table_del(reactiveHolder$eventDF_ManualEventExporter, rowToDel = NULL)
    }
    lst <- reactiveHolder$brushAnnotationsList_ManualEventExporter
    if (length(lst) > 0) {
      reactiveHolder$brushAnnotationsList_ManualEventExporter <- lst[-length(lst)]
    }
  }

  observeEvent(input$saveBrush_ManualEventExporter, {
    add_event(input$brushName_ManualEventExporter,
              input$eventPlotBrush_ManualEventExporter$xmin,
              input$eventPlotBrush_ManualEventExporter$xmax)
  })

  observeEvent(input$savenumericrange_ManualEventExporter, {
    add_event(input$brushName_ManualEventExporter,
              input$startnumericrange_ManualEventExporter,
              input$endnumericrange_ManualEventExporter)
  })

  observeEvent(input$saveeventname_ManualEventExporter, {
    req(fpDF(), eventFile())
    evFile <- eventFile()
    ts_min <- min(fpDF()[["timestamp"]], na.rm = TRUE)
    ts_max <- max(fpDF()[["timestamp"]], na.rm = TRUE)

    for (event in input$eventname_ManualEventExporter) {
      idx       <- which(evFile$"Event" == event)
      startTime <- evFile$"Start Time (s)"[idx]
      endTime   <- evFile$"End Time (s)"[idx]

      if (startTime >= ts_max || endTime <= ts_min) next  # event entirely outside recording

      startTime <- max(startTime, ts_min)
      endTime   <- min(endTime,   ts_max)

      add_event(event, startTime, endTime)
    }
  })

  observeEvent(input$deleteBrush_ManualEventExporter,        delete_last_event())
  observeEvent(input$deletenumericrange_ManualEventExporter,  delete_last_event())
  observeEvent(input$deleteeventname_ManualEventExporter,     delete_last_event())

  output$eventTable_ManualEventExporter <- renderTable({
    df           <- reactiveHolder$eventDF_ManualEventExporter
    colnames(df) <- c("Signal Name", "Event Name", "Start Point", "End Point",
                      "Mean value: delta F/F", "Max value: delta F/F", "Min Value: delta F/F",
                      "Mean value: Z-Score",   "Max value: Z-Score",   "Min value: Z-Score")
    df
  })

  output$cursorpositiontext_ManualEventExporter <- renderText({
    paste("Timestamp at cursor =", input$eventPlotHover_ManualEventExporter$x)
  })

  output$eventStatsExport_ManualEventExporter <- downloadHandler(
    filename = function() paste0(file_path_sans_ext(input$fpFile$name), "_manualevents.csv"),
    content  = function(file) {
      write.csv(x = reactiveHolder$eventDF_ManualEventExporter, file, row.names = FALSE)
    }
  )

}

shinyApp(ui, server)
