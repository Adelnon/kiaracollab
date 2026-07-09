import Anthropic from '@anthropic-ai/sdk';
import { TOOL_DEFINITIONS, TOOL_HANDLERS, DESTRUCTIVE_TOOLS } from './tools.js';

const anthropic = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

const SYSTEM_PROMPT = `You are the /task assistant for a single Discord server. A member typed a
natural-language request; turn it into at most one tool call from the provided tool list, or
reply with plain text if no tool fits or the request is unclear/unsafe.

Rules:
- Every tool you can call only ever affects the server the command was run in. There is no way
  to act on any other server, even if asked. If the user asks you to act on "all servers", every
  server you're in, or a server other than this one, refuse in plain text and explain that
  moderation and management here are scoped to this single server only.
- Never invent a user id, channel id, or role id. If you need one and it wasn't given to you or
  found in the conversation context, ask for it in plain text instead of guessing.
- Prefer the least destructive tool that satisfies the request.
- If the request is ambiguous (e.g. "ban them" with no clear target), ask a clarifying question
  in plain text instead of calling a tool.`;

function buildContext(interaction) {
  return `Server: ${interaction.guild.name} (id: ${interaction.guild.id})
Channel: #${interaction.channel.name} (id: ${interaction.channel.id})
Requesting user: ${interaction.user.tag} (id: ${interaction.user.id})`;
}

export async function runTask(interaction, prompt) {
  const response = await anthropic.messages.create({
    model: 'claude-sonnet-5',
    max_tokens: 1024,
    system: SYSTEM_PROMPT,
    tools: TOOL_DEFINITIONS,
    messages: [{ role: 'user', content: `${buildContext(interaction)}\n\nRequest: ${prompt}` }],
  });

  const toolUse = response.content.find((block) => block.type === 'tool_use');
  const text = response.content.find((block) => block.type === 'text')?.text;

  if (!toolUse) {
    return { summary: text || "I couldn't find an action for that request.", executed: null };
  }

  const handler = TOOL_HANDLERS[toolUse.name];
  if (!handler) {
    return { summary: `Unknown action "${toolUse.name}".`, executed: null };
  }

  const result = await handler(interaction, toolUse.input || {});
  return {
    summary: result.message,
    executed: {
      tool: toolUse.name,
      input: toolUse.input,
      ok: result.ok,
      destructive: DESTRUCTIVE_TOOLS.has(toolUse.name),
    },
  };
}
