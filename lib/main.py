import uuid
import logging
from googleapiclient.discovery import build
import cohere
from flask import Flask, request, Response
import chromadb
from crawl4ai import *
import asyncio
import datetime
import google.generativeai as genai
import json
import re
from html import unescape
from google import genai
from google.genai.types import GenerateContentConfig, Part, Content
import os
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure logging
logging.basicConfig(level=logging.INFO)
crawler_config = CrawlerRunConfig(
    only_text=True,
    excluded_tags=["form", "header", "footer"],
    keep_data_attributes=False,
)

# Configuration Variables
GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY")
CSE_ID = os.getenv("CSE_ID")
CHROMA_PERSIST_DIRECTORY = os.getenv("CHROMA_PERSIST_DIRECTORY")
COLLECTION_NAME = os.getenv("COLLECTION_NAME")
COHERE_API_KEY = os.getenv("COHERE_API_KEY")
GEMINI_CONFIG = GenerateContentConfig(response_modalities=["TEXT"])

# Initialize Flask App
app = Flask(__name__)
# Initialize Google CSE and Gemini
service = build("customsearch", "v1", developerKey=GOOGLE_API_KEY)
client = genai.Client(api_key=os.getenv("GEMINI_API_KEY"))
model_id = os.getenv("GEMINI_MODEL_ID")

# Initialize ChromaDB
chroma_client = chromadb.PersistentClient(path=CHROMA_PERSIST_DIRECTORY)

# Try to get collection if it exists, or create it
try:
    collection = chroma_client.get_collection(name=COLLECTION_NAME)
    logging.info(f"Using existing collection: {COLLECTION_NAME}")
except Exception:
    collection = chroma_client.create_collection(
        name=COLLECTION_NAME, metadata={"description": "Emergency information database"}
    )
    logging.info(f"Created new collection: {COLLECTION_NAME}")

# Initialize Cohere client
co = cohere.Client(COHERE_API_KEY)


def log_exception(f):
    def wrapper(*args, **kwargs):
        try:
            return f(*args, **kwargs)
        except Exception as e:
            logging.error(f"An error occurred while performing {f.__name__}: {e}")
            raise

    return wrapper


@log_exception
def google_search(query):
    # Build the service
    urls = []
    for s in range(5):
        # Maximum of 10 results per request
        # Use start to specify the starting index which navigate to next 10 results
        response = (
            service.cse().list(q=query, cx=CSE_ID, num=10, start=10 * s + 1).execute()
        )
        items = response.get("items", [])
        urls.extend([item.get("link") for item in items])
    return urls


@log_exception
def filter_urls(urls):
    # Get all documents with their metadata
    results = collection.get(include=["metadatas"])

    # Create URL to ID mapping
    existing_urls = {url: None for url in urls}
    new_urls = []
    if results and "ids" in results and "metadatas" in results:
        for i, metadata in enumerate(results["metadatas"]):
            if metadata and "url" in metadata:
                existing_urls[metadata["url"]] = results["ids"][i]
    for url, id in existing_urls.items():
        if id is None:
            new_urls.append(url)
            logging.info(f"NEW URL:{url}")

    return new_urls


def clean_html(html_content):
    # Remove HTML tags
    text = re.sub(r"<[^>]+>", "", html_content)

    # Decode HTML entities
    text = unescape(text)

    # Replace escape sequences and actual newlines/tabs
    text = re.sub(r"\\[nt]", " ", text)
    text = re.sub(r"[\n\t\r]", " ", text)

    # Remove extra whitespace
    text = re.sub(r"\s+", " ", text).strip()

    return text


async def crawl_urls(urls):
    if not urls:
        return {}

    async with AsyncWebCrawler() as crawler:
        results = await crawler.arun_many(urls=urls, config=crawler_config)
    documents = {}
    for res in results:
        if res.success:
            print(res.url, "crawled OK!")
            documents[res.url] = clean_html(res.cleaned_html)
        else:
            print("Failed:", res.url, "-", res.error_message)
    return documents


