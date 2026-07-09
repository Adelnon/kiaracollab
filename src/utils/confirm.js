import { ActionRowBuilder, ButtonBuilder, ButtonStyle, ComponentType } from 'discord.js';

const CONFIRM_TIMEOUT_MS = 30_000;

/**
 * Shows a Confirm/Cancel button pair and resolves to true only if the
 * original command invoker clicks Confirm within the timeout. Used to gate
 * every destructive action so a single free-text prompt can never execute
 * something irreversible without an explicit extra click.
 */
export async function confirmAction(interaction, description) {
  const row = new ActionRowBuilder().addComponents(
    new ButtonBuilder().setCustomId('task-confirm').setLabel('Confirm').setStyle(ButtonStyle.Danger),
    new ButtonBuilder().setCustomId('task-cancel').setLabel('Cancel').setStyle(ButtonStyle.Secondary),
  );

  const message = await interaction.editReply({
    content: `${description}\n\nThis action cannot be easily undone. Confirm within 30 seconds to proceed.`,
    components: [row],
  });

  try {
    const click = await message.awaitMessageComponent({
      componentType: ComponentType.Button,
      time: CONFIRM_TIMEOUT_MS,
      filter: (i) => i.user.id === interaction.user.id,
    });

    await click.update({ components: [] });
    return click.customId === 'task-confirm';
  } catch {
    await interaction.editReply({ content: `${description}\n\nTimed out waiting for confirmation. Cancelled.`, components: [] });
    return false;
  }
}
