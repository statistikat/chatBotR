#' Google Custom Search
#'
#' Performs a search on the specified site using Google Custom Search JSON API.
#'
#' @param q Character. The search query.
#' @param top_k Integer. Number of results to return.
#' @param site Character. Domain to restrict search to (default: statistik.at).
#' @return Parsed JSON response from Google.
llm_search <- function(q, top_k = 5, site = NULL) {
  url <- "https://www.googleapis.com/customsearch/v1"
  # Use config variable if site is not explicitly passed
  if (is.null(site)) {
    site <- Sys.getenv("GCS_SITE") 
    if (site == "") {
      stop("GCS_SITE environment variable is not set.")
    }
  }  
  params <- list(
    key = Sys.getenv("GCS_APIKEY"),
    cx = Sys.getenv("GCS_CX"),
    q = paste(q, "site:", site),
    num = top_k,
    start = 1
  )
  
  res <- httr::GET(url, query = params)
  
  if (httr::http_error(res)) {
    stop(
      "HTTP request failed: ", httr::status_code(res), "\n",
      httr::content(res, "text")
    )
  }
  return(httr::content(res, as = "parsed", type = "application/json"))
}

#' Download and Prepare Search Results
#'
#' Downloads PDFs or HTML content from Google Search results and uploads
#' them to the LLM provider (if RAG is supported).
#'
#' @param res_google List. Results from `llm_search`.
#' @param provider Character. The LLM provider.
#' @return List of file objects/IDs ready for the prompt generator.
prepare_results <- function(res_google, provider) {
  files <- list()
  n <- length(res_google$items)
  
  for (i in seq_len(n)) {
    x <- res_google$items[[i]]
    
    # Handle PDFs
    if (!is.null(x$mime) && x$mime == "application/pdf") {
      f_tmp <- file.path(getwd(), basename(x$link))
      tryCatch({
        download.file(url = x$link, destfile = f_tmp, quiet = TRUE, mode = "wb")
        files[[i]] <- f_tmp
      }, error = function(e) {
        cli::cli_alert_warning(glue::glue("Failed to download PDF: {x$link}"))
      })
      
      # Handle HTML
    } else {
      f_tmp <- file.path(getwd(), glue::glue("url_src_{i}.html"))
      src <- tryCatch(
        as.character(httr::content(httr::GET(x$link), encoding = "UTF-8")),
        error = function(e) e
      )
      
      if (!inherits(src, "error")) {
        cat(src, file = f_tmp)
        files[[i]] <- f_tmp
      }
    }
  }
  
  cli::cli_alert_success(glue::glue("[{llm_ts()}] Google results downloaded"))
  
  # Remove NULLs (failed downloads)
  files <- files[!sapply(files, is.null)]
  
  # Upload to LLM Provider
  processed_files <- list()
  for (i in seq_along(files)) {
    f <- files[[i]]
    cli::cli_alert_info(glue::glue("[{llm_ts()}] Uploading {shQuote(basename(f))} ({i}/{length(files)})"))
    
    # Upload and store result
    processed_files[[i]] <- llm_add_file(path = f, provider = provider)
    
    # Cleanup local file
    try(file.remove(f), silent = TRUE)
  }
  
  cli::cli_alert_success(glue::glue("[{llm_ts()}] {length(processed_files)} files uploaded to LLM"))
  return(processed_files)
}