# Codex Configuration

**Pay-as-you-go MiMo API** and **Token Plan** both support Codex. Refer to this guide for configuration and usage.

<div className='mdx-highlight'>

MiMo Models are not yet compatible with the Responses API and are only supported by older versions of Codex that use the ChatCompletions API.

</div>

## Prerequisites

### Obtain Credentials 

Supports two usage methods, but the corresponding credential acquisition methods are different:

<table>
<colgroup>
<col />
<col style="width: 191px" />
<col style="width: 700px" />
</colgroup>
<thead>
<tr>
<th>Usage Method</th>
<th>Description</th>
<th>Acquisition Method (BASE_URL and API Key below are examples)</th>
</tr>
</thead>
<tbody>
<tr>
<td>Pay-as-you-go MiMo API</td>
<td>Charged based on actual usage, suitable for light use</td>
<td><ul><li>BASE_URL<ul><li>OpenAI Compatibility Protocol: `https://api.xiaomimimo.com/v1`</li><li>Anthropic Compatibility Protocol: `https://api.xiaomimimo.com/anthropic`</li></ul></li><li>API Key<ul><li>Format: `sk-xxxxx`</li></ul></li></ul><br />Go to [API Keys](https://platform.xiaomimimo.com/#/console/api-keys) to create an API Key</td>
</tr>
<tr>
<td>Token Plan</td>
<td>Fixed subscription fee, with limited calls based on the package</td>
<td><ul><li>BASE_URL<ul><li>OpenAI Compatibility Protocol: `https://token-plan-cn.xiaomimimo.com/v1`</li><li>Anthropic Compatibility Protocol: `https://token-plan-cn.xiaomimimo.com/anthropic`</li></ul></li><li>API Key<ul><li>Format: `tp-xxxxx`</li></ul></li></ul><br />After successful subscription, go to [Subscription](https://platform.xiaomimimo.com/#/console/plan-manage) to obtain the exclusive Base URL and API Key</td>
</tr>
</tbody>
</table>

## Use Codex CLI

### Install Codex CLI

**Prerequisites:** Node.js 18 or a later version must be installed first.

**Installation command (here, version 0.80.0 is used as an example):**

```bash
npm install -g @openai/codex@0.80.0
```

**Verify the installation (a version number output indicates success):**

```bash
codex --version
```

### Edit Configuration File

**1.**  **Edit or create the configuration file**

Configuration file path:

- macOS/Linux: `~/.codex/config.toml`

- Windows: `User directory\.codex\config.toml`

Copy the following content into the configuration file:

<div className='mdx-highlight'>

When configuring basic information, you need to first check if the `MIMO_API_KEY` environment variable exists. If it does, please clear it or replace the value with the API Key obtained through the corresponding usage method.

</div>

```python
model = "mimo-v2.5-pro"
model_provider = "mimo"

[model_providers.mimo]
name = "mimo"
env_key = "MIMO_API_KEY"
base_url = "BASE_URL"
wire_api = "chat"
```

**2.**  **Configure the environment variable** `MIMO_API_KEY`

- macOS/Linux

```bash
echo 'export MIMO_API_KEY="MIMO_API_KEY"' >> ~/.bashrc
source ~/.bashrc
```

- Windows (CMD)

```bash
# Run the following command in CMD
setx MIMO_API_KEY "MIMO_API_KEY"

# After success, open a new command prompt and run the following to verify the variable is set.
echo %MIMO_API_KEY%
```

### Use Codex CLI

After completing the above configuration, open a new terminal and run the following command to start Codex CLI:

```bash
codex
```

Once started, skip the update prompt to begin using MiMo models in Codex CLI.

<img src="./images/XbN6bjAeVoSTOwx6q55cip4nnic.png" alt="图片" style="margin: 16px auto;" />

## FAQ

### Codex CLI shows the following red warning?

> Support for the "chat" wire API is deprecated and will soon be removed. Update your model provider definition in config.toml to use wire_api ="responses".

<img src="./images/TfaqbJFqhoiUEuxWgCMcv0SKnqg.png" alt="图片" style="margin: 16px auto;" />

Don't worry, it works normally. Newer versions of Codex no longer support `wire_api = "chat"`. If you encounter the error `wire_api = chat is no longer supported`, please downgrade the Codex version.
