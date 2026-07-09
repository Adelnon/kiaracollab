import { ChannelType, Routes } from 'discord.js';
import { Flags, memberHasPermission, botHasPermission, isOwner } from '../utils/permissions.js';
import { confirmAction } from '../utils/confirm.js';

/**
 * Fixed palette of actions the AI is allowed to pick from. The model never
 * gets raw Discord API access -- it can only select one of these tool names
 * with these parameters, and every handler re-checks real Discord
 * permissions itself before doing anything (the model's judgement is never
 * trusted as the sole gate).
 *
 * Every moderation/administrative action is scoped to interaction.guild,
 * i.e. the single server the /task command was run in. There is
 * intentionally no "act across every server the bot is in" tool: a command
 * that can ban/kick a named user from every community the bot happens to be
 * in would let one server's moderator (or a compromised/prompted command)
 * deplatform someone from unrelated servers without those servers' own
 * admins ever consenting. If you need cross-server moderation, build it as
 * an explicit, audited, owner-only feature -- not as a side effect of a
 * general natural-language command.
 */

export const TOOL_DEFINITIONS = [
  {
    name: 'send_message',
    description: 'Send a text message to a channel in the current server.',
    input_schema: {
      type: 'object',
      properties: {
        channel_id: { type: 'string', description: 'Target channel id. Defaults to the current channel if omitted.' },
        content: { type: 'string', description: 'Message content to send.' },
      },
      required: ['content'],
    },
  },
  {
    name: 'create_channel',
    description: 'Create a new text or voice channel in the current server.',
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        type: { type: 'string', enum: ['text', 'voice'] },
        topic: { type: 'string' },
      },
      required: ['name', 'type'],
    },
  },
  {
    name: 'create_role',
    description: 'Create a new role in the current server. Cannot grant Administrator.',
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
        color: { type: 'string', description: 'Hex color, e.g. #5865F2' },
        mentionable: { type: 'boolean' },
      },
      required: ['name'],
    },
  },
  {
    name: 'create_invite',
    description: 'Create an invite link for a channel in the current server.',
    input_schema: {
      type: 'object',
      properties: {
        channel_id: { type: 'string' },
        max_uses: { type: 'number', description: '0 means unlimited.' },
        max_age_seconds: { type: 'number', description: '0 means never expires.' },
      },
      required: [],
    },
  },
  {
    name: 'timeout_member',
    description: 'Temporarily mute (timeout) a member of the current server.',
    input_schema: {
      type: 'object',
      properties: {
        user_id: { type: 'string' },
        minutes: { type: 'number', description: 'Timeout duration in minutes, max 40320 (28 days).' },
        reason: { type: 'string' },
      },
      required: ['user_id', 'minutes'],
    },
  },
  {
    name: 'kick_member',
    description: 'Kick a member from the current server only.',
    input_schema: {
      type: 'object',
      properties: {
        user_id: { type: 'string' },
        reason: { type: 'string' },
      },
      required: ['user_id'],
    },
  },
  {
    name: 'ban_member',
    description:
      'Ban a member from the current server only. This tool can never target any server other ' +
      'than the one the command was run in -- if the user asks to ban someone from multiple or ' +
      'all servers, refuse in your text reply and explain that moderation is scoped per-server.',
    input_schema: {
      type: 'object',
      properties: {
        user_id: { type: 'string' },
        reason: { type: 'string' },
        delete_message_days: { type: 'number', description: '0-7, how many days of their messages to delete.' },
      },
      required: ['user_id'],
    },
  },
  {
    name: 'create_server',
    description:
      "Create a brand new Discord server (guild) owned by the bot. Owner-only, since it consumes " +
      'the bot account\'s limited guild-creation quota.',
    input_schema: {
      type: 'object',
      properties: {
        name: { type: 'string' },
      },
      required: ['name'],
    },
  },
];

export const DESTRUCTIVE_TOOLS = new Set(['kick_member', 'ban_member', 'timeout_member', 'create_server']);

function resolveChannel(interaction, channelId) {
  if (!channelId) return interaction.channel;
  const channel = interaction.guild.channels.cache.get(channelId);
  if (!channel) throw new Error(`No channel with id ${channelId} in this server.`);
  return channel;
}

