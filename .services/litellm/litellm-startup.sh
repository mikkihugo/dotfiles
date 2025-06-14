#!/bin/bash
# Dynamic LiteLLM startup with provider discovery

echo "🔍 Discovering available AI providers..."

# Build dynamic config based on available API keys
CONFIG="/app/config/dynamic-config.yaml"
cp /app/config/litellm_config.yaml $CONFIG

# Check and add providers dynamically

if [ -n "$GOOGLE_API_KEY" ] || [ -n "$GOOGLE_AI_API_KEY" ]; then
    echo "✅ Google AI available - fetching models..."
    
    # Use whichever key is available
    GKEY="${GOOGLE_API_KEY:-$GOOGLE_AI_API_KEY}"
    
    # Try to list available models from Google AI
    GOOGLE_MODELS=$(curl -s "https://generativelanguage.googleapis.com/v1beta/models" \
        -H "x-goog-api-key: $GKEY" 2>/dev/null || echo '{}')
    
    echo "$GOOGLE_MODELS" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    models = data.get('models', [])
    
    if models:
        for model in models:
            model_name = model.get('name', '').replace('models/', '')
            if model_name and 'gemini' in model_name.lower():
                print(f'  - model_name: google/{model_name}')
                print(f'    litellm_params:')
                print(f'      model: {model_name}')
                print(f'      api_key: os.environ/GOOGLE_API_KEY')
                print()
        print(f'# Found {len(models)} Google models', file=sys.stderr)
    else:
        # Fallback to known models
        print('  - model_name: google/gemini-1.5-flash')
        print('    litellm_params:')
        print('      model: gemini/gemini-1.5-flash')
        print('      api_key: os.environ/GOOGLE_API_KEY')
        print()
        print('  - model_name: google/gemini-2.0-flash')
        print('    litellm_params:')
        print('      model: gemini/gemini-2.0-flash')
        print('      api_key: os.environ/GOOGLE_API_KEY')
        print()
        print('  - model_name: google/gemini-1.5-flash-8b')
        print('    litellm_params:')
        print('      model: gemini/gemini-1.5-flash-8b')
        print('      api_key: os.environ/GOOGLE_API_KEY')
        print()
except Exception as e:
    print(f'# Error parsing Google models: {e}', file=sys.stderr)
" >> $CONFIG 2>&1
fi

if [ -n "$OPENROUTER_API_KEY" ]; then
    echo "✅ OpenRouter available - fetching free models..."
    
    # Query OpenRouter for available models
    MODELS_JSON=$(curl -s https://openrouter.ai/api/v1/models \
        -H "Authorization: Bearer $OPENROUTER_API_KEY" \
        -H "Content-Type: application/json")
    
    # Extract only free models and add to config
    echo "$MODELS_JSON" | python3 -c "
import json
import sys

data = json.load(sys.stdin)
free_models = []

for model in data.get('data', []):
    model_id = model.get('id', '')
    # Only include models with :free suffix
    if ':free' in model_id:
        free_models.append(model)
        print(f'  - model_name: openrouter/{model_id.replace(\":\", \"-\").replace(\"/\", \"-\")}')
        print(f'    litellm_params:')
        print(f'      model: {model_id}')
        print(f'      api_key: os.environ/OPENROUTER_API_KEY')
        print(f'      api_base: https://openrouter.ai/api/v1')
        print()

print(f'# Found {len(free_models)} free models', file=sys.stderr)
" >> $CONFIG 2>&1
fi

if [ -n "$GROQ_API_KEY" ]; then
    echo "✅ Groq available (fast inference)"
fi

if [ -n "$GITHUB_TOKEN" ]; then
    echo "✅ GitHub Models available - fetching model list..."
    
    # GitHub Models catalog endpoint (works without auth too)
    GITHUB_MODELS=$(curl -s https://models.github.ai/catalog/models)
    
    # Parse and add models
    echo "$GITHUB_MODELS" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    # GitHub Models returns a list directly
    models = data if isinstance(data, list) else data.get('data', [])
    
    added_count = 0
    for model in models:
        if isinstance(model, dict):
            model_id = model.get('id', '')
            model_name = model.get('name', '')
            if model_id:
                # Clean up model ID for LiteLLM
                clean_id = model_id.replace('/', '-')
                print(f'  - model_name: github/{clean_id}')
                print(f'    litellm_params:')
                print(f'      model: {model_id}')
                print(f'      api_key: os.environ/GITHUB_TOKEN')
                print(f'      api_base: https://models.inference.ai.azure.com')
                print(f'      custom_llm_provider: azure')
                print()
                added_count += 1
    
    print(f'# Found {added_count} popular GitHub models (of {len(models)} total)', file=sys.stderr)
except Exception as e:
    print(f'# Error parsing GitHub models: {e}', file=sys.stderr)
" >> $CONFIG 2>&1
fi

if [ -n "$GITHUB_TOKEN" ]; then
    echo "✅ GitHub Copilot Catalog available - fetching models..."
    
    # GitHub AI catalog endpoint (different from GitHub Models)
    COPILOT_CATALOG=$(curl -s https://models.github.ai/catalog/models)
    
    # Parse and add models
    echo "$COPILOT_CATALOG" | python3 -c "
import json
import sys

try:
    data = json.load(sys.stdin)
    models = data if isinstance(data, list) else data.get('data', [])
    
    added_count = 0
    for model in models:
        if isinstance(model, dict):
            model_id = model.get('id', '')
            # Only add OpenAI and Meta models for now (most compatible)
            if model_id and (model_id.startswith('openai/') or model_id.startswith('meta/')):
                clean_id = model_id.replace('/', '-')
                print(f'  - model_name: copilot/{clean_id}')
                print(f'    litellm_params:')
                print(f'      model: {model_id}')
                print(f'      api_key: os.environ/GITHUB_TOKEN')
                print(f'      api_base: https://api.individual.githubcopilot.com')
                print(f'      custom_llm_provider: openai')
                print()
                added_count += 1
    
    print(f'# Found {added_count} Copilot models (from {len(models)} total)', file=sys.stderr)
except Exception as e:
    print(f'# Error parsing Copilot catalog: {e}', file=sys.stderr)
" >> $CONFIG 2>&1
fi


# Start LiteLLM with dynamic config
echo "🚀 Starting LiteLLM with discovered providers..."
exec litellm --config $CONFIG --host 0.0.0.0 --port 4000 --detailed_debug