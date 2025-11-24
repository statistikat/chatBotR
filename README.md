# chatBOTr - Open Source R Shiny Chatbot

A Retrieval-Augmented Generation (RAG) chatbot built with **R Shiny**. This application is a boilerplate implementation that may serve as an intelligent search assistant for specific websites (configurable via environment variables). It performs a Google Custom Search, downloads the results (HTML/PDF), feeds them into a Large Language Model (LLM), and provides strict, fact-based answers with citations. Alternatively, a variant that uses Google Gemini directly is also implemented.

## Key Features

* **RAG Pipeline:** Automatically searches, downloads, and processes context from a target website.
* **Strict Grounding:** The system prompt is engineered to answer *only* using the provided documents, minimizing hallucinations.
* **Bilingual Support:** Full support for **English** and **German**. The UI, system prompts, and LLM answers adapt to the selected language.
* **Multi-Provider Support:**
    * **LLM:** Compatible with any OpenAI-API compliant endpoint (e.g., Local Llama, vLLM, SSPCloud).
    * **Google Gemini:** Native support via the `ellmer` package.
* **Dynamic Geo-Restriction:** Automatically detects the target country based on the website TLD (e.g., `.at` -> Austria) to optimize search queries.


## Prerequisites

The application relies on environment variables for API keys and configuration. You can create an `.Renviron` file or define the variables directly.

### 1. Google Custom Search (Required)
You need a Google Programmable Search Engine (CSE) to fetch results.

* **API Key:** Get it from Google Cloud Console.
* **CX ID:** The Search Engine ID.
* **Site:** The domain you want the bot to search (e.g., `www.statistik.at`).

### 2. LLM Provider

* **Custom / Local:** An endpoint running an OpenAI-compatible API.
* **Google Gemini:** Requires the standard Google API Key.

---

## Configuration (.Renviron)

Create a file named `.Renviron` in the root of your project:

```bash
# --- LLM Endpoint (OpenAI Compatible) ---
# Used if provider is set to "Custom / Local"
LLM_BASE_URL="http://your-local-llm:8080/api/"
LLM_TOKEN="your-access-token"

# --- Google Services ---
# Required for Search AND for Gemini Model
GCS_APIKEY="your-google-api-key"
GCS_CX="your-custom-search-engine-id"

# --- App Configuration ---
# The website to search and analyze. 
# The bot derives geo-restrictions from the TLD (e.g., .at = Austria, .de = Germany)
GCS_SITE="www.statistik.at"

# Cache file path (for poor mans caching)
LLM_CACHING_DB="file-upload-cache.rds"
```

Note that you can also set the Environment-Variables directly, e.g. when you want to dockerize this setup or deploy in via Posit Connect.

---

## Installation & Usage

1.  Open the project in RStudio.
2.  Install dependencies:
    ```r
    install.packages(c("shiny", "shinyalert", "cli", "httr", "jsonlite", "digest", "bslib", "fs", "glue", "markdown", "ellmer"))
    ```
3.  Ensure `.Renviron` is present in the root.
4.  Run the app:
    ```r
    shiny::runApp()
    ```

---


## How it Works

1.  **Input:** User enters a query and selects a language (English/German).
2.  **Optimization:** An LLM rewrites the query for Google Search. It automatically adds site-specific or geo-specific restrictions based on the `GCS_SITE` environment variable (e.g., adding `(Austria OR AT)` if the site is `.at`).
3.  **Search:** Google Custom Search API returns top `N` results.
4.  **Ingestion:** The app downloads the content (HTML text or PDFs) from those URLs.
5.  **Context Construction:** A system prompt is generated containing:
    * Strict behavioral instructions in the selected language.
    * The content of the downloaded files.
    * Metadata for citations.
6.  **Generation:** The LLM is instructed to generate an answer using *only* the provided context, citing sources like `[1] {file.pdf}`.