def store_documents(docs):

    # Filter out docs that already exist
    # filtered_docs = filter_docs(docs)

    if not docs:
        logging.info("No new URLs to add.")
        return []

    # Prepare batch data
    ids = [str(uuid.uuid4()) for _ in range(len(docs))]

    # Since filtered_docs is a dict with URLs as keys and text as values
    texts = list(docs.values())
    urls = list(docs.keys())
    metadatas = [
        {"url": url, "timestamp": datetime.datetime.now().isoformat()} for url in urls
    ]

    # Add all documents in one batch
    collection.add(ids=ids, documents=texts, metadatas=metadatas)

    logging.info(f"Stored {len(docs)} new documents in batch.")
    return ids


def retrieve_and_rerank(db_query, rerank_query):
    docs = collection.query(query_texts=db_query, n_results=100)["documents"][0]
    reranked_docs = co.rerank(
        query=rerank_query,
        documents=docs,
        top_n=10,  # Make sure we don't request more than we have
        model="rerank-v3.5",
    )
    return reranked_docs


# Old API
# @app.route('/', methods=['POST'])
# def pipeline():
#     data = request.get_json()
#     user_query = data["query"]
#     message_history = data["chat_history"]
#     emergency_type = data["emergency_type"]

#     # print(user_query)
#     # print(message_history)
#     # print(emergency_type)

#     message_history = json.loads(message_history)
#     llm_chat_history = []
#     for message in message_history:
#         # llm_chat_history.append(Content(role=message["role"], parts=[Part.from_text(message["text"])]))
#         llm_chat_history.append({"role":message["role"], "parts":[message["text"]]})

#     chat = llm.start_chat(history=llm_chat_history)

#     pre_prompt = f"""User is in emegergency with type {emergency_type}. Considering the chat history and the current query: \"{user_query}\",
#     generate a concise keyword or phrase most relevant to the query and history for web searching
#     if you think it is necessary. If not, enter null value. Also, combine the user query and the
#     generated keyword or phrase to produce a most relevant query for the reranker to rank the searched documents,
#     if the search is needed. If not, enter null value.

#     The json should in {{"search_keyword":YOUR_KEYWORD_IN_STRING or null value, "reranker_query":YOUR_QUERY_FOR_RERANKER_IN_STRING or null value}} format.
#     """

#     response = chat.send_message(pre_prompt)
#     response_data = json.loads(response.text)
#     db_query = response_data["search_keyword"]
#     rerank_query = response_data["reranker_query"]
#     urls = google_search(db_query)
#     filtered_urls = filter_urls(urls)
#     docs = asyncio.run(crawl_urls(filtered_urls))
#     store_documents(docs)
#     docs = retrieve_and_rerank(db_query, rerank_query)
#     # Pop twice
#     # First popping the model refined query
#     # Second popping the pre-prompt
#     chat.history.pop()
#     chat.history.pop()
#     print(chat.history)


#     prompt = f"""You are an emergency AI assistant. Based on the following references and the user's query,
#             provide a helpful and informed response. Make your response natural and conversational,
#             avoid using markdown or emoji.

#             References:
#             {docs}

#             User Query: {user_query}

#             Previous conversation context should be considered when relevant.
#             You may refer to the references provided in your response, don't limit yourself to them,
#             you may also use your knowledge to provide a response.
#             The json should in {{"response":YOUR_RESPONSE}} format.
#             """
#     response = chat.send_message(prompt)
#     decoded_response = json.loads(response.text)["response"]

#     return Response(json.dumps({
#                 "response": decoded_response,
#             }, ensure_ascii=False),
#             status=200, mimetype='application/json')


