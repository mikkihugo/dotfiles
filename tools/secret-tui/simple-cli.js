#!/usr/bin/env node

import { execa } from 'execa';
import chalk from 'chalk';
import os from 'os';
import fs from 'fs/promises';
import path from 'path';

const ENV_FILES = {
  tokens: { file: '~/.env_tokens', desc: 'Personal tokens & API keys (private)', color: 'red' },
  ai: { file: '~/.env_ai', desc: 'AI service configurations', color: 'blue' },
  docker: { file: '~/.env_docker', desc: 'Container & Docker configs', color: 'cyan' },
  repos: { file: '~/.env_repos', desc: 'Repository & project paths', color: 'green' },
  local: { file: '~/.env_local', desc: 'Local machine settings (never synced)', color: 'yellow' }
};

const SOPS_FILES = {
  tokens: { file: 'secrets/tokens.yaml', desc: 'Personal API keys (SOPS encrypted)', color: 'red' },
  ai: { file: 'secrets/ai.yaml', desc: 'AI service configurations (SOPS encrypted)', color: 'blue' },
  infra: { file: 'secrets/infrastructure.yaml', desc: 'Infrastructure secrets (SOPS encrypted)', color: 'cyan' },
  cloud: { file: 'secrets/cloud.yaml', desc: 'Cloud services (SOPS encrypted)', color: 'green' },
  auth: { file: 'secrets/auth.yaml', desc: 'Authentication secrets (SOPS encrypted)', color: 'yellow' }
};

const DOTFILES_ROOT = process.env.DOTFILES_ROOT || path.join(os.homedir(), '.dotfiles');

class SecretManager {
  async showMainMenu() {
    console.log(chalk.cyan.bold('\n🔐 Secret Manager\n'));
    console.log('Available actions:');
    console.log('1. View environment files status');
    console.log('2. View SOPS-encrypted files status');
    console.log('3. Migrate from plaintext env files to SOPS');
    console.log('4. Edit SOPS encrypted file');
    console.log('5. Test SOPS decryption');
    console.log('6. Exit');

    process.stdout.write('\nSelect option (1-6): ');
  }

  async checkEnvStatus() {
    console.log(chalk.yellow('\n📋 Environment Files Status\n'));

    for (const [key, config] of Object.entries(ENV_FILES)) {
      const filePath = config.file.replace('~', os.homedir());
      try {
        const stats = await fs.stat(filePath);
        const color = config.color === 'red' ? chalk.red :
                     config.color === 'blue' ? chalk.blue :
                     config.color === 'cyan' ? chalk.cyan :
                     config.color === 'green' ? chalk.green : chalk.yellow;

        console.log(color(`✅ ${config.file}`));
        console.log(chalk.gray(`   ${config.desc}`));
        console.log(chalk.gray(`   ${stats.size} bytes, modified: ${stats.mtime.toLocaleString()}\n`));
      } catch (error) {
        console.log(chalk.gray(`❌ ${config.file} - Not found`));
        console.log(chalk.gray(`   ${config.desc}\n`));
      }
    }
  }

  async checkSOPSStatus() {
    console.log(chalk.cyan('\n🔒 SOPS Encrypted Files Status\n'));

    for (const [key, config] of Object.entries(SOPS_FILES)) {
      const filePath = path.join(DOTFILES_ROOT, config.file);
      try {
        const stats = await fs.stat(filePath);
        const color = config.color === 'red' ? chalk.red :
                     config.color === 'blue' ? chalk.blue :
                     config.color === 'cyan' ? chalk.cyan :
                     config.color === 'green' ? chalk.green : chalk.yellow;

        console.log(color(`✅ ${config.file}`));
        console.log(chalk.gray(`   ${config.desc}`));
        console.log(chalk.gray(`   ${stats.size} bytes, modified: ${stats.mtime.toLocaleString()}`));

        // Test decryption
        try {
          await execa('sops', ['-d', filePath], {
            env: {
              SOPS_AGE_KEY_FILE: path.join(os.homedir(), '.config/sops/age/keys.txt')
            }
          });
          console.log(chalk.green('   🔓 Decryption: OK\n'));
        } catch (error) {
          console.log(chalk.red('   🔒 Decryption: Failed\n'));
        }
      } catch (error) {
        console.log(chalk.gray(`❌ ${config.file} - Not found`));
        console.log(chalk.gray(`   ${config.desc}\n`));
      }
    }
  }

  async testSOPSDecryption() {
    console.log(chalk.blue('\n🔍 Testing SOPS Decryption\n'));

    const sharedFile = path.join(DOTFILES_ROOT, 'secrets/shared.yaml');
    try {
      const { stdout } = await execa('sops', ['-d', sharedFile], {
        env: {
          SOPS_AGE_KEY_FILE: path.join(os.homedir(), '.config/sops/age/keys.txt')
        }
      });

      console.log(chalk.green('✅ SOPS decryption successful'));
      console.log(chalk.gray('First few lines of decrypted content:'));
      const lines = stdout.split('\n').slice(0, 10);
      lines.forEach(line => {
        if (line.includes('=')) {
          const [key] = line.split('=');
          console.log(chalk.blue(`  ${key}=***`));
        } else {
          console.log(chalk.gray(`  ${line}`));
        }
      });
    } catch (error) {
      console.log(chalk.red(`❌ SOPS decryption failed: ${error.message}`));
    }
  }

  async migrateToSOPS() {
    console.log(chalk.yellow('\n🔄 Migrate to SOPS Encrypted Structure\n'));

    // This would implement migration logic
    console.log(chalk.blue('Migration strategy:'));
    console.log('1. Read current secrets from shared.yaml');
    console.log('2. Categorize secrets by type (AI, INFRA, CLOUD, etc.)');
    console.log('3. Create separate encrypted files');
    console.log('4. Update shell configuration to load from categorized files');
    console.log(chalk.yellow('\n⚠️  This feature needs implementation!'));
  }

  async editSOPSFile() {
    console.log(chalk.green('\n✏️  Edit SOPS File\n'));

    console.log('Available SOPS files:');
    const files = Object.entries(SOPS_FILES);
    files.forEach(([key, config], index) => {
      console.log(`${index + 1}. ${config.file} - ${config.desc}`);
    });

    process.stdout.write('\nSelect file to edit (1-5): ');
    // This would implement file selection and editing
  }

  async run() {
    const args = process.argv.slice(2);

    if (args.length === 0) {
      this.showMainMenu();
      return;
    }

    switch (args[0]) {
      case 'status':
      case '1':
        await this.checkEnvStatus();
        break;
      case 'sops':
      case '2':
        await this.checkSOPSStatus();
        break;
      case 'migrate':
      case '3':
        await this.migrateToSOPS();
        break;
      case 'edit':
      case '4':
        await this.editSOPSFile();
        break;
      case 'test':
      case '5':
        await this.testSOPSDecryption();
        break;
      default:
        console.log(chalk.red(`Unknown command: ${args[0]}`));
        console.log('Available commands: status, sops, migrate, edit, test');
    }
  }
}

const manager = new SecretManager();
manager.run().catch(console.error);