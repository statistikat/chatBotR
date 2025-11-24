ui <- fluidPage(
  theme = bslib::bs_theme(version = 5),
  titlePanel("chatBOTr"),
  
  sidebarLayout(
    sidebarPanel(
      h4("Language"),
      selectInput(
        inputId = "language",
        label = "Language / Sprache",
        choices = c("English" = "en", "Deutsch" = "de"),
        selected = "en",
        multiple = FALSE
      ),      
      h4("Model Settings"),
      
      # Input Controls (Visible when NO results are shown)
      conditionalPanel(
        condition = "output.show_reset_btn == false",
        selectInput(
          inputId = "provider",
          label = "LLM Provider",
          choices = c("Remote / Local LLM" = "llm", "Google Gemini" = "gcs"),
          selected = "llm",
          multiple = FALSE
        ),
        selectInput(
          inputId = "model",
          label = "Model",
          choices = NULL, # Populated server-side
          multiple = FALSE
        ),
        textInput(
          inputId = "query",
          label = "Query",
          placeholder = "Please enter your question here..."
        ),
        sliderInput(
          inputId = "max_n",
          label = "Max. Google Results",
          min = 2, max = 15, step = 1, value = 5
        ),
        sliderInput(
          inputId = "top_k",
          label = "top_k (Higher = More Random)",
          min = 10, max = 80, step = 1, value = 40
        ),
        sliderInput(
          inputId = "temperature",
          label = "temperature (Higher = More Creative)",
          min = 0.1, max = 1.0, step = 0.1, value = 0.2
        ),
        sliderInput(
          inputId = "max_tokens",
          label = "max_tokens (in thousands)",
          min = 4, max = 128, step = 4, value = 16
        )
      ),
      
      # Exposed LLM-Parameters
      conditionalPanel(
        condition = "output.show_reset_btn == true",
        tags$ul(
          tags$li(strong("Model: "), textOutput("model", inline = TRUE)),
          tags$li(strong("max_n: "), textOutput("max_n", inline = TRUE)),
          tags$li(strong("top_k: "), textOutput("top_k", inline = TRUE)),
          tags$li(strong("temperature: "), textOutput("temperature", inline = TRUE)),
          tags$li(strong("max_tokens: "), textOutput("max_tokens", inline = TRUE))
        )
      ),
      
      hr(),
      
      # Action Buttons
      conditionalPanel(
        condition = "output.show_reset_btn == false",
        actionButton(
          inputId = "btn_query",
          label = "Run Query",
          class = "btn-primary",
          width = "100%"
        )
      ),
      conditionalPanel(
        condition = "output.show_reset_btn == true",
        downloadButton(
          outputId = "btn_download",
          label = "Download Debug Data",
          class = "btn-secondary",
          style = "margin-bottom: 10px; width: 100%;"
        ),
        actionButton(
          inputId = "btn_reset",
          label = "Start New Query",
          class = "btn-warning",
          width = "100%"
        )
      )
    ),
    
    # Main Display
    mainPanel(
      tabsetPanel(
        tabPanel(
          "Results",
          conditionalPanel(
            condition = 'output.show_results == true',
            br(),
            wellPanel(
              h4("Original Query"),
              verbatimTextOutput("query")
            ),
            wellPanel(
              h4("Optimized Search Query"),
              verbatimTextOutput("query_improved")
            ),
            div(
              class = "card p-3",
              h3("Answer"),
              uiOutput("llm_answer")
            )
          ),
          conditionalPanel(
            condition = 'output.show_results == false',
            uiOutput("no_results_1")
          )
        ),
        
        tabPanel(
          "Metadata / Prompt",
          conditionalPanel(
            condition = 'output.show_results == true',
            br(),
            h4("Google Search Results (Context)"),
            p("These pages were provided to the LLM:"),
            uiOutput("gcs_results"),
            hr(),
            h4("Generated System Prompt"),
            uiOutput("prompt")
          ),
          conditionalPanel(
            condition = 'output.show_results == false',
            uiOutput("no_results_2")
          )
        )
      )
    )
  )
)