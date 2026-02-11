# Universal System Cleaner

A powerful, safe, and configurable system cleanup script for Linux distributions with multiple operation modes: Production, Stealth, and Maximum.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](https://opensource.org/licenses/MIT)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](http://makeapullrequest.com)

## 🚀 Features

- **Multiple cleanup modes** tailored for different use cases
- **Safe by design** - protected directories never get touched
- **Zsh history preservation** - intelligent handling of shell history
- **Self-cleanup capability** - removes all traces (ghost mode)
- **Package manager support** - APT, DNF, Pacman, Snap, Flatpak
- **Log rotation & cleanup** - systemd, Apache, Nginx, custom logs
- **Backup option** - create backups before cleanup
- **Audit logging** - detailed logs of all operations

## 📋 Supported Distributions

- Ubuntu/Debian
- RHEL/CentOS/Fedora
- Arch Linux/Manjaro
- Other systemd-based distributions

## 🔧 Installation

```bash
# Clone repository
git clone https://github.com/yourusername/system-cleaner.git
cd system-cleaner

# Make script executable
chmod +x system-cleaner.sh

# Copy to system path (optional)
sudo cp system-cleaner.sh /usr/local/bin/system-cleaner
```

## 🎯 Usage

### Basic cleanup (safe mode)

```bash
sudo ./system-cleaner.sh
```

### Test run (see what will be cleaned)

```bash
sudo ./system-cleaner.sh --dry-run
```

### Stealth mode (minimal output)

```bash
sudo ./system-cleaner.sh --stealth
```

### Maximum cleanup (including caches)

```bash
sudo ./system-cleaner.sh --stealth-max
```

### Complete trace removal (ghost mode)

```bash
sudo ./system-cleaner.sh --ghost
```

### With backup

```bash
sudo ./system-cleaner.sh --backup --stealth-max
```

## 📊 Operation Modes

| Mode            | Description      | Output  | History                     | Logs       |
| --------------- | ---------------- | ------- | --------------------------- | ---------- |
| **Standard**    | Basic cleanup    | Full    | Preserved (50 Bash/100 Zsh) | Kept       |
| **Stealth**     | Basic cleanup    | Minimal | Cleared but files kept      | Kept       |
| **Stealth-Max** | Full cleanup     | Minimal | Last 1000 commands          | Partial    |
| **Ghost**       | Complete removal | None    | Completely deleted          | Deleted    |
| **Dry-Run**     | Test only        | Full    | No changes                  | No changes |

## 🛡️ Safety Features

### Protected Directories (Never Cleaned)

- `/proc`, `/sys`, `/dev`, `/boot`
- `/etc`, `/usr`, `/opt`, `/srv`
- `/var/lib`, `/root/.ssh`, `/home/*/.ssh`
- Docker, MySQL, PostgreSQL data directories

### Safe History Handling

- **Bash**: Preserves last 50 commands (standard mode)
- **Zsh**: Preserves last 1000 commands (stealth-max)
- **Ghost mode**: Complete secure deletion with shred
- **Active sessions**: Proper synchronization before cleanup

## 📁 Files Structure

```
system-cleaner/
├── system-cleaner.sh          # Main script
├── README.md                  # This file
├── LICENSE                    # MIT License
└── .gitignore                # Git ignore rules
```

### Backup Location

If `--backup` flag is used:

```
/var/backups/system-cleaner/YYYYMMDD_HHMMSS/
├── apt/                      # APT logs backup
├── apache2/                  # Apache logs
├── nginx/                    # Nginx logs
├── root_bash_history         # Root bash history
├── root_zsh_history          # Root zsh history
└── manifest.txt              # Backup manifest
```

### Audit Log

Default location: `/var/log/system-cleaner-audit.log`

## 🔍 What Gets Cleaned

### System Logs

- System logs (`/var/log/*.log`)
- Web server logs (Apache, Nginx)
- Package manager logs (APT, DPKG)
- Old log archives (`.gz`, `.bz2`, `.xz`)

### Temporary Files

- `/tmp`, `/var/tmp`, `/dev/shm` (files older than 1 day)
- Application-specific temp files

### Package Manager Caches

- APT: `apt clean`, `apt autoclean`
- DNF: `dnf clean all`
- Pacman: `pacman -Scc`
- Snap: `/var/lib/snapd/cache/`
- Flatpak: unused runtimes

### User Data

- Browser caches (Chrome, Firefox, Chromium)
- Thumbnail caches
- Recent files lists
- Trash contents
- VS Code/IDE caches

## ⚠️ Important Notes

1. **Always run with `--dry-run` first** to see what will be cleaned
2. **Use `--backup`** if you're unsure about cleanup
3. **Ghost mode is irreversible** - all traces including script itself will be deleted
4. **Root privileges required** - script checks for EUID=0
5. **Disk space check** - warns if disk usage >95%

## 🔄 Zsh History Handling

The script uses intelligent Zsh history management:

1. **Detects active Zsh sessions** and syncs them before cleanup
2. **Preserves history format** - doesn't corrupt Zsh history file structure
3. **Graceful degradation** - if `fc -W` fails, preserves last commands
4. **User permission preservation** - maintains correct file ownership

## 🐛 Troubleshooting

### "Permission denied" errors

Ensure you're running with sudo:

```bash
sudo ./system-cleaner.sh
```

### Zsh history not saving after cleanup

Run in standard mode first to test:

```bash
sudo ./system-cleaner.sh --dry-run
```

### Script doesn't work on my distribution

Check if your distribution is systemd-based:

```bash
systemctl --version
```

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## ⭐ Show Your Support

If you find this script useful, please give it a star on GitHub!

## 🙏 Acknowledgments

- Inspired by various system maintenance scripts
- Tested on multiple Linux distributions
- Community feedback for improvements

## 📞 Contact

For issues, questions, or suggestions:

- Open an [Issue](https://github.com/yourusername/system-cleaner/issues)
- Check [Discussions](https://github.com/yourusername/system-cleaner/discussions)

---

**⚠️ Disclaimer**: Use this script at your own risk. Always backup important data before system cleanup. The author is not responsible for any data loss or system issues.