def transcribe(media_bytes, media_type):
    instruction = """Transcribe the content of this media accurately.  
        - If this is an audio or video, generate a detailed and structured transcript.  
        - If this is an image, provide a rich and informative description of its contents.
        Ensure the transcription is **clear, precise, and useful for future reference** in assisting the user during an emergency.  
        Avoid markdown and emojis.
        """

    GEMINI_CONFIG.response_mime_type = None
    GEMINI_CONFIG.response_schema = None
    GEMINI_CONFIG.system_instruction = instruction
    response = client.models.generate_content(
        model=model_id,
        contents=[
            Content(
                role="user",
                parts=Part.from_bytes(data=media_bytes, mime_type=media_type),
            )
        ],
        config=GEMINI_CONFIG,
    )

    return response.text


@app.route("/", methods=["POST"])
def ai_pipeline():
    if request.mimetype == "application/json":
        data = request.get_json()
        print("Data:", data)
        media = None
    else:
        data = request.form
        media = request.files.get("audio", None)
        if media is None:
            media = request.files.get("video", None)
        if media is None:
            media = request.files.get("image", None)
    media_type = request.mimetype
    message_history = json.loads(data["chat_history"])
    query = data["query"]
    emergency_type = data["emergency_type"]

    contents = []
    for message in message_history:
        contents.append(
            Content(role=message["role"], parts=[{"text": message["text"]}])
        )
    print(contents)
    transcription = None
    if media is not None:
        # media.save(media.filename)
        # with open(media.filename, 'rb') as f:
        media_bytes = media.read()
        contents.append(
            Content(
                role="user",
                parts=Part.from_bytes(data=media_bytes, mime_type=media_type),
            )
        )
        transcription = transcribe(media_bytes, media_type)

    pre_instruction = f"""
        A user is in an emergency ({emergency_type}). Based on the chat history, the user's current media (audio/image/video/None), and their query: "{query}",  
        1. Generate a concise keyword or phrase most relevant to the situation for web search. If unnecessary, return "null".  
        2. Combine the user's query and the generated keyword/phrase to form an optimized query for reranking search results. If unnecessary, return "null".
        """

    GEMINI_CONFIG.response_mime_type = "application/json"
    GEMINI_CONFIG.response_schema = GEMINI_CONFIG.response_schema = {
        "type": "OBJECT",
        "properties": {
            "search_keyword": {
                "type": "STRING",
                "description": "Search keyword string or null value",
            },
            "reranker_query": {
                "type": "STRING",
                "description": "Query for reranker string or null value",
            },
        },
    }
    GEMINI_CONFIG.system_instruction = pre_instruction

    response = client.models.generate_content(
        model=model_id, contents=contents, config=GEMINI_CONFIG
    )

    # # Retrieve and Rerank
    # response_data = json.loads(response.text)
    # db_query = response_data["search_keyword"]
    # rerank_query = response_data["reranker_query"]
    # urls = google_search(db_query)
    # filtered_urls = filter_urls(urls)
    # docs = asyncio.run(crawl_urls(filtered_urls))
    # store_documents(docs)
    # docs = retrieve_and_rerank(db_query, rerank_query)
    docs = None

    post_instruction = f"""
        You are an emergency AI assistant. Given the references below and the user's current media (audio/image/video/None), their query: "{query}" and emergency type: "{emergency_type}", 
        provide a natural and conversational response. Avoid markdown and emojis.
        References:  
        # {docs}  
        Consider previous conversation context when relevant. Use both the provided references and your own knowledge to generate a helpful response.
        """

    GEMINI_CONFIG.response_mime_type = None
    GEMINI_CONFIG.response_schema = None
    GEMINI_CONFIG.system_instruction = post_instruction

    response = client.models.generate_content(
        model=model_id, contents=contents, config=GEMINI_CONFIG
    )

    return Response(
        json.dumps(
            {
                "response": response.text,
                "transcription": transcription,
            },
            ensure_ascii=False,
        ),
        status=200,
        mimetype="application/json",
    )


# @app.route('/', methods=['POST'])
# def pipeline():
#     data = request.get_json()
#     user_query = data["query"]
#     message_history = json.loads(data["chat_history"])
#     emergency_type = data["emergency_type"]

