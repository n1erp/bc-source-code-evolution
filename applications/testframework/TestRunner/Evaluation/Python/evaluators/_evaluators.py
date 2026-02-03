# ---------------------------------------------------------
# Copyright (c) Microsoft Corporation. All rights reserved.
# ---------------------------------------------------------

import os

from promptflow.client import load_flow
from promptflow.core import AzureOpenAIModelConfiguration

class BCEvaluator:
    def __init__(
            self,
            model_config: AzureOpenAIModelConfiguration,
            prompty_path: str,
            metric_name: str):
        """
        Initialize an evaluator configured for a specific Azure OpenAI model.

        (Note that we don't inherit from PromptyEvaluatorBase because
         that only allows for a score and not reason as output.)

        :param model_config: Configuration for the Azure OpenAI model.
        :type model_config: AzureOpenAIModelConfiguration
        :param prompty_path: Path to the Prompty file of the evaluator.
        :type prompty_path: str
        :param metric_name: Name of the metric to be evaluated.
        :type metric_name: str
        """
        prompty_model_config = {"configuration": model_config}
        current_dir = os.path.dirname(__file__)
        prompty_path = os.path.join(current_dir, prompty_path)
        self._flow = load_flow(source=prompty_path, model=prompty_model_config)
        self._metric_name = metric_name

    def __call__(self, **kwargs):
        print(str(kwargs))
        result = self._flow(**kwargs)
        return {f"{self._metric_name}_score": result["score"], f"{self._metric_name}_reason": result["reason"]}

class CopyrightEvaluator(BCEvaluator):
    def __init__(self, model_config: AzureOpenAIModelConfiguration):
        super().__init__(model_config, "copyright.prompty", "bc_copyright")

    def __call__(self, *, query: str, response: str, **kwargs):
        return super().__call__(question=query, answer=response, **kwargs)

class IncitingHarmfulActionsEvaluator(BCEvaluator):
    def __init__(self, model_config: AzureOpenAIModelConfiguration):
        super().__init__(model_config, "inciting_harmful_actions.prompty", "bc_inciting_harmful_actions")

    def __call__(self, *, query: str, response: str, **kwargs):
        return super().__call__(question=query, answer=response, **kwargs)
<<<<<<< HEAD

class XPIAWithItemContextEvaluator(BCEvaluator):
    def __init__(self, model_config: AzureOpenAIModelConfiguration):
        super().__init__(model_config, "xpia_item.prompty", "bc_xpia_with_item_context")

    def __call__(self, *, query: str, response: str, context: str, **kwargs):
        return super().__call__(question=query, answer=response, context=context, **kwargs)
=======
>>>>>>> 4e338bd488fa47b3061e71a29e528dd727f0a574
