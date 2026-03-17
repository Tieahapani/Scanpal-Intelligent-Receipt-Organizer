import os 
from dotenv import load_dotenv
from langchain_google_genai import ChatGoogleGenerativeAI
from langchain_core.prompts import ChatPromptTemplate
from langchain_core.output_parsers import StrOutputParser
from .retriever import get_relevant_chunks, format_context

load_dotenv()

GEMINIT_API_KEY = os.environ.get("GEMINI_API_KEY", "")

SYSTEM_PROMPT = """You are a helpful travel policy assistant for Associated Students (AS) 
at San Francisco State University. You answer questions about the AS Travel Policy in a 
friendly, conversational tone.

Rules:
- Only answer based on the provided policy context. If the answer isn't in the context, 
  say you're not sure and suggest they check with the AS Business Administration office.
- When citing specific numbers (rates, deadlines, limits), be precise.
- Keep answers concise but complete.
- If the user asks about their specific trip, use the trip context provided.
- Do not make up policy rules that aren't in the context.

Policy Context:
{context}

{trip_context}"""

prompt = ChatPromptTemplate.from_messages([
    ("system", SYSTEM_PROMPT),
    ("human", "{greeting}User question: {question}"),
])

llm = ChatGoogleGenerativeAI(
    model="gemini-2.0-flash",
    google_api_key=GEMINIT_API_KEY, 
)

chain = prompt | llm | StrOutputParser()

def ask(question, vectorstore, user_name=None, trip_data=None):
    """
    Answer a travel policy question using RAG.
    """
    docs = get_relevant_chunks(vectorstore, question)
    context = format_context(docs)

    trip_context = ""
    if trip_data:
        trip_lines = []
        for t in trip_data:
            trip_lines.append(
                f"- {t.get('trip_purpose', 'Trip')}: "
                f"{t.get('destination', 'N/A')}, "
                f"{t.get('departure_date', '?')} to {t.get('return_date', '?')}, "
                f"status: {t.get('status', 'unknown')}"
            )
        trip_context = "The user's current trips:\n" + "\n".join(trip_lines)

    greeting = f"The user's name is {user_name}. " if user_name else ""

    answer = chain.invoke({
        "context": context,
        "trip_context": trip_context,
        "greeting": greeting,
        "question": question,
    })

    return answer
