library(shiny)
library(shinyjs)
library(ggplot2)
library(plotly)
library(dplyr)   # case_when; was implicit via sourced file in v1
source("MultiMouseFunctions.R")

options(shiny.maxRequestSize = 1000 * 1024^2)  # moved outside server(); applies once at startup

ui <- fluidPage(

  useShinyjs(),
  tags$head(tags$style(
    '
    .grey-out {
        background-color: #eee;
        opacity: 0.2;
    }
    '
  )),

  headerPanel("Multi-Mouse / Multi-Event Viewer"),

  tabsetPanel(
    tabPanel("Data Upload",
      ##################################################################################################
      sidebarLayout(
          sidebarPanel(width = 3,
              tabsetPanel(

                tabPanel("New Analysis",
                       div(id = "newAnalysis",
                       br(),
                       fluidRow(
                         column(width = 6, fileInput(inputId = "fpdata_dataupload", label = "Photometry Data", accept = ".csv")),
                         column(width = 6, fileInput(inputId = "eventdata_dataupload", label = "Event Data", accept = ".csv")),
                       ),

                       textInput(inputId = "dataidentifier_dataupload", label = "(Optional) Experimental/Mouse Identifier"),

                       fluidRow(
                         column(width = 6, selectInput(inputId = "signallist_dataupload",
                                                       label = "Signal Channel Name", choices = NULL, multiple = TRUE)),
                         column(width = 6, selectInput(inputId = "controllist_dataupload",
                                                       label = "Control Channel Name", choices = NULL, multiple = TRUE)),
                       ),
                       textInput(inputId = "channellist_dataupload", label = "", value = ""),

                       selectInput(inputId = "eventlist_dataupload", label = "Included Events", choices = NULL, multiple = TRUE),

                       hr(),

                       fluidRow(
                         column(width = 6, actionButton(inputId = "file_addtoanalysis_dataupload", label = "Add File to Analysis")),
                         column(width = 6, actionButton(inputId = "file_removefromanalysis_dataupload", label = "Remove Last File")),
                       ),
                    )),

                tabPanel("Resume Analysis",
                        div(id = "resumeAnalysis",
                        br(),
                        fluidRow(
                          column(width = 6, fileInput(inputId = "eventdataframe_dataupload", label = "Event Formatted Data", accept = ".csv")),
                        ),

                        hr(),

                        fluidRow(
                          column(width = 6, actionButton(inputId = "eventdataframe_addtoanalysis_dataupload", label = "Add File to Analysis")),
                          column(width = 6, actionButton(inputId = "eventdataframe_removefromanalysis_dataupload", label = "Remove Last File")),
                        ),

                        tags$script(
                          '
                          $("#file_addtoanalysis_dataupload").click(function(){
                              $("#resumeAnalysis").addClass("grey-out");
                          });
                          $("#file_removefromanalysis_dataupload").click(function(){
                              $("#resumeAnalysis").removeClass("grey-out");
                          });
                          '
                        ),
                    )),
            ),
          ),

          mainPanel(
            tableOutput(outputId = "summarytable_dataupload"),
          ),
      ),
      ##################################################################################################
    ),

    tabPanel("Pre-Plot Options",
      ##################################################################################################
      fluidRow(column(width = 12, offset = 0.5,
                      sidebarLayout(
                        div(id = "preplotOptions", sidebarPanel(width = 3,
                          h3("Corrections/Baselines/Downsampling Options"),
                          numericInput(inputId = "preeventtimeplot_MEO", label = "Number of seconds before each event", value = 20, min = 0),
                          numericInput(inputId = "posteventtimeplot_MEO", label = "Number of seconds after each event", value = 150, min = 0),

                          checkboxInput(inputId = "zeropreeventbool_MEO", label = "Zero Pre-event data"),
                          conditionalPanel(condition = "input.zeropreeventbool_MEO == true",
                                           numericInput(inputId = "zeropreeventrange_MEO", label = "Number of seconds pre-event to use to \"zero\" signal", min = 0, value = 20)),

                          checkboxInput(inputId = "baselinezscorebool_MEO", label = "Adjusted Z-Score (Baseline)"),
                          conditionalPanel(condition = "input.baselinezscorebool_MEO == true",
                                           numericInput(inputId = "baselinezscorerange_MEO", label = "Number of seconds pre-event to use to in adjusted Z-score", min = 0, value = 20)),

                          checkboxInput(inputId = "linearfitbool_MEO", label = "Apply linear fit (control to signal)"),

                          fluidRow(
                            column(width = 6,
                                   numericInput(inputId = "graphDownsamplingRate_MEO",
                                                label = "Set Figure Downsampling Rate",
                                                value = 5,
                                                min = 1),
                            ),
                            column(width = 6,
                                   numericInput(inputId = "dataDownsamplingRate_MEO",
                                                label = "Set Data Downsampling Rate",
                                                value = 5,
                                                min = 1),
                            )
                          ),
                          fluidRow(
                            column(width = 6,
                                   actionButton(inputId = "createdataframe_MEO", label = "Create Data with Current Options"),
                            ),
                            column(width = 6,
                                   downloadButton(outputId = "downloadeventdataframe_MEO", label = "Export Event Formatted data"),
                            ),
                          ),
                          tags$script(
                          '
                          $("#eventdataframe_addtoanalysis_dataupload").click(function(){
                              $("#newAnalysis").addClass("grey-out");
                              $("#preplotOptions").addClass("grey-out");
                          });
                          $("#eventdataframe_removefromanalysis_dataupload").click(function(){
                              $("#newAnalysis").removeClass("grey-out");
                              $("#preplotOptions").removeClass("grey-out");
                          });
                          '
                          ),
                        )),

                        mainPanel(
                          width = 9,
                          h3("Plot Group Options"),
                          radioButtons(inputId = "optionsplotgroup_MEO", label = "", choices = c("No Group Analysis", "Basic", "Manual"), selected = "No Group Analysis", inline = TRUE),

                          conditionalPanel(
                            condition = "input.optionsplotgroup_MEO == 'Basic'",
                            radioButtons(inputId = "groupby_basic_MEO", label = "Select group-by method:", choices = c("By Event Name" = "eventname", "By Input File" = "inputfile")),

                            conditionalPanel(
                              condition = "input.groupby_basic_MEO == 'eventname'",
                              selectInput(inputId = "groupby_eventname_MEO", label = "", choices = NULL, multiple = TRUE)
                            ),

                            conditionalPanel(
                              condition = "input.groupby_basic_MEO == 'inputfile'",
                              selectInput(inputId = "groupby_inputfile_MEO", label = "", choices = NULL, multiple = TRUE)
                            ),
                          ),

                          conditionalPanel(
                            condition = "input.optionsplotgroup_MEO == 'Manual'",
                            selectInput(inputId = "groupby_manual_MEO", label = "Select data to assign to group:", choices = NULL, multiple = TRUE, width = "40%")
                          ),

                          conditionalPanel(
                            condition = "input.optionsplotgroup_MEO != 'No Group Analysis'",

                            textInput(inputId = "plotgroupid_MEO", label = "Plot Group ID"),
                            fluidRow(
                              column(width = 2, actionButton(inputId = "createplotgroup_MEO", label = "Create new plot group")),
                              column(width = 2, offset = 1, actionButton(inputId = "deleteplotgroup_MEO", label = "Delete last plot group")),
                            ),
                            fluidRow(
                              column(width = 12, tableOutput(outputId = "plotgrouptable_MEO"))
                            )
                          ),
                        ),
                      ),
        ),
      ),

      fluidRow(column(width = 12, offset = 3,
        actionButton(inputId = "createplots_MEO", label = "Generate Plots")
        ),
      ),

      ##################################################################################################
    ),

    tabPanel("Photometry Plots",
      ##################################################################################################
      sidebarLayout(
        sidebarPanel(width = 1,
                     selectInput(inputId = "statistictoplot_photometryplots", label = "Select y axis",
                                 choices = c("Z-Score" = "-zScore", "Delta F / F" = "-delff")),
        ),

        mainPanel(width = 11,
                  plotlyOutput(outputId = "multieventplot_photometryplots")
        ),
      )
      ##################################################################################################
    ),
  )
)


