import 'dotenv/config';
import { REST, Routes } from 'discord.js';
import { data as taskCommand } from './commands/task.js';

const required = ['DISCORD_TOKEN', 'DISCORD_CLIENT_ID'];
for (const key of required) {
  if (!process.env[key]) {
    console.error(`Missing ${key} in environment/.env`);
    process.exit(1);
  }
}

const rest = new REST().setToken(process.env.DISCORD_TOKEN);

try {
  console.log('Registering /task command globally (may take up to an hour to propagate)...');
  await rest.put(Routes.applicationCommands(process.env.DISCORD_CLIENT_ID), {
    body: [taskCommand.toJSON()],
  });
  console.log('Done.');
} catch (err) {
  console.error('Failed to register commands:', err);
  process.exit(1);
}
