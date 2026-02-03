from typing import Dict, List, Any
import requests
from urllib3.exceptions import InsecureRequestWarning
import json
import msal
from azure.identity import DefaultAzureCredential


class BcParams:
    def __init__(
        self,
        url: str,
        tenantId: str,
        tenant_id_guid: str,
        chat_features: str = "",
        is_staging: bool = False,
        keep_same_session: bool = False
):
        self.url = url
        self.tenantId = tenantId
        if is_staging:
            self.scopes = "https://projectmadeira-ppe.com/.default"
            self.authority = "https://login.windows-ppe.net/" + tenant_id_guid
        else:
            self.scopes = "https://projectmadeira.com/.default"
            self.authority = "https://login.microsoftonline.com/" + tenant_id_guid
        self.tenant_id_guid = tenant_id_guid
        self.chat_features = chat_features
        self.is_staging = is_staging
        self.keep_same_session = keep_same_session


class BcClient:
    def __init__(self, bcParams: BcParams):
        """Initialize BC client to send message to BC orchestrator endpoint"""
        self.bcParams = bcParams
        requests.packages.urllib3.disable_warnings(category=InsecureRequestWarning)
        
        # Create a session so the cookies can be stored between requests
        self.session = requests.Session()

        try:
            # Create a credential object with the default Azure credential
            # Only managed identity, interactive browser, and environment credentials are enabled
            # For local run, interactive login will be triggered
            # As a build agent, managed identity + Entra app, or environment credentials can be used
            self.credential = DefaultAzureCredential(
                exclude_workload_identity_credential = True,
                exclude_developer_cli_credential = True,
                exclude_cli_credential = True,
                exclude_visual_studio_code_credential = True,
                exclude_powershell_credential = True,
                exclude_shared_token_cache_credential = True,
                exclude_managed_identity_credential = False,
                exclude_interactive_browser_credential = False,
                authority = self.bcParams.authority
            )

            # Try retrieving the token for the first time
            result = self.credential.get_token(self.bcParams.scopes)

            if result.token is not None:
                print("Login successful")
            else:
                print("Login failed")
                return { "success": False }

        except Exception as e:
            print("Exception when creating a BC client")
            return { "success": False }

    def create_bc_session(self):
        try:             
            # 1. Create client session using client services
            payload = json.dumps({
                "jsonrpc": "2.0",
                "method": "OpenSession",
                "params": [
                    {
                        "ClientVersion": "1.0.0.0"
                    }
                ],
                "id": "0"
            })
            
            url = self.bcParams.url + "/cs?aid=FIN&tenant=" + self.bcParams.tenantId
            response = self.session.post(url=url, data=payload, headers=self._get_auth_headers(), verify=False)
            self.sessionId = response.json()["result"]["sessionId"]

            # 2. Initialize client session by opening RC
            payload = json.dumps({
                "jsonrpc": "2.0",
                "method": "InvokeInteractions",
                "params": [
                    {
                        "Context": {
                        "SessionId": self.sessionId
                    },
                "InteractionsToInvoke": [
                    {
                        "InteractionName": "OpenForm",
                        "NamedParameters": {
                            "Page": "9006"
                        }
                    }]
                }
                ],
                "id": "0"
            })
            response = self.session.post(url=url, data=payload, headers=self._get_auth_headers(), verify=False)
            if "Order Processor Role Center" not in response.text:
                raise Exception(f"Could not initialize BC session")
            
            # Extract the role center form id
            changes = response.json()["result"]["LogicalChangeSet"]["Changes"]
            self.rcFormId = next(x['FormToShow']['ServerId'] for x in changes if 'FormToShow' in x)

        except Exception as e:
            print("Exception when creating a BC session: " + str(e))
            return { "success": False }
        
    def create_new_chat_session(self):
        try:            
            # 4. Create a Copilot chat session
            url = self.bcParams.url + "/copilot/cs.createSession?aid=FIN&tenant=" + self.bcParams.tenantId + "&SessionId=" + self.sessionId
            response = self.session.post(url=url, headers=self._get_auth_headers(), verify=False)

            self.chatId = response.json()["session"]["id"]
            
            return response
        except Exception as e:
            print("Exception when creating a new chat session: " + str(e))
            return { "success": False }
    
    async def generate_response(
        self,
        message_to_send,
        chatSessionId,
        bcSessionId
    ) -> str:
        """
        Prompt the BcClient bot for a response.

        Parameters
        ----------
        message_to_send: The query to send to Copilot Chat.
        bcSessionId: The Business Central session id to use for the request.
        chatSessionId: The Copilot Chat session id to use for the request.

        Returns
        -------
        response: The response from the BCBot.
        time_taken: The time taken to generate the response.
        full_response: The full response from the model.
        """

        # send message
        response = self.send_message(message_to_send, chatSessionId, bcSessionId)

        if not response.ok:
            raise Exception(f"Unexpected result from BcBot: {response.status_code}")

        for line in response.text.split("\n"):
            if (not line):
                continue
            lineResult = json.loads(line)
            if lineResult["message"]:
                response_text = lineResult["message"]["content"]

        if not response_text:
            raise Exception(f"Message not found in response: {response.text}")
        return response_text

    def send_message(self, message: str, chatSessionId, bcSessionId):
        try:
            payload = json.dumps({
                    "context": {
                        "chatId": chatSessionId,
                        "variables": [
                            {
                                "key": "pageId",
                                "value": "9006"
                            },
                            {
                                "key": "chatFeatures",
                                "value": self.bcParams.chat_features
                            }
                        ]
                    },
                    "input": message
                })

            url = self.bcParams.url + "/copilot/cs.ask?aid=FIN&tenant=" + self.bcParams.tenantId + "&SessionId=" + bcSessionId
            response = self.session.post(url=url, data=payload, headers=self._get_auth_headers(), verify=False)
            return response
        except Exception as e:
            print("Exception when calling BC Bot")
            return { "success": False }

    def _get_auth_token(self):
        try:
            return self.credential.get_token(self.bcParams.scopes).token
        except Exception as e:
            print("Exception when getting auth token")
            return { "success": False }
        
    def _get_auth_headers(self):
        token = self._get_auth_token()
        return {
            'Content-Type': 'application/json',
            'Authorization': f'Bearer {token}'
        }
    

    async def callback(
            self,
            messages: List[Dict],
            stream: bool = False,
            session_state: Dict[str, Any] = {},
    ) -> dict:
        query = messages["messages"][-1]["content"]
        # Initializing context so it always has a value
        context = ' '

        # Add file contents for summarization or re-write
        if 'file_content' in messages["template_parameters"]:
            query += messages["template_parameters"]['file_content']
            context = messages["template_parameters"]['file_content']
        if 'content' in messages["template_parameters"]:
            context += messages["template_parameters"]['content']

        
        try:
            if not messages["messages"][0]["content"] in session_state:
                self.create_bc_session()
                self.create_new_chat_session()
                session_state[messages["messages"][0]["content"]] = {"chatSessionId": self.chatId, "bcSessionId": self.sessionId}

            response = await self.generate_response(query, session_state[messages["messages"][0]["content"]]["chatSessionId"], session_state[messages["messages"][0]["content"]]["bcSessionId"]) 
        except Exception as e:
            response = "Answer generation failed: " + str(e)
        
        # Format responses in OpenAI message protocol
        formatted_response = {
            "content": response,
            "role": "assistant",
            "context": context,
        }
        
        messages["messages"].append(formatted_response)
        return {
            "messages": messages["messages"],
            "stream": stream,
            "session_state": session_state,
            "context": context
        }
    
    async def text_query_callback(
        self,
        messages: List[Dict],
        keep_same_session: bool = False,
        keep_same_chat_session: bool = False,
    ) -> List[Dict]:
        """
        Callback for text queries.
        """
        query_response_pairs = []
        if keep_same_session:
            self.create_bc_session()
        if keep_same_chat_session:
            self.create_new_chat_session()

        for message in messages:
            if not keep_same_session:
                self.create_bc_session()
            if not keep_same_chat_session:
                self.create_new_chat_session()

            try:
                response = await self.generate_response(message["query"], self.chatId, self.sessionId)
            except Exception as e:
                response = "Answer generation failed: " + str(e)

            formatted_response = {
                "query": message["query"],
                "response": response
            }
            query_response_pairs.append(formatted_response)
        return query_response_pairs
        
    