server <- function(input, output, session) {

  # ── Reactive state ────────────────────────────────────────────────────────

  reactiveHolder <- reactiveValues(
    summarytable_dataupload = blank_df_builder(col_ls = c("Identifier", "SignalFile", "EventFile",
                                                           "ChannelsIncluded", "EventsIncluded",
                                                           "DataPath", "EventPath")),
    inputtable     = blank_df_builder(),  # raw fluorescence intensities
    datatable      = blank_df_builder(),  # dF/F and Z-score per event/channel
    outputtable    = blank_df_builder(),  # group mean ± SEM
    plotgrouptable = blank_df_builder(col_ls = c("GroupID", "Type", "IncludedChannels")),
    ggtable        = blank_df_builder()   # melted data ready for ggplot
  )

  # ── Shared helper: build ggtable from current datatable + plot settings ──────
  # Extracted so both createplots_MEO and the linear-fit toggle can call it
  # without duplicating the group/no-group branching logic.
  build_ggtable <- function() {
    dsRate <- max(1L, floor(input$graphDownsamplingRate_MEO / input$dataDownsamplingRate_MEO))

    if (input$optionsplotgroup_MEO == "No Group Analysis") {
      allStatCols <- setdiff(colnames(reactiveHolder$datatable), "timestamp")
      reactiveHolder$ggtable <- ggtable_builder(
        outputTable    = reactiveHolder$datatable,
        id             = "timestamp",
        downsampleRate = dsRate,
        measures       = list(allStatCols)
      )
    } else {
      req(nrow(reactiveHolder$plotgrouptable) > 0L)
      reactiveHolder$outputtable <- outputtable_builder(
        summaryTable   = reactiveHolder$summarytable_dataupload,
        dataTable      = reactiveHolder$datatable,
        plotGroupTable = reactiveHolder$plotgrouptable
      )
      allCols         <- grep("timestamp", colnames(reactiveHolder$outputtable), value = TRUE, invert = TRUE)
      colPlot_mean    <- grep("-mean-",  allCols, value = TRUE)
      colPlot_PLUSSEM <- grep("SEMPLUS", allCols, value = TRUE)
      colPlot_NEGSEM  <- grep("SEMNEG",  allCols, value = TRUE)
      reactiveHolder$ggtable <- ggtable_builder(
        outputTable    = reactiveHolder$outputtable,
        id             = "timestamp",
        downsampleRate = dsRate,
        measures       = list(colPlot_mean, colPlot_PLUSSEM, colPlot_NEGSEM),
        factors        = reactiveHolder$plotgrouptable$GroupID
      )
      colnames(reactiveHolder$ggtable) <- c("timestamp", "Group", "mean", "plusSEM", "negSEM")
    }
  }

  # ── File upload reactives ─────────────────────────────────────────────────

  fileopen_dataupload <- reactive({
    read.csv(req(input$fpdata_dataupload$datapath), header = TRUE, sep = ",", nrows = 2, check.names = FALSE)
  })

  fileopen_eventupload <- reactive({
    read.csv(req(input$eventdata_dataupload$datapath), header = TRUE, sep = ",", check.names = FALSE)
  })

  # ── Data Upload Logic ─────────────────────────────────────────────────────

  # Mirror combined channel list back into the text field for user visibility
  observe({
    updateTextInput(inputId = "channellist_dataupload",
                    value = paste(c(input$signallist_dataupload, input$controllist_dataupload), collapse = ","))
  })

  # Populate signal/control channel selectors from the uploaded photometry file
  observe({
    inputError <- case_when(
      !any(colnames(fileopen_dataupload()) == "timestamp") ~ "Can't find a \"timestamp\" column in the signal file!",
      !ncol(fileopen_dataupload()) > 1                    ~ "Can't find sufficient data to proceed - check signal file!",
      TRUE ~ ""
    )
    if (inputError != "") {
      showModal(modalDialog(title = "Signal File Error", inputError, easyClose = TRUE))
      return()
    }
    ind      <- which(colnames(fileopen_dataupload()) == "timestamp")
    datacols <- colnames(fileopen_dataupload())[(ind + 1):ncol(fileopen_dataupload())]
    updateSelectInput(inputId = "signallist_dataupload",  choices = datacols)
    updateSelectInput(inputId = "controllist_dataupload", choices = datacols)
  })

  # Populate event selector from the uploaded event file
  observe({
    inputError <- case_when(
      !any(colnames(fileopen_eventupload()) == "Event")           ~ "Can't find an \"Event\" column in the event file!",
      !any(colnames(fileopen_eventupload()) == "Start Time (s)") ~ "Can't find a \"Start Time (s)\" column in the event file!",
      !any(colnames(fileopen_eventupload()) == "End Time (s)")   ~ "Can't find a \"End Time (s)\" column in the event file!",
      TRUE ~ ""
    )
    if (inputError != "") {
      showModal(modalDialog(title = "Event File Error", inputError, easyClose = TRUE))
      return()
    }
    eventcols <- append_frequency(fileopen_eventupload()[["Event"]])
    updateSelectInput(inputId = "eventlist_dataupload", choices = eventcols, selected = eventcols)
  })

  observeEvent(input$file_addtoanalysis_dataupload, {
    req(input$fpdata_dataupload)

    identifier <- if (nchar(input$dataidentifier_dataupload) == 0) {
      paste0("Exp.", nrow(reactiveHolder$summarytable_dataupload) + 1L)
    } else {
      gsub(",", ".", input$dataidentifier_dataupload)
    }

    signalName <- gsub(",", ".", input$fpdata_dataupload$name)
    signalPath <- input$fpdata_dataupload$datapath

    if (is.null(input$eventdata_dataupload)) {
      eventName <- NA; eventPath <- NA; eventList <- NA
    } else {
      eventName <- gsub(",", ".", input$eventdata_dataupload$name)
      eventPath <- input$eventdata_dataupload$datapath
      eventList <- paste(input$eventlist_dataupload, collapse = ",")
    }

    nChannels <- length(strsplit(input$channellist_dataupload, ",")[[1]])
    if (nChannels %% 2L != 0L) {
      showModal(modalDialog(
        title = "Channel List Error",
        "For every signal channel we need a paired control channel (even number required).",
        easyClose = TRUE
      ))
      return()
    }

    reactiveHolder$summarytable_dataupload <- add_row(
      reactiveHolder$summarytable_dataupload,
      c(identifier, signalName, eventName, input$channellist_dataupload, eventList, signalPath, eventPath)
    )
  })

  observeEvent(input$file_removefromanalysis_dataupload, {
    req(nrow(reactiveHolder$summarytable_dataupload) > 0L)
    reactiveHolder$summarytable_dataupload <- del_row(reactiveHolder$summarytable_dataupload)
  })

  observeEvent(input$eventdataframe_addtoanalysis_dataupload, {
    req(input$eventdataframe_dataupload)
    reactiveHolder$datatable <- read.csv(input$eventdataframe_dataupload$datapath,
                                         header = TRUE, sep = ",", check.names = FALSE)
    # Derive selector choices from the loaded datatable column names
    baseCols   <- colnames(reactiveHolder$datatable)[seq(2L, ncol(reactiveHolder$datatable) - 1L, by = 2L)]
    baseCols   <- sub("-delff", "", baseCols)
    eventnames <- unique(sub("^[^-]+-([^-]+).*", "\\1", baseCols))
    updateSelectInput(inputId = "groupby_manual_MEO",    choices = baseCols)
    updateSelectInput(inputId = "groupby_eventname_MEO", choices = eventnames)
  })

  observeEvent(input$eventdataframe_removefromanalysis_dataupload, {
    req(nrow(reactiveHolder$datatable) > 1L)
    reactiveHolder$datatable <- blank_df_builder()
    updateSelectInput(inputId = "groupby_manual_MEO",    choices = NULL)
    updateSelectInput(inputId = "groupby_eventname_MEO", choices = NULL)
  })

  output$summarytable_dataupload <- renderTable({
    reactiveHolder$summarytable_dataupload[1:5]
  })

  # ── Pre-Plot Options Logic ────────────────────────────────────────────────

  output$downloadeventdataframe_MEO <- downloadHandler(
    filename = "eventdata.csv",
    content  = function(file) {
      req(ncol(reactiveHolder$datatable) > 1L)
      write.csv(reactiveHolder$datatable, file, row.names = FALSE, na = "")
    }
  )

  observeEvent(input$createdataframe_MEO, {

    # Reset all derived tables before rebuilding
    reactiveHolder$inputtable     <- blank_df_builder()
    reactiveHolder$datatable      <- blank_df_builder()
    reactiveHolder$outputtable    <- blank_df_builder()
    reactiveHolder$plotgrouptable <- blank_df_builder(col_ls = c("GroupID", "Type", "IncludedChannels"))
    reactiveHolder$ggtable        <- blank_df_builder()

    # Extract range must cover the widest active window (plot, zero, or baseline)
    startVals   <- c(input$preeventtimeplot_MEO, input$zeropreeventrange_MEO, input$baselinezscorerange_MEO)
    activeMask  <- c(TRUE, input$zeropreeventbool_MEO, input$baselinezscorebool_MEO)
    extractfrom <- max(startVals[activeMask])

    reactiveHolder$inputtable <- inputtable_builder(
      summaryTable  = reactiveHolder$summarytable_dataupload,
      extractRange  = c(extractfrom, input$posteventtimeplot_MEO),
      downsampleData = input$dataDownsamplingRate_MEO
    )

    zeroRange     <- if (input$zeropreeventbool_MEO)     c(-input$zeropreeventrange_MEO,    0) else NULL
    baselineRange <- if (input$baselinezscorebool_MEO)   c(-input$baselinezscorerange_MEO,  0) else NULL

    reactiveHolder$datatable <- datatable_builder(
      inputTable    = reactiveHolder$inputtable,
      summaryTable  = reactiveHolder$summarytable_dataupload,
      zeroRange     = zeroRange,
      baselineRange = baselineRange,
      outputRange   = c(input$preeventtimeplot_MEO, input$posteventtimeplot_MEO),
      linearFit     = input$linearfitbool_MEO
    )

    # Populate grouping selectors
    baseCols   <- colnames(reactiveHolder$datatable)[seq(2L, ncol(reactiveHolder$datatable) - 1L, by = 2L)]
    baseCols   <- sub("-delff", "", baseCols)
    eventnames <- unique(gsub("_\\d+$", "", unlist(strsplit(reactiveHolder$summarytable_dataupload$EventsIncluded, ","))))

    updateSelectInput(inputId = "groupby_manual_MEO",    choices = baseCols)
    updateSelectInput(inputId = "groupby_inputfile_MEO", choices = append_frequency(reactiveHolder$summarytable_dataupload$Identifier))
    updateSelectInput(inputId = "groupby_eventname_MEO", choices = eventnames)
  })

  # ── Plot Group Logic ──────────────────────────────────────────────────────

  observeEvent(input$createplotgroup_MEO, {
    gid <- if (nchar(input$plotgroupid_MEO) > 1L) {
      input$plotgroupid_MEO
    } else {
      paste0("Group.", nrow(reactiveHolder$plotgrouptable) + 1L)
    }

    if (input$optionsplotgroup_MEO == "Basic") {
      channels <- if (input$groupby_basic_MEO == "eventname") {
        list("eventname", paste(input$groupby_eventname_MEO, collapse = ","))
      } else {
        list("inputfile", paste(input$groupby_inputfile_MEO, collapse = ","))
      }
      reactiveHolder$plotgrouptable <- add_row(reactiveHolder$plotgrouptable,
                                               c(gid, channels[[1]], channels[[2]]))
    } else {
      reactiveHolder$plotgrouptable <- add_row(reactiveHolder$plotgrouptable,
                                               c(gid, "manual", paste(input$groupby_manual_MEO, collapse = ",")))
    }
  })

  observeEvent(input$deleteplotgroup_MEO, {
    req(nrow(reactiveHolder$plotgrouptable) > 0L)
    reactiveHolder$plotgrouptable <- del_row(reactiveHolder$plotgrouptable)
  })

  output$plotgrouptable_MEO <- renderTable({ reactiveHolder$plotgrouptable })

  observeEvent(input$createplots_MEO, {
    req(nrow(reactiveHolder$datatable) > 0L)
    build_ggtable()
  })

  # Re-run datatable and ggtable when the linear fit toggle changes, but only
  # if data has already been processed and plots have already been generated.
  observeEvent(input$linearfitbool_MEO, {
    req(nrow(reactiveHolder$inputtable) > 0L)
    req(nrow(reactiveHolder$ggtable)    > 0L)

    zeroRange     <- if (input$zeropreeventbool_MEO)   c(-input$zeropreeventrange_MEO,   0) else NULL
    baselineRange <- if (input$baselinezscorebool_MEO) c(-input$baselinezscorerange_MEO, 0) else NULL

    reactiveHolder$datatable <- datatable_builder(
      inputTable    = reactiveHolder$inputtable,
      summaryTable  = reactiveHolder$summarytable_dataupload,
      zeroRange     = zeroRange,
      baselineRange = baselineRange,
      outputRange   = c(input$preeventtimeplot_MEO, input$posteventtimeplot_MEO),
      linearFit     = input$linearfitbool_MEO
    )

    build_ggtable()
  }, ignoreInit = TRUE)

  # ── Photometry Plot ───────────────────────────────────────────────────────

  output$multieventplot_photometryplots <- renderPlotly({
    req(nrow(reactiveHolder$ggtable) > 0L)

    tryCatch({
      stat <- input$statistictoplot_photometryplots
      ylab <- switch(stat, "-zScore" = "Z-Score", "-delff" = "Delta F / F")

      if (input$optionsplotgroup_MEO == "No Group Analysis") {
        # Filter the melted table to the selected statistic (reactive: updates on selector change)
        validGroups <- grep(paste0(stat, "$"), levels(reactiveHolder$ggtable$Group), value = TRUE)
        plotData    <- subset(reactiveHolder$ggtable, Group %in% validGroups)
        p <- ggplot(plotData, aes(x = timestamp, y = value, color = Group)) +
          geom_line() + labs(x = "Time / s", y = ylab)
        ggplotly(p)

      } else {
        validGroups <- unique(grep(paste0(stat, "$"), as.character(reactiveHolder$ggtable$Group), value = TRUE))
        plotData    <- subset(reactiveHolder$ggtable, Group %in% validGroups)
        p <- ggplot(plotData, aes(x = timestamp, color = Group)) +
          geom_line(aes(y = mean), linewidth = 0.75) +
          geom_ribbon(aes(ymax = plusSEM, ymin = negSEM, fill = Group), alpha = 0.3, linewidth = 0.1) +
          labs(x = "Time / s", y = ylab)
        p <- ggplotly(p)
        # Hide legend + hover for ribbon traces (shown after line traces in plotly layer order)
        style(p, showlegend = FALSE, hoverinfo = "none",
              traces = (length(validGroups) + 1L):(2L * length(validGroups)))
      }

    }, error = function(e) {
      ggplotly(
        ggplot() +
          annotate("text", x = 0.5, y = 0.5,
                   label = paste("Plot error:", conditionMessage(e)), size = 4) +
          theme_void() + xlim(0, 1) + ylim(0, 1)
      )
    })
  })
}

shinyApp(ui = ui, server = server)
