rm(list = ls())

source("R/llm_add_file.R")
source("R/llm_extract_answer.R")
source("R/llm_gen_prompt.R")
source("R/llm_request.R")
source("R/llm_search.R")
source("R/llm_utils.R")

# Dependencies
library(shiny)
library(shinyalert)
library(cli)
library(httr)
library(ellmer)
library(jsonlite)
library(digest)
library(markdown)

# Configuration & Environment Check
# Could be defined also in .Renviron!

# LLM Endpoint (OpenAI compatible, e.g., local Llama, vLLM, or SSPCloud)
# We need a Api-Url and a Api_token
Sys.setenv("LLM_BASE_URL" = "https://llm.lab.sspcloud.fr/api/");
#Sys.setenv("LLM_TOKEN" = "") # your Api-Token

# Credentials for Google Custom Search
#Sys.setenv("GCS_CX" = "") # your Google Cx Id
#Sys.setenv("GCS_APIKEY" = "your Google Custom Search Api Token");
Sys.setenv("GCS_SITE" = "statistik.at") # restricted to use a site

# Poor-Mans Cache for uploaded files
Sys.setenv("LLM_CACHING_DB" = "file-upload-cache.rds");

# Overwrite these Env-Vars from .Renviron
try(readRenviron(".Renviron"))

# Load and validate environment variables
config <- list(
  llm_url  = Sys.getenv("LLM_BASE_URL"),
  llm_key  = Sys.getenv("LLM_TOKEN"),
  cache_db   = Sys.getenv("LLM_CACHING_DB", unset = "file-upload-cache.rds"),
  gcs_cx     = Sys.getenv("GCS_CX"),
  gcs_key    = Sys.getenv("GCS_APIKEY"),
  gcs_site   = Sys.getenv("GCS_SITE")
)

required_vars <- setdiff(names(config), c("cache_db"))
missing_vars <- required_vars[sapply(required_vars, function(x) config[[x]] == "")]

if (length(missing_vars) > 0) {
  stop(paste("Missing required environment variables:", paste(missing_vars, collapse = ", ")))
}

# Ensure caching DB path is absolute
Sys.setenv("llm_caching_db" = fs::path(getwd(), config$cache_db))

#' Get Available Models
#'
#' Fetches the list of available models from the specified provider.
#'
#' @param provider Character. "local" or "sspcloud".
#' @return Vector of model IDs.
get_models <- function(provider = "llm") {
  err <- try(res <- llm_request_default(
    endpoint = "models",
    body_data = NULL,
    provider = provider,
    method = "GET"
  ))
  if(!inherits(err,"try-error"))
    return(sort(res$data$id))
  return(NULL)
}

# Define available models manually to maintain specific order/curation
available_models <- list(
  "llm" = get_models(provider = "llm"),
  "gcs" = c("gemini-2.5-flash","gemini-3-pro-preview")
)
