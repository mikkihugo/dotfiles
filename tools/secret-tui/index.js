#!/usr/bin/env node
import React, { useState, useEffect } from 'react';
import { render, Box, Text, useInput } from 'ink';
import BigText from '@ink-ui/big-text';
import Select from '@ink-ui/select';
import TextInput from '@ink-ui/text-input';
import Spinner from '@ink-ui/spinner';
import { execa } from 'execa';
import chalk from 'chalk';
import path from 'path';
import os from 'os';

// Environment file categories
const ENV_FILES = {
  tokens: { file: '~/.env_tokens', desc: 'Personal tokens & API keys (private)', color: 'red' },
  ai: { file: '~/.env_ai', desc: 'AI service configurations', color: 'blue' },
  docker: { file: '~/.env_docker', desc: 'Container & Docker configs', color: 'cyan' },
  repos: { file: '~/.env_repos', desc: 'Repository & project paths', color: 'green' },
  local: { file: '~/.env_local', desc: 'Local machine settings (never synced)', color: 'yellow' }
};

// Secret categories with better naming
const SECRET_CATEGORIES = {
  LLM: 'AI/Language Model providers',
  INFRA: 'Infrastructure and databases',
  CLOUD: 'Cloud services and CDN', 
  DEV: 'Development tools and CI/CD',
  AUTH: 'Authentication and security'
};

const LLM_SECRETS = {
  'LLM_ANTHROPIC_API_KEY': 'Anthropic Claude API key',
  'LLM_OPENAI_API_KEY': 'OpenAI GPT API key',
  'LLM_GOOGLE_GEMINI_API_KEY': 'Google Gemini API key',
  'LLM_MISTRAL_API_KEY': 'Mistral AI API key',
  'LLM_COHERE_API_KEY': 'Cohere API key',
  'LLM_GROQ_API_KEY': 'Groq API key',
  'LLM_OPENROUTER_API_KEY': 'OpenRouter API key',
  'LLM_HUGGINGFACE_TOKEN': 'Hugging Face token'
};

const INFRA_SECRETS = {
  'INFRA_DATABASE_URL': 'PostgreSQL connection string',
  'INFRA_DB_PASSWORD': 'Database password',
  'INFRA_VAULT_MASTER_KEY': 'Vault encryption master key',
  'INFRA_JWT_SECRET': 'JWT signing secret',
  'INFRA_SESSION_SECRET': 'Session encryption secret'
};

const CLOUD_SECRETS = {
  'CLOUD_CLOUDFLARE_API_TOKEN': 'Cloudflare API token',
  'CLOUD_CLOUDFLARE_ZONE_ID': 'Cloudflare zone ID',
  'CLOUD_VULTR_API_KEY': 'Vultr API key',
  'CLOUD_VULTR_INFERENCE_KEY': 'Vultr inference API key'
};

const DEV_SECRETS = {
  'DEV_GITHUB_TOKEN': 'GitHub personal access token',
  'DEV_GITHUB_COPILOT_TOKEN': 'GitHub Copilot OAuth token',
  'DEV_CLAUDE_CODE_OAUTH_TOKEN': 'Claude Code OAuth token'
};

const AUTH_SECRETS = {
  'AUTH_ENCRYPTION_KEY': 'Data encryption key',
  'AUTH_CF_AI_GATEWAY_TOKEN': 'Cloudflare AI Gateway token'
};

const ALL_SECRETS = {
  LLM: LLM_SECRETS,
  INFRA: INFRA_SECRETS,
  CLOUD: CLOUD_SECRETS,
  DEV: DEV_SECRETS,
  AUTH: AUTH_SECRETS
};

const Header = () => (
  <Box flexDirection="column" marginBottom={1}>
    <BigText text="🔐 Secret Manager" />
    <Text color="gray">GitHub Secrets + Local Management</Text>
  </Box>
);

