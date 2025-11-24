#' Retrieve LLM Credentials
#'
#' Helper to get the correct URL and Token based on the selected provider.
#'
#' @param provider Character. "local", "sspcloud", or "gcs".
#' @return List containing `base_url` and `token`.
llm_creds <- function(provider = "local") {
  stopifnot(length(provider) == 1 && is.character(provider))
  
  if (provider == "gcs") {
    return(list()) # GCS uses specific env vars directly
  }
  
  ee_url <- toupper(glue::glue("{provider}_BASE_URL"))
  ee_token <- toupper(glue::glue("{provider}_TOKEN"))

  base_url <- Sys.getenv(ee_url, unset = NA)
  if (base_url == "") {
    stop("env-var", ee_url, " is unset")
  }
  token <- Sys.getenv(ee_token, unset = "")
  if (token == "") {
    stop("env-var", ee_token, " is unset")
  }
  
  return(list(base_url = base_url, token = token))
}

#' Generic LLM Request Handler
#'
#' Sends generic POST/GET requests to OpenAI-compatible endpoints.
#'
#' @param endpoint Character. API endpoint (e.g., "chat/completions").
#' @param body_data List. The JSON body payload.
#' @param provider Character. The provider name.
#' @param method Character. "POST" or "GET".
#' @return Parsed JSON list.
llm_request_default <- function(endpoint = "chat/completions", body_data,
                                provider = "llm", method = "POST") {
  creds <- llm_creds(provider = provider)
  url <- paste0(creds$base_url, endpoint)
  headers <- httr::add_headers(Authorization = paste("Bearer", creds$token))
  
  if (method == "POST") {
    res <- httr::POST(url = url, headers, body = body_data, encode = "json")
  } else {
    res <- httr::GET(url = url, headers)
  }
  
  if (httr::http_error(res)) {
    stop(
      "HTTP request failed: ", httr::status_code(res), "\n",
      httr::content(res, "text", encoding = "UTF-8")
    )
  }
  
  jsonlite::fromJSON(httr::content(res, "text", encoding = "UTF-8"))
}

#' Main LLM Chat Request
#'
#' Coordinates the request to the LLM, handling both OpenAI-compatible APIs
#' and Google Gemini via the `ellmer` package.
#'
#' @param q Character. The user query.
#' @param prompt Character. The system prompt (context).
#' @param model Character. Model ID.
#' @param files List. Files content/IDs (for RAG).
#' @param provider Character.
#' @param ... Additional parameters (temperature, max_tokens, top_k).
#' @return List containing the response.
llm_request <- function(q, prompt, model = "gpt-oss:120b", files = NULL,
                        provider = "llm", ...) {
  args <- list(...)
  
  # Handle OpenAI-compatible Providers
  if (provider != "gcs") {
    body_data <- list(
      model = model,
      messages = list(
        list(role = "system", content = prompt),
        list(role = "user", content = q)
      ),
      files = lapply(files, function(x) list(type = "file", id = x$id))
    )
    
    # Add optional parameters if they exist
    if (length(args) > 0) body_data$params <- args
    
    return(llm_request_default(
      endpoint = "chat/completions",
      body_data = body_data,
      provider = provider
    ))
  }
  
  # --- 2. Handle Google Gemini (GCS) ---
  if (substring(model, 1, 6) == "gemini") {
    # Prepare parameters for ellmer
    chat_params <- list()
    if (all(c("top_k", "temperature", "max_tokens") %in% names(args))) {
      chat_params <- ellmer::params(
        top_k = args[["top_k"]],
        temperature = args[["temperature"]],
        max_tokens = args[["max_tokens"]]
      )
    }
    
    chat <- ellmer::chat_google_gemini(
      api_key = Sys.getenv("GCS_APIKEY"),
      system_prompt = prompt,
      model = model,
      params = chat_params
    )
    
    # Mimic the structure of the OpenAI response object for consistency in UI
    return(list(
      model = model,
      choices = list(
        message = data.frame(
          role = "assistant",
          content = chat$chat(q, echo = "all")
        )
      ),
      usage = args
    ))
  }
  
  stop("Model provider not supported.")
}

#' Improve Search Query with Dynamic Geo-Restriction
#'
#' @param q Character.
#' @param model Character.
#' @param provider Character.
#' @param lang Character.
llm_improve_query <- function(q, model = "gpt-oss:120b", provider = "custom", lang = "en") {
  
  # Dynamic Geo-Logic
  site <- Sys.getenv("GCS_SITE")
  tld <- tools::file_ext(site)
  
  # Map TLD to search context string
  geo_context <- switch(tld,
    "at" = "(Österreich OR Austria OR AT)",
    "de" = "(Deutschland OR Germany OR DE)",
    "ch" = "(Schweiz OR Switzerland OR CH)",
    "uk" = "(UK OR United Kingdom)",
    "fr" = "(France OR Frankreich)",
    "eu" = "(EU OR Europe OR Europa)",
    # Fallback: use the site domain itself as the context context
    paste0("(", site, ")")
  )
  
  # --- Prompt Templates ---
  prompts <- list(
    de = '
    Verbessere den folgenden Input zu einem kompakten Google-CSE-Suchstring (ohne Erklärungen): {shQuote(query_orig)}.
    Prüfe zuerst, ob der Input bereits einen konkreten Regionalbezug hat.
    Wenn JA: korrigiere Tippfehler, aber behalte die Region.
    Wenn NEIN: füge folgende Eingrenzung hinzu: {geo_context}.
    Nutze Google-Operatoren (OR, -, intitle:). Gib nur den Suchstring aus.
    ',
    
    en = '
    Optimize the following input into a compact Google CSE search string (no explanations): {shQuote(query_orig)}.
    Check if the input already contains specific regional references.
    If YES: fix typos but keep the region.
    If NO: add the following restriction: {geo_context}.
    Use Google operators (OR, -, intitle:). Output ONLY the final search string.
    '
  )
  
  system_instruction <- if (!is.null(prompts[[lang]])) {
    prompts[[lang]] 
  } else {
    prompts[["en"]]
  }
  
  # Inject variables
  formatted_prompt <- glue::glue(system_instruction, query_orig = q, geo_context = geo_context)
  
  if (provider != "gcs") {
    body_data <- list(
      model = model,
      messages = list(
        list(role = "user", content = formatted_prompt)
      )
    )
    return(llm_request_default(
      endpoint = "chat/completions", 
      body_data = body_data, 
      provider = provider
    ))
  } else {
    # Gemini
    chat <- ellmer::chat_google_gemini(
      api_key = Sys.getenv("GCS_APIKEY"),
      system_prompt = system_instruction,
      model = model
    )
    return(list(
      model = model, 
      choices = list(
        message = data.frame(
          role = "assistant", 
          content = chat$chat(q, echo = "all")
        )
      )
    ))
  }
}