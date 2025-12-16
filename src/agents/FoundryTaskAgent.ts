import { AIProjectClient } from '@azure/ai-projects';
import { DefaultAzureCredential } from '@azure/identity';
import { TaskService } from '../services/TaskService.js';
import { ChatMessage } from '../types/index.js';

/**
 * Represents an agent that interfaces with Foundry Agent Service to process user messages in conversations.
 *
 * The `FoundryTaskAgent` class is responsible for:
 * - Initializing a connection to Foundry Agent Service using environment variables for configuration.
 * - Managing an agent session and conversation.
 * - Sending user messages to the agent and retrieving assistant responses.
 *
 * @remarks
 * This class requires the following environment variables to be set:
 * - `AZURE_AI_FOUNDRY_PROJECT_ENDPOINT`: The endpoint URL for the Foundry Agent Service project.
 * - `AZURE_AI_FOUNDRY_AGENT_NAME`: The name of the agent to use.
 */
export class FoundryTaskAgent {
    private taskService: TaskService;
    private project: AIProjectClient | null = null;
    private openAIClient: any = null;
    private agentName: string | null = null;
    private conversationId: string | null = null;
    private initializationPromise: Promise<void> | null = null;

    constructor(taskService: TaskService) {
        this.taskService = taskService;
    }

    /**
     * Lazy initialization - ensures the agent is initialized before first use.
     */
    private async ensureInitialized(): Promise<boolean> {
        // If already initialized, return immediately
        if (this.project && this.openAIClient && this.agentName && this.conversationId) {
            return true;
        }

        // If initialization is in progress, wait for it
        if (this.initializationPromise) {
            await this.initializationPromise;
            return !!(this.project && this.openAIClient && this.agentName && this.conversationId);
        }

        // Start new initialization
        this.initializationPromise = this.initialize();
        await this.initializationPromise;
        return !!(this.project && this.openAIClient && this.agentName && this.conversationId);
    }

    /**
     * Initialize the agent by creating the AI Project client and conversation.
     */
    private async initialize(): Promise<void> {
        const endpoint = process.env.AZURE_AI_FOUNDRY_PROJECT_ENDPOINT;
        const agentName = process.env.AZURE_AI_FOUNDRY_AGENT_NAME;

        if (!endpoint || !agentName) {
            console.warn('Foundry Agent Service configuration missing. Set AZURE_AI_FOUNDRY_PROJECT_ENDPOINT and AZURE_AI_FOUNDRY_AGENT_NAME');
            return;
        }

        try {
            // Create the AI Project client
            this.project = new AIProjectClient(endpoint, new DefaultAzureCredential());
            this.openAIClient = await this.project.getOpenAIClient();
            this.agentName = agentName;
            
            // Create a conversation for this session
            const conversation = await this.openAIClient.conversations.create({
                items: [],
            });
            this.conversationId = conversation.id;
            
            console.log(`Foundry agent initialized with name: ${this.agentName}, Conversation: ${this.conversationId}`);
        } catch (error) {
            console.error('Error initializing Foundry agent:', error);
        }
    }

    /**
     * Processes a user message by sending it to the Foundry agent and returns the assistant's response.
     *
     * This method performs the following steps:
     * 1. Ensures the agent is initialized (lazy initialization)
     * 2. Adds the user's message to the conversation
     * 3. Generates a response using the agent
     * 4. Returns the assistant's response
     *
     * @param message - The user's message to be processed by the agent.
     * @returns A promise that resolves to a `ChatMessage` object containing the assistant's response.
     */
    async processMessage(message: string): Promise<ChatMessage> {
        // Ensure initialization has completed
        const initialized = await this.ensureInitialized();
        
        if (!initialized || !this.openAIClient || !this.conversationId || !this.agentName) {
            return {
                role: 'assistant',
                content: 'Foundry agent is not properly configured. Please check your environment variables.'
            };
        }

        try {
            // Add the user message to the conversation
            await this.openAIClient.conversations.items.create(this.conversationId, {
                items: [{ type: 'message', role: 'user', content: message }],
            });

            // Generate response using the agent
            const response = await this.openAIClient.responses.create(
                {
                    conversation: this.conversationId,
                },
                {
                    body: { agent: { name: this.agentName, type: 'agent_reference' } },
                }
            );

            if (response.output_text) {
                return {
                    role: 'assistant',
                    content: response.output_text
                };
            } else {
                return {
                    role: 'assistant',
                    content: 'I received your message but couldn\'t generate a response.'
                };
            }

        } catch (error) {
            console.error('Error processing message with Foundry agent:', error);
            return {
                role: 'assistant',
                content: 'Sorry, I encountered an error processing your request.'
            };
        }
    }

    async cleanup(): Promise<void> {
        // Foundry agents are managed in the portal
        // No cleanup needed for the client or thread
        console.log('Foundry agent cleanup completed');
    }
}
