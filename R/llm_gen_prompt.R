#' Generate System Prompt
#'
#' Dynamically creates the system prompt instructions based on uploaded files
#' and the selected language.
#'
#' @param files List/Dataframe. Information about uploaded files.
#' @param meta List. Metadata from Google Search results.
#' @param provider Character.
#' @param lang Character. "en" (English) or "de" (German).
#' @return formatted string containing the system prompt.
llm_gen_prompt <- function(files, meta, provider, lang = "en") {
  # --- Template Definitions ---
  templates <- list(
    de = list(
      intro = "Du bist ein präziser Such- und Analyseassistent für Inhalte der Webseite von {site}.",
      task = "Deine Aufgabe ist es, Fragen ausschließlich auf Basis der bereitgestellten {{DocumentType}} sachlich und objektiv zu beantworten.",
      lang_instruction = "### WICHTIG: Antworte ausschließlich auf DEUTSCH.",
      rules_header = "### Verhaltensregeln",
      rules_content = "- Beantworte **nur** sachliche Fragen mit Bezug zu den übergebenen Dokumenten.\n- Lehne Fragen ab, die persönlich, hypothetisch oder beleidigend sind.",
      refusal_msg = "Ich beantworte nur objektive, sachliche Fragen basierend auf Information der bereitgestellten Webseite.",
      strict_header = "### Strenge Regeln zur Inhaltsermittlung",
      strict_content = "- **Keine Ergänzungen durch Allgemeinwissen oder Internetrecherche.**\n- Nutze ausschließlich die bereitgestellten Dateien.",
      no_info_msg = "Dazu finde ich keine Information in den bereitgestellten Quellen.",
      citation_header = "### Quellen- und Zitatangabe (wichtig!)",
      citation_instr = "- Zitate müssen direkt belegbar sein.\n- Füge am Ende eine Quellenliste an:",
      files_header = "### Dateireferenzen",
      files_intro = "Hier die Metadaten der hochgeladenen Dateien:"
    ),
    en = list(
      intro = "You are a precise search and analysis assistant for the website {site}.",
      task = "Your task is to answer questions factually and objectively based solely on the provided {{DocumentType}}.",
      lang_instruction = "### IMPORTANT: Answer exclusively in ENGLISH.",
      rules_header = "### Behavioral Rules",
      rules_content = "- Answer **only** factual questions related to the provided documents.\n- Decline questions that are personal, hypothetical, or offensive.",
      refusal_msg = "I only answer objective, factual questions based on the information from the provided website.",
      strict_header = "### Strict Content Rules",
      strict_content = "- **Do not use general knowledge or internet search.**\n- Use only the provided files.",
      no_info_msg = "I cannot find information regarding this in the provided sources.",
      citation_header = "### Sources and Citations (Important!)",
      citation_instr = "- Citations must be directly verifiable.\n- Append a list of sources at the end:",
      files_header = "### File References",
      files_intro = "Here are the metadata of the uploaded files:"
    )
  )
  
  # Select template
  t <- templates[[lang]]
  if (is.null(t)) {
    t <- templates[["en"]] # Fallback
  }
  
  # Inject the configured site into the intro
  t$intro <- glue::glue(t$intro, site = Sys.getenv("GCS_SITE"))
  
  # Construct the Prompt String
  s <- '
    {{t$intro}}
    {{t$task}}
    
    {{t$lang_instruction}}
    
    ---
    
    {{t$rules_header}}
    {{t$rules_content}}
    - If a question is invalid, answer:
      > "{{t$refusal_msg}}"
    
    ---
    
    {{t$strict_header}}
    {{t$strict_content}}
    - If no information is found, answer:
      > "{{t$no_info_msg}}"
    
    ---
    
    ### Analysis Approach
    - Derive keywords from the user question to search the file content.
    - Use **only links and content** contained in the provided files.
    - Quote text literally where possible.
    
    ---
    
    {{t$citation_header}}
    {{t$citation_instr}}
    
    #### Format:
    ```markdown
    Sources:
    - [1] [Filename](Link)
    - [2] [Filename](Link)
    ...
    ```
    
    {{t$files_header}}
    
    {{Dateireferenz}}
    
    {{ file_info }}
    
    Begin directly with your answer.'

  if (provider != "gcs") { 
    DocumentType <- "Dateien (z. B. PDFs, HTML)" 
    Dateireferenz <- "Hier die Metadaten der hochgeladenen Dateien:"
    
    # Extract IDs and Names safely
    file_ids <- sapply(files, function(x) x$id)
    file_names <- sapply(files, function(x) x$filename)
    
    # Create JSON representation of available context
    file_info_df <- data.frame(
      id = file_ids,
      file_name = file_names,
      link = sapply(meta, function(x) x$link)
    )
    file_info <- paste0("```json\n", jsonlite::toJSON(file_info_df, pretty = TRUE), "\n```")
  } else { 
    DocumentType <- "URLs" 
    Dateireferenz <- ifelse(lang == "de", "Liste der URLs:", "List of URLs:")
    file_info <- paste(files, collapse = "\n") 
  }
  
  return(glue::glue(s, .open = "{{", .close = "}}"))
}
