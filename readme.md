# Perzizt

## Overview

Perzizt is a lightweight, compiled persistence tool developed in Zig for establishing and maintaining access on Linux systems in controlled environments, such as capture-the-flag (CTF) competitions. It dynamically creates an obscure user account, configures SSH key-based authentication, sets up passwordless sudo privileges, and ensures redundancy through cron jobs and boot scripts. Additionally, it incorporates log sanitization to minimize detection footprints. This tool is designed for educational purposes and ethical hacking scenarios, emphasizing self-reinforcing mechanisms to restore access in the event of partial cleanups.

> **Note**: This was made for fun and learning zig 0.15.1. It will not compile with earlier versions and should be considered a toy at best.

## Features

- **Dynamic User Creation**: Checks for the existence of a specified obscure user (e.g., `_sysmaint`) and creates it only if absent, including home directory setup and group assignment (e.g., sudo).
- **SSH Key Configuration**: Appends a hardcoded public SSH key to the user's `authorized_keys` file with appropriate permissions.
- **Sudo Privileges**: Grants passwordless sudo access via a dedicated sudoers file.
- **Redundant Persistence**:
  - Appends a cron job entry to `/etc/crontab` for periodic execution (e.g., every 5 minutes).
  - Ensures boot-time execution by modifying `/etc/rc.local` (with fallback creation if missing).
- **Self-Reinforcement**: The binary verifies and recreates both cron and boot entries during each run, creating a mutual restoration loop.
- **Log Cleaning**: Selectively filters common authentication logs (e.g., `/var/log/auth.log`, `/var/log/secure`) to remove traces of user creation and related keywords, performed only after modifications.
- **Stealth-Oriented Design**: Compiled binary for efficiency and obfuscation; customizable constants for usernames, keys, and paths.

## Requirements

- Zig compiler (version 0.15.1 or later required).
- Root access on the target Linux system (e.g., Ubuntu, Debian, CentOS).
- Compatible with systemd-based distributions; may require adaptations for others.

## Installation

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/perzizt.git
   cd perzizt
   ```

2. Customize constants in `main.zig`:
   - Edit `username`, `pub_key`, `binary_path`, `cron_entry`, and other variables as needed.

3. Build the binary:
   ```
   zig build
   ```
   You might have to specify the target depending on your setup and target OS.

4. Transfer the binary to the target system and make it executable.
   ```
   scp zig-out/bin/perzizt root@target:~/obscure_name
   ssh root@target 'chmod +x ~/obscure_name'

## Usage

1. Execute the binary manually on the target as root to initialize:
   ```
    ssh root@target '~/obscure_name'
   ```

   This creates the user (if needed), sets up SSH and sudo, adds cron and boot entries, automatically moves itself to the binary_path specified, and cleans logs.

2. Every 5 mins binary will automatically run via cron as well as anytime the system is rebooted, checking and restoring components as necessary.

3. Access the system via SSH using the configured key:
   ```
   ssh username@target -i ~/.ssh/priv_key
   ```

## Configuration

All key parameters are defined as constants at the top of `main.zig` for easy modification:

- `username`: The obscure username to create (e.g., `_sysmaint`).
- `pub_key`: Your premade public SSH key.
- `binary_path`: Installation path of the binary (e.g., `/sbin`, `/usr/local/sbin`, etc)
- `cron_entry`: Cron schedule (e.g., `*/5 * * * * root /path/to/binary`).
- `log_paths` and `clean_keywords`: Arrays for log files and filter terms.

Recompile after changes to apply updates.

## Disclaimer

Perzizt is intended solely for educational and authorized use in CTF competitions or penetration testing engagements with explicit permission. Misuse for unauthorized access violates ethical standards and may be illegal. The author assumes no responsibility for any consequences arising from its application. Always ensure compliance with applicable laws and remove persistence mechanisms after use.

## Acknowledgements

Shout out to @i8degrees for spending the afternoon exploring the zig 0.15 changes with me.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
