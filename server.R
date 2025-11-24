server <- function(input, output, session) {
  # Reactive Values 
  result <- reactiveVal(NULL)
  params <- reactiveVal()
  debug_data <- reactiveVal(list())
  reset_counter <- reactiveVal(0)
  
  # Dynamic UI Updates
  observeEvent(input$provider, {
    req(input$provider)
    updateSelectInput(
      session = session,
      inputId = "model",
      choices = available_models[[input$provider]]
    )
  })
  
  # Main Query Logic
  observeEvent(input$btn_query, {
    # Validation
    req(input$model, input$top_k, input$max_tokens, input$temperature, input$query, input$provider)
    if (nchar(input$query) == 0) return(NULL)
    
    # Initialize Debug Data
    dbg <- list()
    
    # Progress Bar
    progress <- Progress$new(session, min = 0, max = 10)
    on.exit(progress$close())
    
    # 1. Improve Query
    progress$set(value = 1, message = glue::glue("[{llm_ts()}] Optimizing search term..."))
    
    res_improve_query <- tryCatch(
      expr = llm_improve_query(
        q = input$query, 
        model = input$model, 
        provider = input$provider,
        lang = input$language
      ), 
      error = function(e) e
    )
    
    if (inherits(res_improve_query, "error")) {
      shinyalert::shinyalert("Error", "Failed to optimize query via LLM.", type = "error")
      reset_counter(reset_counter() + 1)
      return(NULL)
    }
    
    dbg$reqest_improve_query <- res_improve_query
    q_improved <- res_improve_query$choices$message$content
    
    # 2. Google Search
    progress$set(value = 2, message = glue::glue("[{llm_ts()}] Searching Google..."))
    
    # 2. Update llm_search call
    # Note: 'site' is not passed explicitly;
    # in this case, the value is read from environment-variable GCS_SITE
    res_google <- tryCatch(
      expr = llm_search(
        q = q_improved, 
        top_k = input$max_n
      ),
      error = function(e) e
    )
    
    # Fallback to original query if optimized fails to return results
    if (inherits(res_google, "error") || length(res_google$items) == 0) {
      res_google <- tryCatch(
        expr = llm_search(q = input$query, top_k = input$max_n, site = "statistik.at"),
        error = function(e) e
      )
    }
    
    if (inherits(res_google, "error")) {
      shinyalert::shinyalert("Error", "Google Search failed.", type = "error")
      reset_counter(reset_counter() + 1)
      return(NULL)
    } else if (as.numeric(res_google$searchInformation$totalResults) == 0) {
      shinyalert::shinyalert("Info", "No search results found.", type = "warning")
      reset_counter(reset_counter() + 1)
      return(NULL)
    }
    
    dbg$request_google_search <- res_google
    progress$set(value = 3, message = "[{llm_ts()}] Search complete")
    
    # 3. Prepare Files (Download & Upload to LLM)
    files <- list()
    if (input$provider != "gcs") {
      files <- prepare_results(res_google, provider = input$provider)
      progress$set(value = 6, message = glue::glue("[{llm_ts()}] {length(files)} files processed"))
    } else {
      # GCS provider just needs links, typically
      files <- sapply(res_google$items, function(x) x$link)
    }
    
    # 4. Generate Prompt
    prompt <- llm_gen_prompt(
      files = files, 
      meta = res_google$items, 
      provider = input$provider,
      lang = input$language
    )
    
    # Save parameters for debug
    para <- list(
      model = input$model,
      top_k = input$top_k,
      max_tokens = input$max_tokens * 1000,
      max_n = input$max_n,
      temperature = input$temperature,
      query = input$query,
      query_improved = q_improved,
      prompt = prompt
    )
    params(para)
    dbg$params <- para
    
    progress$set(value = 7, message = "[{llm_ts()}] Prompt generated")
    
    # 5. Final LLM Request
    progress$set(value = 8, message = "[{llm_ts()}] Waiting for LLM answer...")
    
    out <- tryCatch(
      expr = llm_request(
        q = input$query,
        prompt = prompt,
        model = input$model,
        files = files,
        temperature = input$temperature,
        max_tokens = input$max_tokens * 1000,
        top_k = input$top_k,
        provider = input$provider
      ),
      error = function(e) e
    )
    
    if (inherits(out, "error")) {
      shinyalert::shinyalert("Error", "LLM failed to generate an answer.", type = "error")
      reset_counter(reset_counter() + 1)
      return(NULL)
    }
    
    dbg$request_model_answer <- out
    debug_data(dbg)
    result(out)
    
    progress$set(value = 10, message = "Done!")
  })
  
  # Outputs
  
  # Format Final Answer
  llm_final_answer <- reactive({
    llm_extract_answer(result())
  })
  
  output$llm_answer <- renderUI({
    r <- tryCatch(llm_final_answer())
    if (is.null(r)) return(NULL)
    HTML(markdown::markdownToHTML(text = r, fragment.only = TRUE))
  })
  
  output$prompt <- renderUI({
    req(params())
    HTML(markdown::markdownToHTML(text = params()$prompt, fragment.only = TRUE))
  })
  
  output$query <- renderText({ params()$query })
  output$query_improved <- renderText({ params()$query_improved })
  
  output$gcs_results <- renderUI({
    x <- debug_data()$request_google_search
    if (is.null(x)) return(NULL)
    
    res <- paste(sapply(x$items, function(item) {
      glue::glue("- [{item$title}]({item$link})")
    }), collapse = "\n")
    
    HTML(markdown::markdownToHTML(text = res, fragment.only = TRUE))
  })
  
  # UI Parameter displays
  output$model <- renderText({ params()$model })
  output$top_k <- renderText({ params()$top_k })
  output$max_tokens <- renderText({ params()$max_tokens })
  output$temperature <- renderText({ params()$temperature })
  output$max_n <- renderText({ params()$max_n })

  # State Management
  # Conditionals for UI visibility
  output$show_results <- reactive({ !is.null(llm_final_answer()) })
  outputOptions(output, "show_results", suspendWhenHidden = FALSE)
  
  output$show_reset_btn <- reactive({ !is.null(llm_final_answer()) })
  outputOptions(output, "show_reset_btn", suspendWhenHidden = FALSE)
  
  # Reset Logic
  observeEvent(input$btn_reset, {
    reset_counter(reset_counter() + 1)
  })
  
  observeEvent(reset_counter(), {
    if (reset_counter() > 0) {
      result(NULL)
      params(NULL)
      debug_data(list())
    }
  })
  
  # Download Handler
  output$btn_download <- downloadHandler(
    filename = function() {
      paste("llm-debug-", format(Sys.Date(), '%Y%m%d-%H%M%S'), ".json", sep = "")
    },
    content = function(file) {
      cat(jsonlite::toJSON(debug_data(), pretty = TRUE), file = file)
    }
  )
  
  # Helpers for empty states
  no_results_html <- reactive({
    tagList(br(), p("No results available yet."))
  })
  output$no_results_1 <- renderUI({ no_results_html() })
  output$no_results_2 <- renderUI({ no_results_html() })
}