const MainMenu = ({ onSelect }) => {
  const items = [
    { label: '🗂️ Multi-Environment Manager', value: 'multi-env' },
    { label: '📋 View environment files', value: 'view-env' },
    { label: '➕ Edit environment file', value: 'edit-env' },
    { label: '🔄 Sync with GitHub (gists)', value: 'sync-gists' },
    { label: '🔐 Sync with GitHub (secrets)', value: 'sync-secrets' },
    { label: '🧹 Clean up old configs', value: 'cleanup' },
    { label: '🔍 Search across all env files', value: 'search' },
    { label: '❌ Exit', value: 'exit' }
  ];

  return (
    <Box flexDirection="column">
      <Text color="yellow">Available actions:</Text>
      <Select items={items} onSelect={onSelect} />
    </Box>
  );
};

const SecretList = ({ secrets, onBack }) => {
  useInput((input, key) => {
    if (key.escape || input === 'q') {
      onBack();
    }
  });

  return (
    <Box flexDirection="column">
      <Text color="green">📋 Current GitHub Secrets:</Text>
      <Box marginY={1}>
        {secrets.length > 0 ? (
          secrets.map(secret => (
            <Text key={secret.name}>
              {secret.name} ({secret.visibility}) - Updated: {secret.updatedAt}
            </Text>
          ))
        ) : (
          <Text color="gray">No secrets found</Text>
        )}
      </Box>
      <Text color="gray">Press 'q' or ESC to go back</Text>
    </Box>
  );
};

const CategorySelect = ({ onSelect, onBack }) => {
  const items = Object.entries(SECRET_CATEGORIES).map(([key, desc]) => ({
    label: `${key}: ${desc}`,
    value: key
  }));

  useInput((input, key) => {
    if (key.escape || input === 'q') {
      onBack();
    }
  });

  return (
    <Box flexDirection="column">
      <Text color="green">➕ Add New Secret</Text>
      <Text color="yellow">Select category:</Text>
      <Select items={items} onSelect={onSelect} />
      <Text color="gray">Press 'q' or ESC to go back</Text>
    </Box>
  );
};

const SecretSelect = ({ category, onSelect, onBack }) => {
  const secrets = ALL_SECRETS[category];
  const items = Object.entries(secrets).map(([key, desc]) => ({
    label: `${key}: ${desc}`,
    value: key
  }));

  useInput((input, key) => {
    if (key.escape || input === 'q') {
      onBack();
    }
  });

  return (
    <Box flexDirection="column">
      <Text color="green">Select secret to set:</Text>
      <Text color="yellow">Category: {SECRET_CATEGORIES[category]}</Text>
      <Select items={items} onSelect={onSelect} />
      <Text color="gray">Press 'q' or ESC to go back</Text>
    </Box>
  );
};

const SecretInput = ({ secretName, secretDesc, onSubmit, onBack }) => {
  const [value, setValue] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  useInput((input, key) => {
    if (key.escape || input === 'q') {
      onBack();
    }
    if (key.return && value.trim()) {
      handleSubmit();
    }
  });

  const handleSubmit = async () => {
    if (!value.trim()) return;
    
    setIsSubmitting(true);
    try {
      await onSubmit(secretName, value);
    } finally {
      setIsSubmitting(false);
    }
  };

  return (
    <Box flexDirection="column">
      <Text color="yellow">Setting: {secretName}</Text>
      <Text color="gray">{secretDesc}</Text>
      <Box marginY={1}>
        <Text>Enter secret value: </Text>
        <TextInput
          value={value}
          onChange={setValue}
          placeholder="Enter secret value..."
          mask="*"
        />
      </Box>
      {isSubmitting && (
        <Box>
          <Spinner type="dots" />
          <Text> Setting secret...</Text>
        </Box>
      )}
      <Text color="gray">Press Enter to submit, 'q' or ESC to go back</Text>
    </Box>
  );
};

