#' Extract Answer from LLM Response
#'
#' Safely retrieves the content string from the nested JSON response object.
#'
#' @param x List. The API response object.
#' @return Character string (the answer) or NULL if failed.
llm_extract_answer <- function(x) {
  tryCatch(
    expr = x$choices$message$content,
    error = function(e) NULL
  )
}