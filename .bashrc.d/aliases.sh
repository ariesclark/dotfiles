# On WSL the 1Password CLI is the Windows binary, reached over interop.
command -v op.exe > /dev/null && alias op=op.exe