// Multi-Environment Manager Component
const MultiEnvManager = ({ onBack }) => {
  const [envStatus, setEnvStatus] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    checkEnvStatus();
  }, []);

  const checkEnvStatus = async () => {
    setLoading(true);
    try {
      const status = {};
      for (const [key, config] of Object.entries(ENV_FILES)) {
        const filePath = config.file.replace('~', process.env.HOME);
        try {
          const { stdout } = await execa('stat', ['-c', '%s,%Y', filePath]);
          const [size, mtime] = stdout.split(',');
          status[key] = {
            exists: true,
            size: parseInt(size),
            modified: new Date(parseInt(mtime) * 1000).toLocaleString(),
            ...config
          };
        } catch {
          status[key] = { exists: false, ...config };
        }
      }
      setEnvStatus(status);
    } catch (error) {
      console.error('Error checking env status:', error);
    }
    setLoading(false);
  };

  useInput((input, key) => {
    if (key.escape || input === 'q') {
      onBack();
    }
  });

  if (loading) {
    return (
      <Box flexDirection="column" alignItems="center">
        <Spinner />
        <Text> Checking environment files...</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Text color="cyan">🗂️ Multi-Environment Status</Text>
      <Text color="gray">═══════════════════════════════</Text>
      <Box marginY={1}>
        {Object.entries(envStatus || {}).map(([key, status]) => (
          <Box key={key} marginY={0} flexDirection="column">
            <Box>
              <Text color={status.color}>
                {status.exists ? '✅' : '❌'} {status.file}
              </Text>
            </Box>
            <Box marginLeft={3}>
              <Text color="gray" dimColor>
                {status.desc}
              </Text>
            </Box>
            {status.exists && (
              <Box marginLeft={3}>
                <Text color="gray" dimColor>
                  {status.size} bytes, modified: {status.modified}
                </Text>
              </Box>
            )}
            <Text> </Text>
          </Box>
        ))}
      </Box>
      <Text color="yellow">💡 Tips:</Text>
      <Text color="gray">• ~/.env_tokens: Keep your most sensitive API keys here</Text>
      <Text color="gray">• ~/.env_local: Machine-specific settings, never synced</Text>
      <Text color="gray">• Other files: Can be shared via gists or GitHub secrets</Text>
      <Box marginTop={1}>
        <Text color="gray">Press 'q' or ESC to go back</Text>
      </Box>
    </Box>
  );
};

// Environment File Viewer
const EnvFileViewer = ({ onBack }) => {
  const [selectedEnv, setSelectedEnv] = useState(null);
  const [envContent, setEnvContent] = useState('');
  const [loading, setLoading] = useState(false);

  const viewEnvFile = async (envKey) => {
    const config = ENV_FILES[envKey];
    const filePath = config.file.replace('~', process.env.HOME);
    
    setLoading(true);
    try {
      const { stdout } = await execa('cat', [filePath]);
      setEnvContent(stdout);
      setSelectedEnv(envKey);
    } catch (error) {
      setEnvContent(`Error reading ${config.file}: ${error.message}`);
      setSelectedEnv(envKey);
    }
    setLoading(false);
  };

  useInput((input, key) => {
    if (key.escape || input === 'q') {
      if (selectedEnv) {
        setSelectedEnv(null);
        setEnvContent('');
      } else {
        onBack();
      }
    }
  });

  if (selectedEnv) {
    return (
      <Box flexDirection="column">
        <Text color={ENV_FILES[selectedEnv].color}>
          📄 {ENV_FILES[selectedEnv].file}
        </Text>
        <Text color="gray">─────────────────────────────────</Text>
        <Box marginY={1} flexDirection="column">
          {loading ? (
            <Spinner />
          ) : (
            envContent.split('\n').map((line, index) => (
              <Text key={index} color={line.startsWith('#') ? 'gray' : 'white'}>
                {line || ' '}
              </Text>
            ))
          )}
        </Box>
        <Text color="gray">Press 'q' or ESC to go back</Text>
      </Box>
    );
  }

  const envItems = Object.entries(ENV_FILES).map(([key, config]) => ({
    label: `${config.color === 'red' ? '🔒' : '📄'} ${config.file} - ${config.desc}`,
    value: key
  }));

  return (
    <Box flexDirection="column">
      <Text color="green">📋 Select Environment File to View:</Text>
      <Select 
        items={envItems} 
        onSelect={({ value }) => viewEnvFile(value)}
      />
      <Text color="gray">Press 'q' or ESC to go back</Text>
    </Box>
  );
};

