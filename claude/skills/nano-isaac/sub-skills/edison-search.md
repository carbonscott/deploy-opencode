# Edison Literature Search

## When to Use

- User asks about mechanistic information not in the database
- You need literature context for a new surface or reaction
- Searching for experimental precedent or validation
- Looking up activation energies or binding energies not in our database

## What is Edison?

Edison Labs API is a scientific literature search service that:
- Searches scientific papers and databases
- Synthesizes answers from multiple sources
- Returns formatted summaries with citations

## Usage Modes

The skill supports three modes controlled by the config file at `$NANO_ISAAC_DATA_DIR/edison_config.json`:

| Mode | Behavior | Use Case |
|------|----------|----------|
| `live` | Always query Edison API | Production, real queries |
| `cache` | Use cached response if match, else query | Development with new queries |
| `default` | Always use default cached response | Fast development |

## Running Edison Searches

### Option 1: Using Python Script

```python
import os
from dotenv import load_dotenv
from edison_client import EdisonClient, JobNames

# Load .env file
load_dotenv()

# Get API key from environment
api_key = os.environ.get("EDISON_API_KEY")
if not api_key:
    raise ValueError("EDISON_API_KEY not set - check your .env file")

client = EdisonClient(api_key=api_key)

query = """I'm studying water chemistry on silver surfaces using AP-XPS.
I need to understand what O 1s binding energies are expected for different
adsorbed species (O*, OH*, H2O*, hydrogen-bonded complexes) and how the
surface speciation changes with temperature and water pressure."""

task_data = {"name": JobNames.LITERATURE, "query": query}

# This blocks until results are ready (~10 min)
results = client.run_tasks_until_done(task_data)

if results:
    answer = results[0].formatted_answer
    print(answer)
```

**Note:** Edison live queries require the `edison-client` package and an API key, which are not included in the shared deployment. This mode is available for users who have their own Edison credentials.

### Option 2: Using Cached Responses

For most use cases, use the cached responses:

```python
import json

cache_path = '/sdf/group/lcls/ds/dm/apps/dev/data/nano-isaac/edison_cache.json'
with open(cache_path) as f:
    cache = json.load(f)

# Use default cached response
response = cache.get("default", "No cached response available")

# Or check for exact query match
query = "your detailed query here..."
if query in cache.get("queries", {}):
    response = cache["queries"][query]
```

## Query Tips

Edison is an agentic system that understands natural language. Don't write terse keyword searches like you would for Google. Instead, write a paragraph that gives context about what you're looking for and why.

**Good query example:**

```
I'm studying water adsorption and dissociation on Ag(111) using ambient-pressure XPS.
I'm particularly interested in understanding what O 1s binding energies have been
reported in the literature for different oxygen-containing species (atomic oxygen,
hydroxyl, molecular water, hydrogen-bonded complexes) on this surface. I'd also like
to understand how the dominant surface species changes as a function of temperature
(room temperature to 500C) and water pressure (UHV to 1 torr).
```

**What to include in your query:**
- The surface and chemistry you're studying
- The experimental technique and spectral region
- What specific information you're looking for
- Why you need it (context helps Edison find relevant details)
- Any specific conditions or parameters of interest

## Current Cached Content

The default cached response covers:
- O 1s binding energies for water species on Ag(110)
- Temperature-dependent speciation (RT to 500C)
- Pressure effects on dominant species
- Experimental considerations (contamination, resolution)
- Suggested experimental strategy

## Gotchas

1. **API key required**: Edison live queries require `EDISON_API_KEY` environment variable
2. **Slow queries**: Live Edison queries take ~10 minutes
3. **Rate limits**: Don't spam the API; cache responses
4. **Query format**: Natural language works best; include key technical terms

## When to Go Live vs Use Cache

**Use cached:**
- Development and testing
- Demo scenarios
- Questions within cached query scope

**Go live:**
- New surface not in database
- New reaction not covered by existing data
- User explicitly asks for literature search
- Answering questions outside parameterized systems
