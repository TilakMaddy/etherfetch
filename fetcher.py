from dotenv import load_dotenv
import requests
import json
import os 

def fetch_source_code_response(address):
    load_dotenv()
    api_key = os.environ["ETHERSCAN_API_KEY"]
    url = f"https://api.etherscan.io/api?module=contract&action=getsourcecode&address={address}&apikey={api_key}"
    response = json.loads(requests.get(url).content)
    return response