#     # Migrate to another API which does not support chat history internally
#     # llm_chat_history = []
#     # for message in message_history:
#         # llm_chat_history.append(Content(role=message["role"], parts=[Part.from_text(message["text"])]))
#         # llm_chat_history.append({"role":message["role"], "parts":[message["text"]]})

#     # chat = llm.start_chat(history=llm_chat_history)

#     contents = []
#     for message in message_history:
#         contents.append(Content(role=message["role"], parts=message["text"]))


#     instruction = f"""
#     A user is in an emergency ({emergency_type}). Based on the chat history, the user's query: "{user_query}",
#     1. Generate a concise keyword or phrase most relevant to the situation for web search. If unnecessary, return "null".
#     2. Combine the user's query and the generated keyword/phrase to form an optimized query for reranking search results. If unnecessary, return "null".
#     """

#     GEMINI_CONFIG.response_mime_type = "application/json"
#     GEMINI_CONFIG.response_schema =  {"search_keyword":"YOUR_KEYWORD_IN_STRING or null value", "reranker_query":"YOUR_QUERY_FOR_RERANKER_IN_STRING or null value"}
#     GEMINI_CONFIG.system_instruction = instruction

#     response = client.models.generate_content(
#         model=model_id,
#         contents=contents,
#         config=GEMINI_CONFIG
#     )

#     response_data = json.loads(response.text)
#     db_query = response_data["search_keyword"]
#     rerank_query = response_data["reranker_query"]
#     urls = google_search(db_query)
#     filtered_urls = filter_urls(urls)
#     docs = asyncio.run(crawl_urls(filtered_urls))
#     store_documents(docs)
#     docs = retrieve_and_rerank(db_query, rerank_query)
#     # Pop twice
#     # First popping the model refined query
#     # Second popping the pre-prompt
#     # chat.history.pop()
#     # chat.history.pop()
#     # print(chat.history)


#     instruction = f"""
#         You are an emergency AI assistant. Given the references below and the user's query,
#         provide a natural and conversational response. Avoid markdown and emojis.
#         References:
#         {docs}
#         User Query: "{user_query}"
#         Consider previous conversation context when relevant. Use both the provided references and your own knowledge to generate a helpful response.
#         """
#     GEMINI_CONFIG.response_mime_type = None
#     GEMINI_CONFIG.response_schema = None
#     GEMINI_CONFIG.system_instruction = instruction


#     response = client.models.generate_content(
#         model=model_id,
#         contents=contents,
#         config=GEMINI_CONFIG
#     )
#     return Response(json.dumps({
#                 "response": response.text,
#             }, ensure_ascii=False),
#             status=200, mimetype='application/json')

# @app.route('/audio', methods=["POST"])
# def audio_pipeline():
#     form_data = request.form
#     message_history = json.loads(form_data["chat_history"])
#     emergency_type = form_data["emergency_type"]
#     audio = request.files.get('audio')
#     audio.save(audio.filename)

#     contents = []
#     for message in message_history:
#         contents.append(Content(role=message["role"], parts=message["text"]))


#     instruction = f"""
#     A user is in an emergency ({emergency_type}). Based on the chat history, the user's audio query,
#     1. Generate a concise keyword or phrase most relevant to the situation for web search. If unnecessary, return "null".
#     2. Combine the user's query and the generated keyword/phrase to form an optimized query for reranking search results. If unnecessary, return "null".
#     """

#     GEMINI_CONFIG.response_mime_type = "application/json"
#     GEMINI_CONFIG.response_schema =  {"search_keyword":"YOUR_KEYWORD_IN_STRING or null value", "reranker_query":"YOUR_QUERY_FOR_RERANKER_IN_STRING or null value"}
#     GEMINI_CONFIG.system_instruction = instruction

#     with open(audio.filename, 'rb') as f:
#         audio_bytes = f.read()
#     contents.append(Content(role="user", parts=Part.from_bytes(data=audio_bytes, mime_type="audio/aac")))

