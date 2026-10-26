# Security Policy

## Supported versions
Only the latest release is supported. Update with `pbs-motd --update-installer`.

## Reporting a vulnerability
Please do **not** open a public issue for a security problem.
Use GitHub's "Report a vulnerability" button (Security tab) to write to me privately.

Helpful details: the script version (`pbs-post-install.sh --version`), what you
did, and what happened. I will answer as soon as I can and credit you in the
release notes if you want.

## What this script handles
It runs as root. It stores the iSCSI CHAP login in the root-only iSCSI node
record and never writes the password to its log. Alert settings are in
root-only files (mode 600).
