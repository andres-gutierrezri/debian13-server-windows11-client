# Publicación del proyecto en GitHub y GitLab

Guía comando por comando. Autor: Ingeniero Andrés Felipe Gutiérrez Rivera.
Cuentas: GitHub `andres-gutierrezri` · GitLab `andres.gutierrezri`.

## 1. Repositorio local

```bash
cd debian13-server-windows11-client
git init
git config user.name  "Andrés Felipe Gutiérrez Rivera"
git config user.email "felipe.gutierrezri@gmail.com"
git status
git add .
git commit -m "feat: versión inicial del entorno Debian 13 servidor y Windows 11 cliente"
git branch -M main
```

Opcional (global): `git config --global init.defaultBranch main`.

## 2. Crear los repositorios remotos (interfaz web)

- **GitHub:** <https://github.com/new> → nombre `debian13-server-windows11-client` → Public/Private → **sin** README, .gitignore ni licencia (ya existen) → *Create repository*.
- **GitLab:** <https://gitlab.com/projects/new> → *Create blank project* → mismo nombre → desmarcar *Initialize with a README* → *Create project*.

## 3. Autenticación

### Opción A — SSH (recomendada)

```bash
ssh-keygen -t ed25519 -C "felipe.gutierrezri@gmail.com" -f ~/.ssh/id_ed25519_git
eval "$(ssh-agent -s)" && ssh-add ~/.ssh/id_ed25519_git
cat ~/.ssh/id_ed25519_git.pub        # copie la salida
```

- GitHub: *Settings → SSH and GPG keys → New SSH key*.
- GitLab: *Preferences → SSH Keys*.

```bash
ssh -T git@github.com
ssh -T git@gitlab.com
```

En Windows (PowerShell): `ssh-keygen -t ed25519 -f $env:USERPROFILE\.ssh\id_ed25519_git`, luego `Get-Content ...\id_ed25519_git.pub | Set-Clipboard`. Asocie la llave en `~/.ssh/config`:

```
Host github.com gitlab.com
    User git
    IdentityFile ~/.ssh/id_ed25519_git
```

### Opción B — Token de acceso personal (PAT) por HTTPS

- GitHub: *Settings → Developer settings → Personal access tokens* → permiso `repo` (o *fine-grained* con *Contents: Read and write*).
- GitLab: *Preferences → Access Tokens* → ámbitos `read_repository`, `write_repository`.

```bash
git remote add origin https://github.com/andres-gutierrezri/debian13-server-windows11-client.git
git push -u origin main
# Usuario: su usuario | Contraseña: el PAT (no su contraseña de cuenta)
git config --global credential.helper store    # Linux (texto plano; use con cautela)
```

En Windows, **Git Credential Manager** guarda el token de forma segura. **Nunca** incluya tokens en el repositorio ni en el historial de la terminal compartida.

## 4. Vincular y publicar

```bash
git remote add origin git@github.com:andres-gutierrezri/debian13-server-windows11-client.git
git remote -v
git push -u origin main
```

## 5. Doble remoto

### Variante 1 — Dos remotos con nombre (explícita)

```bash
git remote add gitlab git@gitlab.com:andres.gutierrezri/debian13-server-windows11-client.git
git push -u origin main
git push -u gitlab main
```

### Variante 2 — Un solo `git push` hacia ambos

```bash
git remote set-url --add --push origin git@github.com:andres-gutierrezri/debian13-server-windows11-client.git
git remote set-url --add --push origin git@gitlab.com:andres.gutierrezri/debian13-server-windows11-client.git
git remote -v
git push origin main        # publica en GitHub y GitLab
```

> Al usar `--add --push`, el primer comando reemplaza el destino de *push* por defecto; por eso se añaden ambas URL.

## 6. Flujo de ramas (Git Flow simplificado)

| Rama | Propósito |
|---|---|
| `main` | Código estable, etiquetado |
| `develop` | Integración continua |
| `feature/<tema>` | Nuevas funciones |
| `release/<x.y.z>` | Preparación de versión |
| `hotfix/<tema>` | Correcciones urgentes sobre `main` |

```bash
git switch -c develop
git switch -c feature/hardening-ssh develop
# ... trabajo ...
git add -A && git commit -m "feat(ssh): desactivar autenticación por contraseña"
git switch develop && git merge --no-ff feature/hardening-ssh
git branch -d feature/hardening-ssh
git push -u origin develop
```

## 7. Conventional Commits

Formato: `<tipo>(<ámbito>): <descripción>`

| Tipo | Uso |
|---|---|
| `feat` | Nueva funcionalidad |
| `fix` | Corrección de errores |
| `docs` | Documentación |
| `chore` | Mantenimiento |
| `refactor` | Reestructuración sin cambio funcional |
| `test` | Pruebas |

Ejemplos: `docs(readme): añadir tabla de solución de problemas`, `fix(samba): corregir hosts allow`, `feat!: cambiar variables del .env` (el `!` indica cambio incompatible).

## 8. Versionado semántico (SemVer 2.0.0)

`MAJOR.MINOR.PATCH`: incompatible / funcionalidad compatible / corrección.

```bash
git switch main
git merge --no-ff develop
git tag -a v1.0.0 -m "Primera versión estable"
git push origin main develop --tags
git push gitlab main develop --tags     # si usa la variante 1
```

## 9. Comprobaciones finales

```bash
git log --oneline --graph --decorate -n 10
git ls-remote origin
git ls-remote gitlab
git status
```

Verifique en ambas interfaces web que `.env` **no** aparezca y que el README se renderice correctamente.
