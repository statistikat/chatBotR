#' Add File to LLM Cache
#'
#' Uploads a local file to the LLM provider API and maintains a local cache
#' (RDS file) to prevent re-uploading identical files (based on hash).
#'
#' @param path Character. Path to the local file.
#' @param provider Character.
#' @return Data frame row containing file ID and metadata.
llm_add_file <- function(path, provider = "local") {
  stopifnot(file.exists(path))
  
  # Verify Cache DB configuration
  f_cache <- Sys.getenv("llm_caching_db")
  if (!nzchar(f_cache)) stop("Env var `llm_caching_db` is unset")
  
  # Load or Initialize Cache
  if (file.exists(f_cache)) {
    cache <- readRDS(file = f_cache)
  } else {
    cache <- data.frame(
      id = character(),
      provider = character(),
      filename = character(),
      path = character(),
      hash = character(),
      stringsAsFactors = FALSE
    )
  }
  
  # Compute file hash
  hash_value <- digest::digest(object = path, algo = "sha256", file = TRUE)
  
  # Check Cache
  df <- subset(cache, cache$hash == hash_value & provider == provider)
  if (nrow(df) == 1) {
    cli::cli_alert_info("File '{basename(path)}' (Hash: {substring(hash_value, 1, 8)}) already exists in cache.")
    return(df)
  }
  
  # Upload to API
  creds <- llm_creds(provider = provider)
  upload_url <- paste0(fs::path(creds$base_url, "v1", "files"), "/")
  
  res <- httr::POST(
    url = upload_url,
    httr::add_headers(Authorization = paste("Bearer", creds$token)),
    body = list(file = httr::upload_file(path)),
    encode = "multipart"
  )
  
  if (httr::http_error(res)) {
    stop(
      "HTTP upload failed: ", httr::status_code(res), "\n",
      httr::content(res, "text")
    )
  }
  
  # Parse Response and Update Cache
  cc <- httr::content(res)
  new_entry <- data.frame(
    id = cc$id,
    filename = cc$filename,
    path = cc$path,
    hash = hash_value,
    stringsAsFactors = FALSE
  )
  
  # For sspcloud/standard schema compliance, ensure columns match
  new_entry$provider <- provider 
  
  # Bind and Save
  # Ensure columns align before binding in case schema varies slightly
  common_cols <- intersect(names(cache), names(new_entry))
  cache <- rbind(cache, new_entry[common_cols]) 
  saveRDS(cache, file = f_cache)
  
  return(new_entry)
}