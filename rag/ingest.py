import os 
from dotenv import load_dotenv
import pdfplumber
from langchain_classic.schema import Document
from langchain_community.vectorstores import FAISS 
from langchain_google_genai import GoogleGenerativeAIEmbeddings
from langchain_text_splitters import RecursiveCharacterTextSplitter

load_dotenv()

RAG_DIR = os.path.dirname(os.path.abspath(__file__))
PDF_PATH = os.path.join(RAG_DIR, "policy.pdf")
FAISS_INDEX_PATH = os.path.join(RAG_DIR, "faiss_index")
GEMINI_API_KEY = os.environ.get("GEMINI_API_KEY", "")

def _table_row_to_sentence(headers, row, page_num):
    """Convert a table row into a natural language sentence."""
    parts = []
    for h, v in zip(headers, row):
        if h and v:
            parts.append(f"{h.strip()}: {v.strip()}")
    return " | ".join(parts) if parts else None


def _extract_from_pdf(pdf_path):
    """Extract text and tables from all pages of the PDF."""
    documents = []

    with pdfplumber.open(pdf_path) as pdf:
        for i, page in enumerate(pdf.pages):
            page_num = i + 1

            # extract tables
            tables = page.extract_tables()
            table_texts = []

            for table in tables:
                if not table or len(table) < 2:
                    continue
                headers = table[0]
                for row in table[1:]:
                    sentence = _table_row_to_sentence(headers, row, page_num)
                    if sentence:
                        table_texts.append(sentence)

            if table_texts:
                combined_table = "\n".join(table_texts)
                documents.append(Document(
                    page_content=combined_table,
                    metadata={"source": "table", "page": page_num}
                ))

            # extract regular text
            text = page.extract_text()
            if text and text.strip():
                documents.append(Document(
                    page_content=text.strip(),
                    metadata={"source": "text", "page": page_num}
                ))

    return documents

def _chunk_documents(documents):
    """Split documents into smaller chunks."""
    table_docs = [d for d in documents if d.metadata["source"]== "table"]
    text_docs = [d for d in documents if d.metadata["source"] == "text"]

    splitter = RecursiveCharacterTextSplitter(
        chunk_size = 600, 
        chunk_overlap = 80, 
        separators=["\n\n", "\n", ". ", " "],

    )

    text_chunks = splitter.split_documents(text_docs)

    table_chunks = []
    for doc in table_docs:
        rows = doc.page_content.split("\n")
        for row in rows:
            if row.strip():
                table_chunks.append(Document(
                    page_content=row.strip(),
                    metadata=doc.metadata.copy()
                ))

    return text_chunks + table_chunks


def build_index():
    """Main function: extract, chunk, embed, save FAISS index."""
    print("Extracting text and tables from PDF...")
    documents = _extract_from_pdf(PDF_PATH)
    print(f"  Extracted {len(documents)} raw documents")

    print("Chunking documents...")
    chunks = _chunk_documents(documents)
    print(f"  Created {len(chunks)} chunks")

    print("Embedding and building FAISS index...")
    embeddings = GoogleGenerativeAIEmbeddings(
        model="models/gemini-embedding-001",
        google_api_key=GEMINI_API_KEY,
    )
    vectorstore = FAISS.from_documents(chunks, embeddings)
    vectorstore.save_local(FAISS_INDEX_PATH)
    print(f"  Saved FAISS index to {FAISS_INDEX_PATH}")

    return vectorstore


def load_index():
    """Load existing FAISS index from disk."""
    embeddings = GoogleGenerativeAIEmbeddings(
        model="models/gemini-embedding-001",
        google_api_key=GEMINI_API_KEY,
    )
    return FAISS.load_local(
        FAISS_INDEX_PATH,
        embeddings,
        allow_dangerous_deserialization=True,
    )


if __name__ == "__main__":
    if not GEMINI_API_KEY:
        print("Set GOOGLE_API_KEY in your .env file")
    else:
        build_index()

