# Hello Discord bot

This flake packages a Discord bot that responds to `/hello` and exports a
Nix-on-Droid module that decrypts its token and supervises the process.

The encrypted token is committed as `secrets/token.age`. The corresponding
private identity must exist outside the Nix store at:

```text
~/.config/age/nix-droid-discord-bot.key
```

After activating the phone configuration, the bot starts automatically. It is
also checked whenever a Nix-on-Droid login shell starts.

Useful commands:

```console
hello-discord-bot-status
hello-discord-bot-start
hello-discord-bot-stop
tail -f ~/.local/state/hello-discord-bot/service.log
```
