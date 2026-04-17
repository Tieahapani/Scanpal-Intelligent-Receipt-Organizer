def get_relevant_chunks(vectorstore, query, k=4, lambda_mult=0.7):  ### Getting the relevant chunks 
    """
    Retrieve relevant chunks using MMR (Maximal Marginal Relevance).
    
    lambda_mult: 0 = max diversity, 1 = max relevance
    0.7 = favors relevance but avoids redundant chunks
    """
    docs = vectorstore.max_marginal_relevance_search(
        query,
        k=k,
        fetch_k=12,
        lambda_mult=lambda_mult,
    )
    return docs
 
### Formatting context that gemini can read through it 
def format_context(docs):
    """Format retrieved docs into a context string for the LLM."""
    context_parts = []
    for i, doc in enumerate(docs, 1):
        source = doc.metadata.get("source", "unknown")
        page = doc.metadata.get("page", "?")
        context_parts.append(
            f"[Source {i} - Page {page} ({source})]\n{doc.page_content}"
        )
    return "\n\n---\n\n".join(context_parts)