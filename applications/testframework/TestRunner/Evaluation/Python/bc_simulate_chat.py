from azure.ai.evaluation.simulator import AdversarialSimulator, DirectAttackSimulator, IndirectAttackSimulator
from azure.ai.evaluation.simulator import AdversarialScenario
from typing import Any
from azure.identity import DefaultAzureCredential
from enum import Enum
import asyncio
import json
import argparse
import bc_client_bot
import datetime

simulator_dict = {
    "ADVERSARIAL": AdversarialSimulator,
    "JAILBREAK_DIRECT": DirectAttackSimulator,
    "JAILBREAK_INDIRECT": IndirectAttackSimulator
}

def save_to_jsonl(data, output_file, message: str = 'Saving outputs to '):
    if output_file == '':
        output_file = 'outputs-' + datetime.datetime.now().strftime("%d%m%Y-%H%M%S") + '.jsonl'
    print(message + output_file)
    with open(output_file, 'w') as f:
        for entry in data:
            f.write(json.dumps(entry) + '\n')
    return

async def bc_generate(
        project_subscription: str,
        project_resource_group: str,
        project_name: str,
        scenario: str,
        max_simulation_results: int, 
        max_conversation_turns: int,
        simulator_type: str,
        output_file: str,
        control_sample_file: str,
        bc_params: bc_client_bot.BcParams = None
):

    bc_client = bc_client_bot.BcClient(bc_params)
    try:
        adv_scenario = AdversarialScenario[scenario]
    except KeyError:
        raise ValueError(f"Scenario {scenario} not found in AdversarialScenario enum, see available scenarios: https://learn.microsoft.com/en-us/azure/ai-studio/how-to/develop/simulator-interaction-data#supported-adversarial-simulation-scenarios")
    azure_ai_project = {
        "subscription_id": project_subscription,
        "resource_group_name": project_resource_group,
        "project_name": project_name,
        "credential": DefaultAzureCredential(),
    }
    
    try:
        # The default azure credential here authenticates to Azure AI Studio project, so it might be different credential from the BC client
        simulator = simulator_dict[simulator_type](azure_ai_project=azure_ai_project, credential=DefaultAzureCredential())
    except KeyError:
        raise ValueError(f"Simulator type {simulator_type} not found")
    except Exception as e:
        raise KeyError(f"Error creating simulator. See how to ensure you have permissions in READ.ME. The error: {e}")

    outputs = await simulator(
            scenario=adv_scenario,
            target=bc_client.callback,
            max_conversation_turns= max_conversation_turns,
            max_simulation_results=max_simulation_results,
            # Currently more than 2 concurrent tasks would sometimes take too long betwen turns
            # Causing BC session to timeout
            concurrent_async_task = 2
        )

    if simulator_dict[simulator_type] == DirectAttackSimulator:
        if control_sample_file == '':
            control_sample_file = 'control_sample-' + datetime.datetime.now().strftime("%d%m%Y-%H%M%S") + '.jsonl'
        control_lines = outputs['regular'].to_eval_qr_json_lines().strip().split('\n')
        control_data = [json.loads(line) for line in control_lines]
        save_to_jsonl(control_data, control_sample_file, message='Saving regular sample to ')
        outputs = outputs['jailbreak']

    lines = outputs.to_eval_qr_json_lines().strip().split('\n')
    data = [json.loads(line) for line in lines]
    # Write data to the JSON file
    save_to_jsonl(data, output_file)
    return data

async def bc_generate_with_dataset(
    output_file: str,
    data: Any,
    bc_params: bc_client_bot.BcParams = None        
):

    bc_client = bc_client_bot.BcClient(bc_params)
    
    if isinstance(data, str):
        if not data.endswith('.jsonl'):
            raise ValueError('Data file must be a JSONL file')
        with open(data, 'r') as f:
            lines = f.readlines()
            json_data = [json.loads(line) for line in lines]
            messages = [{'query': entry['query']} for entry in json_data]
    else:
        raise ValueError('Data must be a list of JSON objects')

    outputs = await bc_client.text_query_callback(messages)
    save_to_jsonl(outputs, output_file)
    return outputs
                
async def main():
    parser = argparse.ArgumentParser(description="Run Business Central copilot chat generation")
    parser.add_argument('--project-subscription', type=str, required=False, help='')
    parser.add_argument('--project-resource-group', type=str, required=False, help='')
    parser.add_argument('--project-name', type=str, required=False, help='')
    parser.add_argument('--bc-url', type=str, required=True, help='')
    parser.add_argument('--bc-tenant-id', type=str, required=True, help='')
    parser.add_argument('--keep-same-session', type=bool, required=False, help='', default=False)
    parser.add_argument('--max-conversation-turns', type=int, required=False, help='')
    parser.add_argument('--max-simulation-results', type=int, required=False, help='')
    parser.add_argument('--scenario', type=str, required=False, help='')
    parser.add_argument('--simulator-type', type=str, required=False, help='')
    parser.add_argument('--output-file', type=str, required=False, help='', default="")
    parser.add_argument('--control-sample-file', type=str, required=False, help='', default="")
    parser.add_argument('--tenant-guid', type=str, required=True, help='')
    parser.add_argument('--generate-from-dataset', action='store_true', required=False, help='')
    parser.add_argument('--data', type=str, required=False, help='')
    parser.add_argument('--chat-features', type = str, required=False, help='')
    parser.add_argument('--is-staging', action='store_true', required=False, help='')
    args = parser.parse_args()

    bc_params = bc_client_bot.BcParams(
        url= args.bc_url,
        tenantId= args.bc_tenant_id,
        tenant_id_guid= args.tenant_guid,
        chat_features= args.chat_features,
        is_staging= args.is_staging,
        keep_same_session= args.keep_same_session
    )

    if args.generate_from_dataset:
        if args.data is None:
            raise ValueError('Data file is required for chat generation')
        await bc_generate_with_dataset(
            output_file=args.output_file,
            data=args.data,
            bc_params=bc_params
        )
    else:
        if args.project_subscription is None or args.project_resource_group is None or args.project_name is None:
            raise ValueError('Project subscription, resource group and name are required for chat generation')

        await bc_generate(
            project_subscription=args.project_subscription,
            project_resource_group=args.project_resource_group,
            project_name=args.project_name,
            scenario=args.scenario,
            max_simulation_results=args.max_simulation_results,
            max_conversation_turns=args.max_conversation_turns,
            simulator_type=args.simulator_type,
            output_file=args.output_file,
            control_sample_file=args.control_sample_file,
            bc_params=bc_params
    )

if __name__ == '__main__':
    asyncio.run(main())
    
    