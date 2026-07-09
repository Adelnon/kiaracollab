import { PermissionsBitField } from 'discord.js';

export function memberHasPermission(member, flag) {
  return Boolean(member?.permissions?.has(flag));
}

export function botHasPermission(guild, flag) {
  const me = guild?.members?.me;
  return Boolean(me?.permissions?.has(flag));
}

export function isOwner(userId) {
  return Boolean(process.env.OWNER_ID) && userId === process.env.OWNER_ID;
}

export const Flags = PermissionsBitField.Flags;
