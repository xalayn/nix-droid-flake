# Secrets

Encrypted secret payloads live in this directory. The phone configuration
decrypts every entry in `age.secrets` during activation using the identities in
`age.identityPaths`.

The existing identity is intentionally reused for all secrets:

```nix
age.identityPaths = [
  "${config.user.home}/.config/age/nix-droid-discord-bot.key"
];
```

Its public recipient is safe to share and commit:

```text
age1t6kfkcsyzzq0wqd7hjpvgewyy5t6amwnq4p046k8g94vaerl0p4qr3kael
```

To add a secret, encrypt it to that recipient and declare it in the module that
uses it:

```nix
age.secrets."example" = {
  file = ../secrets/example.age;
  # Optional; defaults to ~/.local/state/nix-on-droid-secrets/example.
  path = "${config.user.home}/.local/state/example/token";
  # Optional; defaults to 0400.
  mode = "0400";
};
```

Activation decrypts all declared ciphertexts into a private staging directory
first. It replaces live secrets only after every decryption succeeds.

Only `.age` files are allowed through this repository's `.gitignore`. The
private identity must never enter Git. A fresh phone still needs that private
identity restored once at the configured path; the flake cannot safely contain
the key that decrypts itself.