export const TOOL_HANDLERS = {
  async send_message(interaction, input) {
    const channel = resolveChannel(interaction, input.channel_id);
    if (!memberHasPermission(interaction.member, Flags.SendMessages)) {
      return { ok: false, message: 'You do not have permission to send messages here.' };
    }
    await channel.send(input.content);
    return { ok: true, message: `Sent message to #${channel.name}.` };
  },

  async create_channel(interaction, input) {
    if (!memberHasPermission(interaction.member, Flags.ManageChannels) || !botHasPermission(interaction.guild, Flags.ManageChannels)) {
      return { ok: false, message: 'Missing Manage Channels permission (you or the bot).' };
    }
    const channel = await interaction.guild.channels.create({
      name: input.name,
      type: input.type === 'voice' ? ChannelType.GuildVoice : ChannelType.GuildText,
      topic: input.type === 'voice' ? undefined : input.topic,
    });
    return { ok: true, message: `Created channel ${channel.toString()}.` };
  },

  async create_role(interaction, input) {
    if (!memberHasPermission(interaction.member, Flags.ManageRoles) || !botHasPermission(interaction.guild, Flags.ManageRoles)) {
      return { ok: false, message: 'Missing Manage Roles permission (you or the bot).' };
    }
    const role = await interaction.guild.roles.create({
      name: input.name,
      color: input.color,
      mentionable: Boolean(input.mentionable),
      // Deliberately never forwards elevated permissions from the model's input.
      permissions: [],
    });
    return { ok: true, message: `Created role ${role.toString()}.` };
  },

  async create_invite(interaction, input) {
    const channel = resolveChannel(interaction, input.channel_id);
    if (!memberHasPermission(interaction.member, Flags.CreateInstantInvite)) {
      return { ok: false, message: 'You do not have permission to create invites.' };
    }
    const invite = await channel.createInvite({
      maxUses: input.max_uses ?? 0,
      maxAge: input.max_age_seconds ?? 0,
    });
    return { ok: true, message: `Invite created: ${invite.url}` };
  },

  async timeout_member(interaction, input) {
    if (!memberHasPermission(interaction.member, Flags.ModerateMembers) || !botHasPermission(interaction.guild, Flags.ModerateMembers)) {
      return { ok: false, message: 'Missing Timeout Members permission (you or the bot).' };
    }
    const target = await interaction.guild.members.fetch(input.user_id).catch(() => null);
    if (!target) return { ok: false, message: `No member with id ${input.user_id} in this server.` };
    if (!target.moderatable) return { ok: false, message: 'That member outranks the bot or cannot be moderated.' };

    const confirmed = await confirmAction(interaction, `Timeout ${target.user.tag} for ${input.minutes} minute(s)?`);
    if (!confirmed) return { ok: false, message: 'Cancelled.' };

    const ms = Math.min(Math.max(input.minutes, 1), 40320) * 60_000;
    await target.timeout(ms, input.reason || 'Requested via /task');
    return { ok: true, message: `Timed out ${target.user.tag} for ${input.minutes} minute(s).` };
  },

  async kick_member(interaction, input) {
    if (!memberHasPermission(interaction.member, Flags.KickMembers) || !botHasPermission(interaction.guild, Flags.KickMembers)) {
      return { ok: false, message: 'Missing Kick Members permission (you or the bot).' };
    }
    const target = await interaction.guild.members.fetch(input.user_id).catch(() => null);
    if (!target) return { ok: false, message: `No member with id ${input.user_id} in this server.` };
    if (!target.kickable) return { ok: false, message: 'That member outranks the bot or cannot be kicked.' };

    const confirmed = await confirmAction(interaction, `Kick ${target.user.tag} from this server?`);
    if (!confirmed) return { ok: false, message: 'Cancelled.' };

    await target.kick(input.reason || 'Requested via /task');
    return { ok: true, message: `Kicked ${target.user.tag} from this server.` };
  },

  async ban_member(interaction, input) {
    if (!memberHasPermission(interaction.member, Flags.BanMembers) || !botHasPermission(interaction.guild, Flags.BanMembers)) {
      return { ok: false, message: 'Missing Ban Members permission (you or the bot).' };
    }
    const target = await interaction.guild.members.fetch(input.user_id).catch(() => null);
    if (target && !target.bannable) {
      return { ok: false, message: 'That member outranks the bot or cannot be banned.' };
    }

    const confirmed = await confirmAction(
      interaction,
      `Ban <@${input.user_id}> from **${interaction.guild.name}** only? (Moderation never spans other servers.)`,
    );
    if (!confirmed) return { ok: false, message: 'Cancelled.' };

    await interaction.guild.members.ban(input.user_id, {
      reason: input.reason || 'Requested via /task',
      deleteMessageSeconds: Math.min(Math.max(input.delete_message_days ?? 0, 0), 7) * 86_400,
    });
    return { ok: true, message: `Banned <@${input.user_id}> from ${interaction.guild.name}.` };
  },

  async create_server(interaction, input) {
    if (!isOwner(interaction.user.id)) {
      return { ok: false, message: 'Only the bot owner can create new servers.' };
    }
    const confirmed = await confirmAction(interaction, `Create a brand new server named "${input.name}"?`);
    if (!confirmed) return { ok: false, message: 'Cancelled.' };

    const guild = await interaction.client.rest.post(Routes.guilds(), { body: { name: input.name } });
    return { ok: true, message: `Created server "${input.name}" (id: ${guild.id}). Use an invite from within it to join.` };
  },
};
