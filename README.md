# Mia — My Intelligent Agents

Downloads do Mia para Mac (Apple Silicon). O código fica num repositório privado; aqui ficam só as versões.

## Instalar

1. Baixe o `Mia-<versão>.dmg` da [última versão](https://github.com/richardoliveira/Mia-releases/releases/latest).
2. Abra o DMG e arraste **Mia** para **Aplicativos**.
3. Abra o Mia. Vai aparecer "A Apple não pôde verificar…". Clique em **OK**.
4. Abra **Ajustes do Sistema › Privacidade e Segurança**, role até "Mia foi bloqueado" e clique em **Abrir Mesmo Assim**.
5. Abra o Mia de novo e clique em **Abrir Mesmo Assim**.
6. Instale e faça login no [Claude Code](https://docs.claude.com/claude-code) e no [Codex](https://github.com/openai/codex).

Para quem usa o Terminal, no lugar dos passos 3 a 5:

```
xattr -dr com.apple.quarantine /Applications/Mia.app
```

O aviso da Apple só aparece na primeira instalação.

## Atualizações

O Mia se atualiza sozinho: quando sai uma versão nova, ele mostra **Atualizar para vX** ao lado de Configurações. O motor
também se atualiza sozinho quando não há nenhuma sessão rodando. Cada versão é assinada; o Mia só instala o que a assinatura
confirma.

- `app-vX.Y.Z`: o app (DMG).
- `motor-vX.Y.Z`: o motor (Mac, Linux e Windows).
