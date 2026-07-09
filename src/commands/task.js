import { SlashCommandBuilder, EmbedBuilder } from 'discord.js';
import { runTask } from '../ai/agent.js';

export const data = new SlashCommandBuilder()
  .setName('task')
  .setDescription('Ask the AI to do something in this server.')
  .addStringOption((option) =>
    option.setName('prompt').setDescription('What should I do?').setRequired(true),
  );

export async function execute(interaction) {
  const prompt = interaction.options.getString('prompt', true);
  await interaction.deferReply();

  let result;
  try {
    result = await runTask(interaction, prompt);
  } catch (err) {
    console.error('[/task] failed:', err);
    await interaction.editReply(`Something went wrong: ${err.message}`);
    return;
  }

  // If a confirmation flow already edited the reply (destructive actions), just
  // append the final summary; otherwise this is the first and only edit.
  await interaction.editReply({ content: result.summary, components: [] });

  await logToModChannel(interaction, prompt, result);
}

async function logToModChannel(interaction, prompt, result) {
  const channelId = process.env.MOD_LOG_CHANNEL_ID;
  if (!channelId || !result.executed) return;

  const logChannel = interaction.guild.channels.cache.get(channelId);
  if (!logChannel?.isTextBased()) return;

  const embed = new EmbedBuilder()
    .setTitle('/task executed')
    .setColor(result.executed.destructive ? 0xed4245 : 0x5865f2)
    .addFields(
      { name: 'User', value: `${interaction.user.tag} (${interaction.user.id})` },
      { name: 'Prompt', value: prompt.slice(0, 1024) },
      { name: 'Tool', value: result.executed.tool },
      { name: 'Result', value: `${result.executed.ok ? 'Success' : 'Failed/Refused'}: ${result.summary}`.slice(0, 1024) },
    )
    .setTimestamp();

  await logChannel.send({ embeds: [embed] }).catch(() => {});
}