#     response = client.models.generate_content(
#         model=model_id,
#         contents=contents,
#         config=GEMINI_CONFIG
#     )
#     response_data = json.loads(response.text)

#     db_query = response_data["search_keyword"]
#     rerank_query = response_data["reranker_query"]
#     urls = google_search(db_query)
#     filtered_urls = filter_urls(urls)
#     docs = asyncio.run(crawl_urls(filtered_urls))
#     store_documents(docs)
#     docs = retrieve_and_rerank(db_query, rerank_query)

#     instruction = f"""
#         You are an emergency AI assistant. Given the references below and the user's audio,
#         provide a natural and conversational response. Avoid markdown and emojis.
#         References:
#         {docs}
#         Consider previous conversation context when relevant. Use both the provided references and your own knowledge to generate a helpful response.
#         """

#     GEMINI_CONFIG.response_mime_type = None
#     GEMINI_CONFIG.response_schema = None
#     GEMINI_CONFIG.system_instruction = instruction

#     response = client.models.generate_content(
#         model=model_id,
#         contents=contents,
#         config=GEMINI_CONFIG
#     )

#     return Response(json.dumps({
#                 "response": response.text,
#             }, ensure_ascii=False),
#             status=200, mimetype='application/json')

# @app.route('/media', methods=["POST"])
# def media_pipeline():
#     form_data = request.form
#     message_history = json.loads(form_data["chat_history"])
#     emergency_type = form_data["emergency_type"]
#     query = form_data["query"]
#     media = request.files.get('video', None)
#     if media is None:
#         media = request.files.get('image')

#     media.save(media.filename)

#     contents = []
#     for message in message_history:
#         contents.append(Content(role=message["role"], parts=message["text"]))


#     instruction = f"""
#     A user is in an emergency ({emergency_type}). Based on the chat history, the user's media (image/video), and their query: "{query}",
#     1. Generate a concise keyword or phrase most relevant to the situation for web search. If unnecessary, return "null".
#     2. Combine the user's query and the generated keyword/phrase to form an optimized query for reranking search results. If unnecessary, return "null".
#     """


#     GEMINI_CONFIG.response_mime_type = "application/json"
#     GEMINI_CONFIG.response_schema =  {"search_keyword":"YOUR_KEYWORD_IN_STRING or null value", "reranker_query":"YOUR_QUERY_FOR_RERANKER_IN_STRING or null value"}
#     GEMINI_CONFIG.system_instruction = instruction

#     with open(media.filename, 'rb') as f:
#         media_bytes = f.read()
#     contents.append(Content(role="user", parts=Part.from_bytes(data=media_bytes, mime_type="audio/aac")))

#     response = client.models.generate_content(
#         model=model_id,
#         contents=contents,
#         config=GEMINI_CONFIG
#     )
#     response_data = json.loads(response.text)
#     db_query = response_data["search_keyword"]
#     rerank_query = response_data["reranker_query"]
#     urls = google_search(db_query)
#     filtered_urls = filter_urls(urls)
#     docs = asyncio.run(crawl_urls(filtered_urls))
#     store_documents(docs)
#     docs = retrieve_and_rerank(db_query, rerank_query)

#     instruction = f"""
#         You are an emergency AI assistant. Given the references below and the user's query,
#         provide a natural and conversational response. Avoid markdown and emojis.
#         References:
#         {docs}
#         User Query: "{query}"
#         Consider previous conversation context when relevant. Use both the provided references and your own knowledge to generate a helpful response.
#         """

#     GEMINI_CONFIG.response_mime_type = None
#     GEMINI_CONFIG.response_schema = None
#     GEMINI_CONFIG.system_instruction = instruction

#     response = client.models.generate_content(
#         model=model_id,
#         contents=contents,
#         config=GEMINI_CONFIG
#     )

#     return Response(json.dumps({
#                 "response": response.text,
#             }, ensure_ascii=False),
#             status=200, mimetype='application/json')

if __name__ == "__main__":
    app.run(host="0.0.0.0", debug=True)
