# ---------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ---------------------------------------------------------

from datetime import datetime
import os
import re

from azure.ai.evaluation import AzureOpenAIModelConfiguration, AzureAIProject

def handle_json_serialization(o: any) -> any:
    """
    Handle datetime values in JSON serialization.

    Args:
        o: Object.

    Returns:
        any: Object without datetimes values.
    """
    if isinstance(o, datetime):
        return o.isoformat()
    raise TypeError

def get_azure_ai_project():
    return AzureAIProject(
        subscription_id = os.getenv("AZURE_AI_SUBSCRIPTION_ID"),
        resource_group_name = os.getenv("AZURE_AI_RESOURCE_GROUP"),
        project_name = os.getenv("AZURE_AI_PROJECT"))

def get_model_config():
    return AzureOpenAIModelConfiguration(
        azure_endpoint = os.getenv("AZURE_AI_ENDPOINT"),
        azure_deployment = os.getenv("AZURE_OPENAI_DEPLOYMENT") or "gpt-4o-allowall",
        api_version= os.getenv("OPENAI_API_VERSION") or "2024-08-01-preview"
    )

def sanitize_language_file(language):
    """Sanitize language parameter and return safe file path for datasets."""
    # Validate language parameter to prevent path traversal attacks
    if not re.match(r'^[a-zA-Z]{2,3}$', language):
        language = "en"  # Default to English for invalid language codes
    
    # Construct the expected file path
    datasets_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "datasets")
    language_file = os.path.join(datasets_dir, f"{language}.csv")
    
    # Normalize the path to resolve any relative path components
    normalized_path = os.path.normpath(language_file)

    # Ensure the normalized path is still within the datasets directory
    if not normalized_path.startswith(os.path.normpath(datasets_dir)):
        raise Exception("File path not allowed - outside datasets directory")
    
    return normalized_path