<!-- PROJECT LOGO -->
<div align="center">
  <h1 align="center">menv</h1>
  <p align="center">A command line tool to manage environment variables on macOS</p>
</div>

<!-- SHIELDS -->
<div align="center">

[![Contributors][contributors-shield]][contributors-url]
[![Forks][forks-shield]][forks-url]
[![Stargazers][stars-shield]][stars-url]
[![Issues][issues-shield]][issues-url]
[![MIT License][license-shield]][license-url]

</div>

## 🚀 Overview

`menv` simplifies user-scope environment variable management on macOS by handling the complexity of making variables available to both GUI applications and terminal sessions across different contexts:

- **GUI Applications** (VS Code, browsers, etc.) via `launchctl`
- **Terminal Sessions** (bash, zsh, fish) via shell profiles
- **Persistent across reboots** via LaunchAgent plists and profile files

## 📋 Table of Contents

- [Installation](#-installation)
- [Quick Start](#-quick-start)
- [Commands](#-commands)
- [PATH-like Variables](#-path-like-variables)
- [Sources Managed](#-sources-managed)
- [Examples](#-examples)
- [Advanced Usage](#-advanced-usage)
- [Troubleshooting](#-troubleshooting)

## 🛠 Installation

1. **Download the script:**
   ```bash
   curl -O https://raw.githubusercontent.com/thgossler/menv/refs/heads/main/menv.sh
   chmod +x menv.sh
   ```

2. **Make it globally available (optional):**
   ```bash
   sudo cp menv.sh /usr/local/bin/menv
   ```

3. **Verify installation:**
   ```bash
   ./menv.sh --help
   # or if installed globally:
   menv --help
   ```

## ⚡ Quick Start

```bash
# List all environment variables
menv list

# Add a new environment variable
menv add MY_API_KEY "abc123def456"

# Add Java home
menv set JAVA_HOME "/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home"

# Add a directory to PATH
menv add-path PATH "/usr/local/custom/bin"

# View detailed information about a variable
menv info PATH

# Remove a variable
menv delete OLD_VARIABLE
```

## 📖 Commands

### `list` - List Environment Variables

Shows all environment variables in a clean table format.

```bash
# List all variables
menv list

# Example output:
# NAME                    VALUE                                           SOURCES
# ----------------------- ----------------------------------------------- -----------
# HOME                    /Users/john                                     inherited
# PATH                    /usr/local/bin:/usr/bin:/bin                    launchctl
# MY_API_KEY              abc123def456                                    launchctl, shell-profile
```

### `add` / `set` - Add or Set Variables

Creates or updates an environment variable. Both commands work identically.

```bash
# Basic usage
menv add VARIABLE_NAME "value"
menv set VARIABLE_NAME "value"

# Examples
menv add API_KEY "your-secret-key"
menv set EDITOR "code"
menv add JAVA_OPTS "-Xmx2g -Xms1g"
```

**For PATH-like variables**, you'll be prompted with options:
```bash
menv add PATH "/new/directory"
# Prompts:
# 1) Append to existing PATH (recommended)
# 2) Prepend to existing PATH  
# 3) Replace entire PATH (dangerous!)
```

### `delete` / `del` / `remove` - Remove Variables

Removes a variable from all locations where it's defined.

```bash
# Remove a variable
menv delete VARIABLE_NAME

# Force removal without confirmation
menv --force delete VARIABLE_NAME

# Examples
menv delete OLD_API_KEY
menv delete DEPRECATED_VAR
```

### `add-path` - Add PATH Entries

Safely adds directories to PATH-like variables without prompting.

```bash
# Add to PATH (appends by default)
menv add-path PATH "/usr/local/custom/bin"

# Add to other PATH-like variables
menv add-path LIBRARY_PATH "/usr/local/lib"
menv add-path PYTHONPATH "/usr/local/python/modules"
```

### `remove-path` - Remove PATH Entries

Removes specific directories from PATH-like variables.

```bash
# Remove from PATH
menv remove-path PATH "/old/directory"

# Remove from other PATH-like variables  
menv remove-path LIBRARY_PATH "/deprecated/lib"
```

### `info` - Variable Information

Shows detailed information about a specific variable.

```bash
# Get detailed info
menv info VARIABLE_NAME

# Example output for PATH:
# Current environment: /usr/local/bin:/usr/bin:/bin
# 
# Launchctl status:
#   ✓ launchctl: /usr/local/bin:/usr/bin:/bin
# 
# Shell profile status:
#   ✗ Not found in configuration files
# 
# Fresh shell test:
#   ✓ Fresh shell would see: /usr/local/bin:/usr/bin:/bin
```

### `test` - Test Variables

Verifies that a variable works in fresh shell and GUI environments.

```bash
# Test a variable
menv test MY_API_KEY

# Example output:
# ✓ Variable 'MY_API_KEY' is set to: abc123def456
# ✓ Variable 'MY_API_KEY' is set in launchctl: abc123def456
```

### `analyze` - Analyze PATH Variables

Analyzes PATH-like variables for duplicates, missing directories, and composition.

```bash
# Analyze PATH
menv analyze PATH

# Example output shows:
# - All PATH entries with existence status
# - Duplicate detection
# - Source analysis
# - Recommendations for cleanup
```

## 🛤 PATH-like Variables

The following variables receive special treatment for path management:

- `PATH`
- `LIBRARY_PATH`
- `LD_LIBRARY_PATH`
- `DYLD_LIBRARY_PATH`
- `PKG_CONFIG_PATH`
- `MANPATH`
- `INFOPATH`
- `CLASSPATH`
- `PYTHONPATH`
- `NODE_PATH`

### Special Behavior

- **`add` command**: Prompts for append/prepend/replace options
- **`add-path` command**: Always appends safely
- **`remove-path` command**: Removes specific entries
- **`delete` command**: Warns about removing entire variable
- **`analyze` command**: Shows composition and duplicates

## 📁 Sources Managed

`menv` manages environment variables across multiple sources:

| Source | Description | Purpose |
|--------|-------------|---------|
| **`launchctl`** | User launchctl environment | GUI applications |
| **`shell-profile`** | Shell profile files | Terminal sessions |
| **`user-plist`** | LaunchAgent plist files | Persistence across reboots |
| **`macos-environment-plist`** | Legacy environment.plist | Backwards compatibility |
| **`inherited`** | System/parent process variables | Context only (read-only) |

### Shell Profiles Supported

- `~/.zshrc` (Zsh)
- `~/.bash_profile` (Bash)
- `~/.bashrc` (Bash)
- `~/.profile` (Generic)
- `~/.zshenv` (Zsh)
- `~/.bash_login` (Bash)
- `~/.zprofile` (Zsh)
- `~/.config/fish/config.fish` (Fish shell)

## 💡 Examples

### Development Environment Setup

```bash
# Set up Node.js development
menv add NODE_ENV "development"
menv add-path PATH "$HOME/.npm-global/bin"
menv add-path NODE_PATH "$HOME/.npm-global/lib/node_modules"

# Set up Python development
menv add PYTHONPATH "$HOME/python/modules"
menv add-path PATH "$HOME/.local/bin"

# Set up Java development
menv set JAVA_HOME "/Library/Java/JavaVirtualMachines/jdk-17.jdk/Contents/Home"
menv add-path PATH "$JAVA_HOME/bin"
```

### API Keys and Secrets

```bash
# Add API keys (be careful with sensitive data!)
menv add OPENAI_API_KEY "your-api-key-here"
menv add GITHUB_TOKEN "your-github-token"
menv add DATABASE_URL "postgresql://user:pass@localhost/db"

# Set default applications
menv set EDITOR "code"
menv set BROWSER "firefox"
```

### Custom Tool Paths

```bash
# Add Homebrew paths
menv add-path PATH "/opt/homebrew/bin"
menv add-path PATH "/opt/homebrew/sbin"

# Add custom binary directories
menv add-path PATH "$HOME/bin"
menv add-path PATH "$HOME/.local/bin"
menv add-path PATH "/usr/local/custom/bin"
```

### Managing Existing Variables

```bash
# Check what's currently set
menv list | grep API

# Get detailed information
menv info PATH
menv info JAVA_HOME

# Analyze PATH for problems
menv analyze PATH

# Clean up old variables
menv delete OLD_API_KEY
menv delete DEPRECATED_PATH
```

### Batch Operations

```bash
# Set multiple related variables
menv add AWS_REGION "us-west-2"
menv add AWS_DEFAULT_REGION "us-west-2"
menv add AWS_OUTPUT "json"

# Remove multiple old variables
menv --force delete OLD_VAR_1
menv --force delete OLD_VAR_2
menv --force delete OLD_VAR_3
```

## 🔧 Advanced Usage

### Options

- **`-f, --force`**: Skip confirmation prompts
- **`-v, --verbose`**: Enable debug output
- **`-h, --help`**: Show help message

### Verbose Mode

```bash
# See what the tool is doing internally
menv --verbose add MY_VAR "value"
menv --verbose list
```

### Force Mode

```bash
# Skip all confirmation prompts
menv --force delete RISKY_VARIABLE
menv --force add PATH "/risky/path"
```

### PATH Management Strategies

```bash
# Safe PATH addition (recommended)
menv add-path PATH "/new/directory"

# Interactive PATH modification with choices
menv add PATH "/new/directory"

# Analyze before modifying
menv analyze PATH
menv add-path PATH "/optimized/path"
menv analyze PATH  # Check the result
```

## 🩺 Troubleshooting

### Variable Not Available in GUI Apps

```bash
# Check if it's set in launchctl
menv info MY_VARIABLE

# If not in launchctl, add it properly
menv add MY_VARIABLE "value"

# Restart GUI applications to pick up changes
```

### Variable Not Available in Terminal

```bash
# Check shell profile status
menv info MY_VARIABLE

# Open a new terminal session
# or source your profile manually:
source ~/.zshrc  # or your shell's profile
```

### PATH Issues

```bash
# Analyze PATH for problems
menv analyze PATH

# Common issues and solutions:
# - Duplicates: Remove and re-add paths
# - Missing directories: Remove non-existent paths  
# - Wrong order: Use prepend instead of append

# Fix duplicate homebrew paths
menv remove-path PATH "/opt/homebrew/bin"  # remove duplicate
menv add-path PATH "/opt/homebrew/bin"     # add once
```

### Backup and Restore

The tool automatically creates backups before modifying files:

```bash
# Backups are created in the same directory with timestamp
# Example: ~/.zshrc.backup.20240920_143022

# To restore a backup:
cp ~/.zshrc.backup.20240920_143022 ~/.zshrc
```

### Common Error Messages

**"Variable name cannot be empty"**
```bash
# Fix: Provide a variable name
menv add "" "value"          # ❌ Wrong
menv add MY_VARIABLE "value" # ✅ Correct
```

**"Administrator privileges required"**
```bash
# This shouldn't happen with user-scope operations
# If you see this, there might be a bug - please report it
```

**"Variable not found"**
```bash
# The variable doesn't exist in managed locations
menv info NON_EXISTENT_VAR
# Check if it's inherited:
menv list | grep NON_EXISTENT_VAR
```

## 📝 Notes

- **GUI Applications**: Need to be restarted to see new environment variables
- **Terminal Sessions**: Need to be reopened or profiles re-sourced
- **Persistence**: Variables are automatically persistent across reboots
- **Safety**: Only manages user-scope variables, never requires sudo
- **Backups**: Automatically creates backups before modifying files

## 💰​ Donate

If you are using the tool but are unable to contribute technically, please consider promoting it and donating an amount that reflects its value to you. You can do so either via PayPal

[![Donate via PayPal](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/donate/?hosted_button_id=JVG7PFJ8DMW7J)

or via [GitHub Sponsors](https://github.com/sponsors/thgossler).

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b my-feature`
3. Make your changes
4. Test thoroughly on macOS
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙋 Support

If you encounter issues:

1. Check the troubleshooting section above
2. Run with `--verbose` to see detailed output
3. Check that you're on a supported macOS version
4. Open an issue with detailed information about your environment


<!-- MARKDOWN LINKS & IMAGES (https://www.markdownguide.org/basic-syntax/#reference-style-links) -->
[contributors-shield]: https://img.shields.io/github/contributors/thgossler/menv.svg
[contributors-url]: https://github.com/thgossler/menv/graphs/contributors
[forks-shield]: https://img.shields.io/github/forks/thgossler/menv.svg
[forks-url]: https://github.com/thgossler/menv/network/members
[stars-shield]: https://img.shields.io/github/stars/thgossler/menv.svg
[stars-url]: https://github.com/thgossler/menv/stargazers
[issues-shield]: https://img.shields.io/github/issues/thgossler/menv.svg
[issues-url]: https://github.com/thgossler/menv/issues
[license-shield]: https://img.shields.io/github/license/thgossler/menv.svg
[license-url]: https://github.com/thgossler/menv/blob/main/LICENSE