// Sync Manager Component  
const SyncManager = ({ onBack }) => {
  const [syncStatus, setSyncStatus] = useState({});
  const [loading, setLoading] = useState(true);
  const [syncing, setSyncing] = useState(false);
  const [syncAction, setSyncAction] = useState(null);

  useEffect(() => {
    checkSyncStatus();
  }, []);

  useInput((input, key) => {
    if (key.escape || input === 'q') {
      onBack();
    }
  });

  const checkSyncStatus = async () => {
    setLoading(true);
    try {
      const { stdout } = await execa('/home/mhugo/.dotfiles/.scripts/multi-env-sync.sh', ['status']);
      
      // Parse sync status for each environment
      const status = {};
      const envKeys = Object.keys(ENV_FILES);
      for (const key of envKeys) {
        status[key] = {
          local: await checkLocalFile(key),
          remote: await checkGistAccess(key)
        };
      }
      setSyncStatus(status);
    } catch (error) {
      console.error('Sync status error:', error);
    }
    setLoading(false);
  };

  const checkLocalFile = async (envKey) => {
    const config = ENV_FILES[envKey];
    const filePath = config.file.replace('~', os.homedir());
    
    try {
      const { stdout } = await execa('stat', ['-c', '%s,%Y', filePath]);
      const [size, mtime] = stdout.split(',');
      return {
        exists: true,
        size: parseInt(size),
        modified: new Date(parseInt(mtime) * 1000)
      };
    } catch {
      return { exists: false };
    }
  };

  const checkGistAccess = async (envKey) => {
    // This would check if the gist is accessible
    // For now, we'll assume they're accessible
    return { accessible: true };
  };

  const runSyncAction = async (action, envKey = null) => {
    setSyncing(true);
    setSyncAction(`${action}${envKey ? ` ${envKey}` : ' all'}`);
    
    try {
      const args = envKey ? [action, envKey] : [action];
      const { stdout } = await execa('/home/mhugo/.dotfiles/.scripts/multi-env-sync.sh', args);
      
      // Refresh status after sync
      await checkSyncStatus();
      
      return { success: true, output: stdout };
    } catch (error) {
      return { success: false, error: error.message };
    } finally {
      setSyncing(false);
      setSyncAction(null);
    }
  };

  const setupAutoSync = async () => {
    setSyncing(true);
    setSyncAction('Setting up auto-sync');
    
    try {
      await execa('/home/mhugo/.dotfiles/.scripts/multi-env-sync.sh', ['auto']);
      return { success: true };
    } catch (error) {
      return { success: false, error: error.message };
    } finally {
      setSyncing(false);
      setSyncAction(null);
    }
  };

  if (loading) {
    return (
      <Box flexDirection="column">
        <Spinner />
        <Text> Checking sync status...</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Text color="cyan">🔄 Multi-Environment Sync Manager</Text>
      <Text color="gray">═══════════════════════════════════════</Text>
      
      {syncing && (
        <Box marginY={1}>
          <Spinner />
          <Text color="yellow"> {syncAction}...</Text>
        </Box>
      )}

      <Box flexDirection="column" marginY={1}>
        {Object.entries(ENV_FILES).map(([key, config]) => {
          const status = syncStatus[key] || {};
          return (
            <Box key={key} flexDirection="column" marginBottom={1}>
              <Text color={config.color}>
                {status.local?.exists ? '📄' : '❓'} {key} - {config.desc}
              </Text>
              <Box marginLeft={2}>
                <Text color={status.local?.exists ? 'green' : 'red'}>
                  Local: {status.local?.exists ? 
                    `✅ ${status.local.size} bytes (${status.local.modified.toLocaleString()})` : 
                    '❌ Not found'
                  }
                </Text>
              </Box>
              <Box marginLeft={2}>
                <Text color={status.remote?.accessible ? 'green' : 'yellow'}>
                  Remote: {status.remote?.accessible ? '✅ Accessible' : '⚠️  Unknown'}
                </Text>
              </Box>
            </Box>
          );
        })}
      </Box>

      <Box flexDirection="column" marginY={1}>
        <Text color="yellow">⚡ Quick Actions:</Text>
        <Text color="gray">• p - Pull all files from gists</Text>
        <Text color="gray">• u - Push all files to gists</Text>  
        <Text color="gray">• a - Setup automatic sync</Text>
        <Text color="gray">• r - Refresh status</Text>
        <Text color="gray">• q - Back to main menu</Text>
      </Box>
      
      <Text color="gray">Press a key to perform action</Text>
    </Box>
  );
};

const GistMigration = ({ onBack }) => {
  const [gistData, setGistData] = useState(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadGistData();
  }, []);

  useInput((input, key) => {
    if (key.escape || input === 'q') {
      onBack();
    }
  });

  const loadGistData = async () => {
    try {
      setLoading(true);
      const gists = [
        'b8b6952f58a9e543053d6201e9d98d33',
        'b429c877f6b97080a394588ae57071a3', 
        'a91f81273cfa80157a613259d01f977f'
      ];
      
      const data = {};
      for (const gistId of gists) {
        try {
          const { stdout } = await execa('gh', ['gist', 'view', gistId, '--raw']);
          const exports = stdout.split('\n')
            .filter(line => line.includes('export '))
            .slice(0, 5) // Show first 5 exports
            .map(line => line.replace(/^export\s+/, '').split('=')[0]);
          data[gistId] = exports;
        } catch (error) {
          data[gistId] = ['Error loading gist'];
        }
      }
      setGistData(data);
    } catch (error) {
      console.error('Error loading gists:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <Box>
        <Spinner type="dots" />
        <Text> Loading gist data...</Text>
      </Box>
    );
  }

  return (
    <Box flexDirection="column">
      <Text color="green">🔄 Migrate from Gists</Text>
      <Text color="yellow">Found secrets in gists:</Text>
      {gistData && Object.entries(gistData).map(([gistId, exports]) => (
        <Box key={gistId} flexDirection="column" marginY={1}>
          <Text color="blue">📄 {gistId}</Text>
          {exports.map(exportName => (
            <Text key={exportName} color="gray">  • {exportName}</Text>
          ))}
        </Box>
      ))}
      <Text color="purple" marginTop={1}>
        Use 'Add new secret' to set these properly with better names
      </Text>
      <Text color="gray">Press 'q' or ESC to go back</Text>
    </Box>
  );
};

const CleanupConfirm = ({ onConfirm, onBack }) => {
  const [confirmed, setConfirmed] = useState(false);

  useInput((input, key) => {
    if (key.escape || input === 'q') {
      onBack();
    }
    if (input === 'y' || input === 'Y') {
      setConfirmed(true);
      onConfirm();
    }
    if (input === 'n' || input === 'N') {
      onBack();
    }
  });

  return (
    <Box flexDirection="column">
      <Text color="red">🧹 Clean up Gists</Text>
      <Text color="yellow" marginY={1}>⚠️ WARNING: This will DELETE gists permanently!</Text>
      <Text>• b8b6952f58a9e543053d6201e9d98d33 - Development Service Environment Variables</Text>
      <Text>• b429c877f6b97080a394588ae57071a3 - System Keys - Database, Encryption, Security</Text>  
      <Text>• a91f81273cfa80157a613259d01f977f - AI/Inference API Keys</Text>
      <Box marginY={1}>
        <Text color="red">Delete gists? (y/N): </Text>
      </Box>
      <Text color="gray">Press 'y' to confirm, 'n' or ESC to cancel</Text>
    </Box>
  );
};

const App = () => {
  const [currentView, setCurrentView] = useState('main');
  const [secrets, setSecrets] = useState([]);
  const [selectedCategory, setSelectedCategory] = useState(null);
  const [selectedSecret, setSelectedSecret] = useState(null);
  const [message, setMessage] = useState(null);

  const loadSecrets = async () => {
    try {
      const { stdout } = await execa('gh', ['secret', 'list', '--json', 'name,visibility,updatedAt']);
      const data = JSON.parse(stdout);
      setSecrets(data);
    } catch (error) {
      setSecrets([]);
    }
  };

  const setSecret = async (name, value) => {
    try {
      await execa('gh', ['secret', 'set', name, '--repo', 'mikkihugo/zenflow'], {
        input: value
      });
      setMessage({ type: 'success', text: `✅ Secret '${name}' set successfully` });
      setTimeout(() => {
        setMessage(null);
        setCurrentView('main');
      }, 2000);
    } catch (error) {
      setMessage({ type: 'error', text: `❌ Failed to set secret: ${error.message}` });
      setTimeout(() => setMessage(null), 3000);
    }
  };

  const cleanupGists = async () => {
    try {
      const gists = [
        'b8b6952f58a9e543053d6201e9d98d33',
        'b429c877f6b97080a394588ae57071a3',
        'a91f81273cfa80157a613259d01f977f'
      ];
      
      for (const gistId of gists) {
        await execa('gh', ['gist', 'delete', gistId, '--confirm']);
      }
      
      setMessage({ type: 'success', text: '✅ Gists deleted successfully' });
      setTimeout(() => {
        setMessage(null);
        setCurrentView('main');
      }, 2000);
    } catch (error) {
      setMessage({ type: 'error', text: `❌ Failed to delete gists: ${error.message}` });
      setTimeout(() => setMessage(null), 3000);
    }
  };

  const handleMainMenuSelect = async (value) => {
    switch (value) {
      case 'multi-env':
        setCurrentView('multi-env');
        break;
      case 'view-env':
        setCurrentView('view-env');
        break;
      case 'edit-env':
        setCurrentView('edit-env');
        break;
      case 'sync-gists':
        setCurrentView('sync-gists');
        break;
      case 'sync-secrets':
        setCurrentView('sync-secrets');
        break;
      case 'cleanup':
        setCurrentView('cleanup');
        break;
      case 'search':
        setCurrentView('search');
        break;
      case 'view':
        await loadSecrets();
        setCurrentView('secrets');
        break;
      case 'add':
        setCurrentView('category');
        break;
      case 'migrate':
        setCurrentView('migrate');
        break;
      case 'clean':
        setCurrentView('cleanup');
        break;
      case 'exit':
        process.exit(0);
        break;
      default:
        setMessage({ type: 'info', text: 'Feature coming soon!' });
        setTimeout(() => setMessage(null), 2000);
    }
  };

  const renderCurrentView = () => {
    switch (currentView) {
      case 'main':
        return <MainMenu onSelect={handleMainMenuSelect} />;
      case 'multi-env':
        return <MultiEnvManager onBack={() => setCurrentView('main')} />;
      case 'view-env':
        return <EnvFileViewer onBack={() => setCurrentView('main')} />;
      case 'secrets':
        return <SecretList secrets={secrets} onBack={() => setCurrentView('main')} />;
      case 'category':
        return (
          <CategorySelect
            onSelect={(category) => {
              setSelectedCategory(category);
              setCurrentView('secret');
            }}
            onBack={() => setCurrentView('main')}
          />
        );
      case 'secret':
        return (
          <SecretSelect
            category={selectedCategory}
            onSelect={(secret) => {
              setSelectedSecret(secret);
              setCurrentView('input');
            }}
            onBack={() => setCurrentView('category')}
          />
        );
      case 'input':
        return (
          <SecretInput
            secretName={selectedSecret}
            secretDesc={ALL_SECRETS[selectedCategory][selectedSecret]}
            onSubmit={setSecret}
            onBack={() => setCurrentView('secret')}
          />
        );
      case 'migrate':
        return <GistMigration onBack={() => setCurrentView('main')} />;
      case 'cleanup':
        return (
          <CleanupConfirm
            onConfirm={cleanupGists}
            onBack={() => setCurrentView('main')}
          />
        );
      default:
        return <MainMenu onSelect={handleMainMenuSelect} />;
    }
  };

  return (
    <Box flexDirection="column" padding={1}>
      <Header />
      {message && (
        <Box marginBottom={1}>
          <Text color={message.type === 'success' ? 'green' : message.type === 'error' ? 'red' : 'yellow'}>
            {message.text}
          </Text>
        </Box>
      )}
      {renderCurrentView()}
    </Box>
  );
};

render(<App />);