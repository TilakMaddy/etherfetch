from pathlib import Path

import fetcher
import json

import typer

def assemble_files_from_json(code: str, address: str):
    result = json.loads(code[1:-1])
    for filename, content in result["sources"].items():
        p = Path(f"downloads") / Path(f"{address}/{filename}")
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content["content"])
    r = Path(f"downloads") / Path(f"{address}/remappings")
    r.write_text("\n".join(result["settings"]["remappings"]))

def assemble_file(code: str, address: str):
    out_path = Path("downloads") / Path(f"{address}") / Path(f"contract.sol")
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(code)

def main(address: str):
    response = fetcher.fetch_source_code_response(address)
    apparent_source_code = response["result"][0]["SourceCode"]
    
    # Now we need to detect the format.(Solidity or Solidity input JSON)
    source_code_format = "JSON" if apparent_source_code[0] == "{" and apparent_source_code[-1] == "}" else "SOL"

    if source_code_format == "JSON":
        assemble_files_from_json(apparent_source_code, address)    
    else:
        assemble_file(apparent_source_code, address)

    print(f"Contracts written to downloads/{address}")
    

if __name__ == "__main__":
    typer.run(main)